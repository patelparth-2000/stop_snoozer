import CoreLocation
import CoreMotion
import Flutter
import UIKit

/// Manages both above-ground CLLocationManager geofencing and subterranean
/// CMMotionManager dead-reckoning for StopSnoozer on iOS.
///
/// Registered against the Flutter MethodChannel "com.stopsnoozer.app/location"
/// and EventChannel "com.stopsnoozer.app/alarm_stream".
@objc
class SnoozeLocationManager: NSObject {

    // ── Flutter channels ───────────────────────────────────────────────────
    private let methodChannel: FlutterMethodChannel
    private let eventChannel:  FlutterEventChannel
    private var eventSink:     FlutterEventSink?

    // ── CoreLocation ────────────────────────────────────────────────────────
    private let locationManager = CLLocationManager()
    private var monitoredRegion: CLCircularRegion?

    // ── CoreMotion dead-reckoning ───────────────────────────────────────────
    private let motionManager = CMMotionManager()
    private var targetStopCount     = 0
    private var currentStopCount    = 0
    private var trainIsMoving       = false
    private var deadReckoningTimer: Timer?

    // Motion thresholds (m/s²)
    private static let accelerationThreshold:  Double = 0.15
    private static let stationaryThreshold:    Double = 0.02
    // Fallback timer if motion is unavailable: 7 minutes
    private static let fallbackTimerInterval:  TimeInterval = 420

    // ── Target state ────────────────────────────────────────────────────────
    private var targetStopId:   String = ""
    private var targetStopName: String = ""

    // ── Init ────────────────────────────────────────────────────────────────

    init(messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "com.stopsnoozer.app/location",
            binaryMessenger: messenger)
        eventChannel = FlutterEventChannel(
            name: "com.stopsnoozer.app/alarm_stream",
            binaryMessenger: messenger)

        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest

        eventChannel.setStreamHandler(self)
        methodChannel.setMethodCallHandler(handleMethodCall)
    }

    // ── MethodChannel dispatch ─────────────────────────────────────────────

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            if call.method == "stopActiveTracking" {
                stopAllTracking()
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
            return
        }

        switch call.method {
        case "startAboveGroundTracking":
            guard
                let id     = args["id"]     as? String,
                let lat    = args["lat"]    as? Double,
                let lng    = args["lng"]    as? Double,
                let radius = args["radius"] as? Double
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            startGeofencing(stopId: id, lat: lat, lon: lng, radius: radius)
            result(nil)

        case "startUndergroundTracking":
            guard
                let id   = args["id"]         as? String,
                let name = args["targetName"] as? String,
                let stop = args["targetSsid"] as? Int  // stop index used as proxy
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            startDeadReckoning(stopId: id, stopName: name, targetStopIndex: stop)
            result(nil)

        case "stopActiveTracking":
            stopAllTracking()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ── Above-ground: CLCircularRegion geofencing ──────────────────────────

    private func startGeofencing(stopId: String, lat: Double, lon: Double, radius: Double) {
        stopAllTracking()
        targetStopId   = stopId
        targetStopName = stopId   // name resolved from Dart layer

        let clampedRadius = min(radius, locationManager.maximumRegionMonitoringDistance)
        let centre        = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let region        = CLCircularRegion(center: centre, radius: clampedRadius, identifier: stopId)
        region.notifyOnEntry = true
        region.notifyOnExit  = false

        requestAlwaysAuthorizationIfNeeded()
        locationManager.startMonitoring(for: region)
        monitoredRegion = region
    }

    private func requestAlwaysAuthorizationIfNeeded() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        }
    }

    // ── Subterranean: CMMotionManager dead-reckoning ───────────────────────

    /// Counts train platform stops using accelerometer/gyroscope kinematics.
    /// Fires the alarm when `targetStopIndex` arrivals have been detected.
    private func startDeadReckoning(stopId: String, stopName: String, targetStopIndex: Int) {
        stopAllTracking()
        targetStopId    = stopId
        targetStopName  = stopName
        targetStopCount = targetStopIndex
        currentStopCount = 0
        trainIsMoving    = false

        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1  // 10 Hz
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }
                self.processMotionUpdate(motion)
            }
        } else {
            // Fallback: fixed-interval timer based on average inter-station time
            deadReckoningTimer = Timer.scheduledTimer(
                withTimeInterval: Self.fallbackTimerInterval * Double(max(targetStopIndex, 1)),
                repeats: false
            ) { [weak self] _ in
                self?.fireAlarm(distanceMetres: 0)
            }
        }
    }

    /// Detects acceleration → stationary transitions to count platform arrivals.
    private func processMotionUpdate(_ motion: CMDeviceMotion) {
        let userAcc = motion.userAcceleration
        // Magnitude of user acceleration vector (gravity-free)
        let magnitude = sqrt(userAcc.x * userAcc.x +
                             userAcc.y * userAcc.y +
                             userAcc.z * userAcc.z)

        if magnitude > Self.accelerationThreshold {
            trainIsMoving = true
        } else if trainIsMoving && magnitude < Self.stationaryThreshold {
            // Train was moving and has now stopped — count a station
            trainIsMoving = false
            currentStopCount += 1

            if currentStopCount >= targetStopCount {
                fireAlarm(distanceMetres: 0)
            }
        }
    }

    // ── Alarm dispatch ─────────────────────────────────────────────────────

    private func fireAlarm(distanceMetres: Double) {
        stopAllTracking()
        let payload: [String: Any] = [
            "stopId":         targetStopId,
            "stopName":       targetStopName,
            "distanceMetres": distanceMetres,
        ]
        eventSink?(payload)
        triggerHaptics()
    }

    private func triggerHaptics() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        // Repeat haptic every 1s using a retained strong reference
        var count = 0
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            generator.notificationOccurred(.error)
            count += 1
            if count >= 30 { timer.invalidate() }   // Stop after 30s
        }
    }

    // ── Cleanup ────────────────────────────────────────────────────────────

    private func stopAllTracking() {
        // Stop geofence monitoring
        if let region = monitoredRegion {
            locationManager.stopMonitoring(for: region)
            monitoredRegion = nil
        }
        // Stop motion
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        // Stop fallback timer
        deadReckoningTimer?.invalidate()
        deadReckoningTimer = nil
    }
}

// ── CLLocationManagerDelegate ──────────────────────────────────────────────

extension SnoozeLocationManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager,
                         didEnterRegion region: CLRegion) {
        guard region.identifier == targetStopId else { return }
        // Calculate approximate distance from region boundary
        let distanceMetres: Double
        if let userLocation = manager.location,
           let circularRegion = region as? CLCircularRegion {
            distanceMetres = max(0, userLocation.distance(
                from: CLLocation(latitude: circularRegion.center.latitude,
                                 longitude: circularRegion.center.longitude)
            ) - circularRegion.radius)
        } else {
            distanceMetres = 0
        }
        fireAlarm(distanceMetres: distanceMetres)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways,
           let region = monitoredRegion {
            manager.startMonitoring(for: region)
        }
    }
}

// ── FlutterStreamHandler ───────────────────────────────────────────────────

extension SnoozeLocationManager: FlutterStreamHandler {

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
