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
    print('[PUSH] OneSignal: initializing...');
    
    OneSignal.Debug.setLogLevel(OSLogLevel.none);
    OneSignal.initialize(AppConfig.oneSignalAppId);

    OneSignal.User.pushSubscription.addObserver((state) {
      final id = state.current.id;
      final token = state.current.token;

      print('[PUSH] observer -> id=${id ?? "null"}');

      if (id != null && id.isNotEmpty) {
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
    print('[PUSH] OneSignal: initialized (no permission requested)');
  } catch (e) {
    print('[PUSH] init error: $e');
    _initialized = true;
  }
}

}