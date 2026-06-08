import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private var snoozeLocationManager: SnoozeLocationManager?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        // Register StopSnoozer's native channels once the engine is live
        snoozeLocationManager = SnoozeLocationManager(
            messenger: engineBridge.pluginRegistry.registrar(
                forPlugin: "SnoozeLocationManager"
            ).messenger()
        )
    }
}
