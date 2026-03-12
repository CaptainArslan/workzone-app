/// Central configuration for the Haywork app.
/// Store app name, base URL, and OneSignal app ID here for easy updates.
class AppConfig {
  AppConfig._();

  /// Display name of the application
  static const String appName = 'HayWork';

  /// Base URL loaded in the WebView (production)
   static const String baseUrl = 'https://haywork.am/';

  /// OneSignal App ID for push notifications.
  /// Replace with your actual OneSignal app ID from the OneSignal dashboard.
  static const String oneSignalAppId = '1a952e85-63d8-437b-b526-7d7f35a7ddcf';

  /// Duration to show the splash screen before navigating to WebView (milliseconds)
  static const int splashDurationMs = 2500;
}
