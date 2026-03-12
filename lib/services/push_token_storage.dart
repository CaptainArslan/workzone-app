import 'package:shared_preferences/shared_preferences.dart';

/// Keys for local storage (push notification token and pending login payload).
const String _keyPushSubscriptionId = 'push_subscription_id';
const String _keyPushToken = 'push_token';
const String _keyPendingPushAuthPayload = 'pending_push_auth_payload';

/// Persists the OneSignal player/subscription ID and optional token in local storage
/// so we can register with the backend when the user logs in (even if login happens
/// before the subscription is ready, we retry with [pendingPushAuthPayload]).
class PushTokenStorage {
  PushTokenStorage._();

  static SharedPreferences? _prefs;
  static Future<SharedPreferences> get _instance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Saves the OneSignal subscription (player) ID and optional FCM/APNS token
  /// after the user grants push permission and OneSignal registers.
  static Future<void> savePushSubscription({
    required String subscriptionId,
    String? token,
  }) async {
    final prefs = await _instance;
    await prefs.setString(_keyPushSubscriptionId, subscriptionId);
    if (token != null && token.isNotEmpty) {
      await prefs.setString(_keyPushToken, token);
    }
    print('[PUSH] Storage: saved subscription_id=${subscriptionId.substring(0, subscriptionId.length.clamp(0, 20))}... token=${token != null ? "yes" : "no"}');
  }

  /// Returns the stored subscription (player) ID, or null if not yet saved.
  static Future<String?> getPushSubscriptionId() async {
    final prefs = await _instance;
    final id = prefs.getString(_keyPushSubscriptionId);
    print('[PUSH] Storage: getPushSubscriptionId -> ${id != null ? "${id.substring(0, id.length.clamp(0, 20))}..." : "null"}');
    return id;
  }

  /// Returns the stored push token (FCM/APNS), or null.
  static Future<String?> getPushToken() async {
    final prefs = await _instance;
    return prefs.getString(_keyPushToken);
  }

  /// Saves the encrypted user ID from the web script when the user logs in
  /// but the push subscription was not ready yet. Cleared after successful
  /// registration with the backend.
  static Future<void> setPendingPushAuthPayload(String? encryptedUserId) async {
    final prefs = await _instance;
    if (encryptedUserId == null || encryptedUserId.isEmpty) {
      await prefs.remove(_keyPendingPushAuthPayload);
      print('[PUSH] Storage: pending_push_auth_payload cleared');
    } else {
      await prefs.setString(_keyPendingPushAuthPayload, encryptedUserId);
      print('[PUSH] Storage: pending_push_auth_payload saved (length=${encryptedUserId.length})');
    }
  }

  /// Returns the pending encrypted user ID if any (user logged in before token was ready).
  static Future<String?> getPendingPushAuthPayload() async {
    final prefs = await _instance;
    final pending = prefs.getString(_keyPendingPushAuthPayload);
    print('[PUSH] Storage: getPendingPushAuthPayload -> ${pending != null ? "yes (length=${pending.length})" : "null"}');
    return pending;
  }

  /// Clears the pending payload after successful token registration.
  static Future<void> clearPendingPushAuthPayload() async {
    await setPendingPushAuthPayload(null);
  }

  /// Clears all push-related data (e.g. on logout if you add it).
  static Future<void> clearAll() async {
    final prefs = await _instance;
    await prefs.remove(_keyPushSubscriptionId);
    await prefs.remove(_keyPushToken);
    await prefs.remove(_keyPendingPushAuthPayload);
    print('[PUSH] Storage: clearAll');
  }
}