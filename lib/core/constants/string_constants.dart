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

  // Prominent disclosure — background location.
  //
  // Play policy requires this to appear IN-APP, in the runtime flow, immediately
  // BEFORE the OS background-location prompt, and to require affirmative action.
  // The first sentence of [discloseBgBody] deliberately follows Google's
  // prescribed form ("collects location data to enable … even when the app is
  // closed or not in use") — the most common rejection is a paraphrase, or a
  // permission requested before this dialog is accepted. Do not reword it
  // without re-reading the Location permissions policy.
  static const String discloseBgTitle   = 'Location while the app is closed';
  static const String discloseBgBody    =
      'StopSnoozer collects location data to detect when you reach your '
      'destination stop and wake you with an alarm, even when the app is closed '
      'or not in use.\n\n'
      'On the Underground there is no GPS signal, so the app uses your phone\'s '
      'motion and pressure sensors to track your position offline. Location is '
      'used to confirm that position wherever signal is available.';
  static const String discloseBgFooter  =
      'Location is used only to fire your alarm. It is never sold, and never '
      'leaves your phone except in requests to Transport for London that contain '
      'no personal data.';
  static const String discloseBgAllow   = 'Allow';
  static const String discloseBgDeny    = 'No thanks';
  static const String discloseBgDenied  =
      'Without background location, alarms can only fire while StopSnoozer is '
      'open and on screen. You can change this later in Settings.';

  // Radio-scan consent (PECR reg. 6 — see RadioConsentDialog).
  static const String consentRadioTitle = 'Help StopSnoozer learn your stations';
  static const String consentRadioBody  =
      'StopSnoozer can read the identifiers of nearby Wi-Fi access points and '
      'mobile cells to recognise which underground station you are at.\n\n'
      'This reading happens on your device only. The identifiers are stored in '
      'the app\'s private database, are never transmitted anywhere, and you can '
      'erase them at any time from System Health.';
  static const String consentRadioFooter =
      'This is optional. Arrival detection works without it, using the pressure '
      'and motion sensors and journey timing.';
  static const String consentRadioAllow = 'Allow on-device learning';
  static const String consentRadioDeny  = 'Not now';

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
