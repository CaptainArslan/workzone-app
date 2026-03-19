import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../config/app_config.dart';
import 'push_token_storage.dart';

/// Service to initialize and configure OneSignal push notifications.
/// Call [initialize] from main() before runApp().
class OneSignalService {
  OneSignalService._();

  static bool _initialized = false;

static Future<void> initialize() async {
  if (_initialized) {
    print('[PUSH] OneSignal: already initialized, skip');
    return;
  }
  
  if (AppConfig.oneSignalAppId.isEmpty) {
    print('[PUSH] OneSignal: app ID empty, skip');
    return;
  }

  try {
    print('[PUSH] OneSignal: initializing with appId=${AppConfig.oneSignalAppId.substring(0, 8)}...');
    OneSignal.Debug.setLogLevel(OSLogLevel.none);
    OneSignal.initialize(AppConfig.oneSignalAppId);
    print('[PUSH] OneSignal: requesting notification permission...');
    await OneSignal.Notifications.requestPermission(true);
    print('[PUSH] OneSignal: permission requested');

    print('[PUSH] OneSignal: optIn push subscription...');
    await OneSignal.User.pushSubscription.optIn();

    // Wait for subscription to be ready, then persist in local storage
    OneSignal.User.pushSubscription.addObserver((state) {
      final id = state.current.id;
      final token = state.current.token;
      print('[PUSH] OneSignal: observer fired -> id=${id ?? "null"} token=${token != null ? "***" : "null"}');
      if (id != null && id.isNotEmpty) {
        print('[PUSH] OneSignal: subscription ready, saving to local storage');
        PushTokenStorage.savePushSubscription(
          subscriptionId: id,
          token: token,
        );
      }
    });

    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      event.notification.display();
    });

    _initialized = true;
    print('[PUSH] OneSignal: initialization done');
  } catch (e, stack) {
    // e.g. "GSM SERVICE NOT AVAILABLE" on some devices; app still runs, push may work when network is ready
    print('[PUSH] OneSignal: init error (app will continue, push may work later): $e');
    print('[PUSH] OneSignal: $stack');
    _initialized = true;
  }
}


}