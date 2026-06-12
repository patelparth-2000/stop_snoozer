abstract final class StringConstants {
  // App
  static const String appName    = 'StopSnoozer';
  static const String appTagline = 'Never Miss Your Stop Again';

  // Splash
  static const String splashInitialising      = 'Initialising System…';
  static const String splashDecompressing     = 'Decompressing UK Stop Database';
  static const String splashReady             = 'System Ready';
  static const String splashPermTitle         = 'Before we begin';
  static const String splashPermSubtitle      = 'StopSnoozer needs a few permissions to keep you safe on your commute.';
  static const String splashPermLocation      = 'Precise Location';
  static const String splashPermLocationDesc  = 'Required for GPS geofencing above ground';
  static const String splashPermNotification  = 'Notifications';
  static const String splashPermNotifDesc     = 'To alert you when approaching your stop';
  static const String splashPermBgLocation    = 'Background Location';
  static const String splashPermBgLocationDesc = 'Must be "Allow all the time" — required for alarms to fire when the app is closed. After granting precise location, you\'ll be taken to App Settings to enable this.';
  static const String splashPermFullScreen    = 'Alarm Display';
  static const String splashPermFullScreenDesc = 'Required on Android 14+ to show the alarm over the lock screen and above other apps. You\'ll be taken to App Settings to enable this.';
  static const String splashPermBattery       = 'Battery Optimisation Exemption';
  static const String splashPermBatteryDesc   = 'Prevents the OS from killing the tracking service';
  static const String splashPermContinue      = 'Grant Permissions & Continue';
  static const String splashPermSkip          = 'Skip for now';

  // Dashboard
  static const String dashboardGreetingMorning   = 'Good morning, Commuter';
  static const String dashboardGreetingAfternoon = 'Good afternoon, Commuter';
  static const String dashboardGreetingEvening   = 'Good evening, Commuter';
  static const String dashboardDetectedNear      = 'DETECTED NEAR';
  static const String dashboardNoLocation        = 'LOCATING…';
  static const String dashboardActiveJourney     = 'Active Journey';
  static const String dashboardNoTrip            = 'No active trip';
  static const String dashboardNoTripSub         = 'Search for a destination to get started';
  static const String dashboardSearchCta         = 'Search Destination / Plan New Trip';
  static const String dashboardGeofenceActive    = 'GPS Geofence Active';
  static const String dashboardWifiActive        = 'Wi-Fi Sensing Active';
  static const String dashboardIdleBattery       = '0% Idle Battery';
  static const String dashboardLegActive         = 'ACTIVE';
  static const String dashboardLegQueued         = 'QUEUED';
  static const String dashboardLegComplete       = 'COMPLETE';

  // Search
  static const String searchHint          = 'Where do you need to be? We\'ll make sure you don\'t miss it. (e.g. Stratford, Victoria…)';
  static const String searchPlaceholder   = 'Search for a stop';
  static const String searchPlaceholderSub = 'Start typing a station, stop or area';
  static const String searchNoResults          = 'No stops found for';
  static const String searchMiles              = 'mi';
  static const String searchPostcodeNotFound   = 'Postcode not found — check spelling and try again';
  static const String searchPostcodeHint       = 'Postcode detected — showing nearest stops';
  static const String searchFilterAll          = 'All';
  static const String searchFilterBus          = 'Bus';
  static const String searchFilterTube         = 'Tube & DLR';
  static const String searchFilterRail         = 'Rail';

  // Trip Config
  static const String tripConfigTitle    = 'Review Your Trip Playlist';
  static const String tripConfigAddLeg   = '+ Add Transit Step';
  static const String tripConfigArm      = 'Arm System';
  static const String tripConfigClear    = 'Clear';
  static const String tripConfigRadius   = 'Wake Radius';
  static const String tripConfigMetres   = 'm';
  static const String tripConfigStyle    = 'Alarm Style';
  static const String tripConfigSubtle   = 'Subtle Pulse Vibe';
  static const String tripConfigDefcon   = 'Defcon Wakeup Drill';

  // Alarm
  static const String alarmWakeUp      = 'WAKE UP!';
  static const String alarmApproaching = 'Approaching';
  static const String alarmAway        = 'Away';
  static const String alarmSlide       = '>>> Slide Fully to Safe Zone to Stop Audio >>>';

  // System Health
  static const String healthTitle         = 'System Health';
  static const String healthTabDashboard  = 'Dashboard';
  static const String healthTabDiagnostics = 'Diagnostics';
  static const String healthTabOptimizers = 'Optimizers';
  static const String healthTabAlerts     = 'Alerts';
  static const String healthGpsLabel      = 'GPS Geofence Kernel';
  static const String healthWifiLabel     = 'Underground Wi-Fi Scanner';
  static const String healthDeadRecLabel  = 'Inertial Dead Reckoning Core';
  static const String healthStatusOnline  = 'Online / Active';
  static const String healthStatusStandby = 'Standby / Idle';
  static const String healthStatusLinked  = 'Linked / Active';
  static const String healthBatteryTitle  = 'Android Background Battery Constraint';
  static const String healthBatteryGrant  = 'Grant Whitelist Exemption';
  static const String healthDndTitle      = 'Do Not Disturb / Silent Mode Bypass';
  static const String healthDndDesc       = 'Alarms will sound regardless of hardware mute switch';
  static const String healthVersion       = 'v1.0.0-stable | Build 1000';

  // Generic
  static const String back   = 'Back';
  static const String done   = 'Done';
  static const String cancel = 'Cancel';
  static const String error  = 'Something went wrong';
  static const String retry  = 'Retry';
}
