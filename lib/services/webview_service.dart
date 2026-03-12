import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../config/app_config.dart';
import '../services/push_token_storage.dart';

/// Callback types for WebView lifecycle events.
typedef OnPageStarted = void Function(String url);
typedef OnPageFinished = void Function(String url);
typedef OnWebResourceError = void Function(WebResourceError error);

/// Centralizes WebView controller creation, JS injection, push bridge,
/// and push token registration. The screen only handles UI state.
class WebViewService {
  WebViewService._();

  /// Creates a fully configured [WebViewController].
  ///
  /// [onPageStarted]  — called when a new page begins loading.
  /// [onPageFinished] — called when the page DOM is ready (safe to inject JS).
  /// [onError]        — called only for main-frame load failures.
  static WebViewController createController({
    required OnPageStarted onPageStarted,
    required OnPageFinished onPageFinished,
    required OnWebResourceError onError,
  }) {
    final controller = WebViewController();
    _activeController = controller;

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _handleBridgeMessage(message.message);
        },
      )
      // ..setNavigationDelegate(
      //   NavigationDelegate(
      //     onPageStarted: onPageStarted,
      //     onPageFinished: (url) async {
      //       onPageFinished(url);
      //       await _injectViewportMeta(controller);
      //     },
      //     onWebResourceError: (error) {
      //       // Ignore sub-resource failures (images, fonts, scripts).
      //       // Only surface main-frame errors to the screen.
      //       if (error.isForMainFrame == false) return;
      //       onError(error);
      //     },
      //   ),
      // );
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) async {
            // ✅ Detect logout on ANY navigation type (POST, redirect, link)
            if (isLogoutUrl(url)) {
              await clearSession(controller);
            }
            onPageStarted(url);
          },
          onPageFinished: (url) async {
            onPageFinished(url);
            await _injectViewportMeta(controller);
            await _injectLogoutDetector(controller);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) return;
            onError(error);
          },
        ),
      );

    return controller;
  }

  // ---------------------------------------------------------------------------
  // JS injection
  // ---------------------------------------------------------------------------

  /// Disables user zoom and enforces a mobile viewport meta tag.
  /// Must be called from [onPageFinished] — the DOM is ready at that point.
  static Future<void> _injectViewportMeta(WebViewController controller) async {
    await controller.runJavaScript("""
      (function() {
        try {
          var meta = document.querySelector('meta[name="viewport"]');
          if (meta) {
            meta.setAttribute('content',
              'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no');
          } else {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content =
              'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            if (document.head) document.head.appendChild(meta);
          }
          document.addEventListener('gesturestart', function(e) {
            e.preventDefault();
          });
        } catch(e) {
          console.log('Viewport injection error: ' + e);
        }
      })();
    """);
  }

  // ---------------------------------------------------------------------------
  // FlutterBridge message handling
  // ---------------------------------------------------------------------------

  /// Handles JSON or plain-string messages posted by the Laravel blade script.
  // static void _handleBridgeMessage(String message) {
  //   print('[PUSH] Bridge: received (length=${message.length})');
  //   try {
  //     final data = jsonDecode(message);
  //     if (data is Map && data['type'] == 'push_auth_payload') {
  //       final encryptedUserId = data['pushAuthPayload'] as String?;
  //       if (encryptedUserId != null && encryptedUserId.isNotEmpty) {
  //         print('[PUSH] Bridge: push_auth_payload received');
  //         onPushAuthPayload(encryptedUserId);
  //       } else {
  //         print('[PUSH] Bridge: push_auth_payload is empty, ignoring');
  //       }
  //     } else {
  //       print(
  //           '[PUSH] Bridge: unknown type=${data is Map ? data['type'] : '?'}');
  //     }
  //   } catch (_) {
  //     if (message == 'login_success') {
  //       print('[PUSH] Bridge: login_success (plain string)');
  //     } else {
  //       print('[PUSH] Bridge: parse failed or unrecognised message');
  //     }
  //   }
  // }
  static WebViewController? _activeController;

  static void _handleBridgeMessage(String message) {
    print('[PUSH] Bridge: received (length=${message.length})');
    try {
      final data = jsonDecode(message);
      if (data is Map && data['type'] == 'push_auth_payload') {
        final encryptedUserId = data['pushAuthPayload'] as String?;
        if (encryptedUserId != null && encryptedUserId.isNotEmpty) {
          print('[PUSH] Bridge: push_auth_payload received');
          onPushAuthPayload(encryptedUserId);
        } else {
          print('[PUSH] Bridge: push_auth_payload is empty, ignoring');
        }
      } else if (data is Map && data['type'] == 'logout') {
        print('[AUTH] Bridge: logout received → clearing session');
        if (_activeController != null) {
          clearSession(_activeController!).then((_) {
            // ✅ properly chained
            print('[AUTH] clearSession completed');
          });
        }
      } else {
        print(
            '[PUSH] Bridge: unknown type=${data is Map ? data['type'] : '?'}');
      }
    } catch (_) {
      if (message == 'login_success') {
        print('[PUSH] Bridge: login_success (plain string)');
      } else {
        print('[PUSH] Bridge: parse failed or unrecognised message');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Push token registration
  // ---------------------------------------------------------------------------

  /// Called when the web page sends the encrypted user ID after login.
  /// Attempts immediate registration; falls back to saving a pending payload
  /// if the OneSignal subscription ID is not yet available.
  static Future<void> onPushAuthPayload(String encryptedUserId) async {
    print('[PUSH] onPushAuthPayload: start');

    String? subscriptionId = await PushTokenStorage.getPushSubscriptionId() ??
        OneSignal.User.pushSubscription.id;

    if (subscriptionId == null) {
      print('[PUSH] onPushAuthPayload: no subscription ID, waiting 2s…');
      await Future.delayed(const Duration(seconds: 2));
      subscriptionId = OneSignal.User.pushSubscription.id ??
          await PushTokenStorage.getPushSubscriptionId();
    }

    if (subscriptionId != null && subscriptionId.isNotEmpty) {
      print('[PUSH] onPushAuthPayload: registering token now');
      final ok = await registerPushToken(encryptedUserId, subscriptionId);
      if (ok) await PushTokenStorage.clearPendingPushAuthPayload();
    } else {
      print('[PUSH] onPushAuthPayload: saving as pending for later');
      await PushTokenStorage.setPendingPushAuthPayload(encryptedUserId);
    }
  }

  /// Retries push registration if a pending payload exists and the subscription
  /// ID is now available. Call this from [onPageFinished] and on app start.
  static Future<void> tryPendingPushRegistration() async {
    print('[PUSH] tryPending: checking…');
    final pending = await PushTokenStorage.getPendingPushAuthPayload();
    if (pending == null) {
      print('[PUSH] tryPending: nothing pending');
      return;
    }

    final subscriptionId = await PushTokenStorage.getPushSubscriptionId() ??
        OneSignal.User.pushSubscription.id;

    if (subscriptionId == null) {
      print('[PUSH] tryPending: subscription ID still unavailable');
      return;
    }

    print('[PUSH] tryPending: registering pending token');
    final ok = await registerPushToken(pending, subscriptionId);
    if (ok) {
      await PushTokenStorage.clearPendingPushAuthPayload();
      print('[PUSH] tryPending: success, cleared pending');
    }
  }

  /// POSTs the OneSignal subscription ID and encrypted user ID to the backend.
  /// Returns `true` on HTTP 200/201.
  static Future<bool> registerPushToken(
    String encryptedUserId,
    String subscriptionId,
  ) async {
    final uri = Uri.parse('${AppConfig.baseUrl}save-push-subscription');
    final body = {
      'player_id': subscriptionId,
      'push_auth_payload': encryptedUserId,
      'device_type': Platform.isIOS ? 'ios' : 'android',
    };

    print('[PUSH] API: POST $uri');
    print(
      '[PUSH] API: player_id=${subscriptionId.substring(0, subscriptionId.length.clamp(0, 24))}… '
      'payload=${encryptedUserId.length} chars '
      'device=${body['device_type']}',
    );

    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      print('[PUSH] API: status=${response.statusCode}');
      if (response.body.isNotEmpty) {
        print(
          '[PUSH] API: body=${response.body.length > 200 ? '${response.body.substring(0, 200)}…' : response.body}',
        );
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('[PUSH] API: token saved successfully');
        return true;
      }
      print('[PUSH] API: failed ${response.statusCode}');
      return false;
    } catch (e, stack) {
      print('[PUSH] API: exception $e');
      print('[PUSH] API: $stack');
      return false;
    }
  }

  static bool isLogoutUrl(String url) {
    return url.contains('/seller/logout') || url.contains('/buyer/logout');
  }

  static Future<void> clearSession(WebViewController controller) async {
    print('[AUTH] Clearing cookies, cache, localStorage…');
    await WebViewCookieManager().clearCookies();
    await controller.clearCache();
    await controller.clearLocalStorage();
    print('[AUTH] Session cleared → reloading to home');
    await controller
        .loadRequest(Uri.parse(AppConfig.baseUrl)); // ✅ redirect to homepage
  }

  static Future<void> _injectLogoutDetector(
      WebViewController controller) async {
    await controller.runJavaScript("""
    (function() {
      // Watch for logout links/buttons being clicked
      document.addEventListener('click', function(e) {
        var el = e.target.closest('a, button, form');
        if (!el) return;
        
        // Check anchor tags
        if (el.tagName === 'A') {
          var href = el.getAttribute('href') || '';
          if (href.includes('/logout')) {
            FlutterBridge.postMessage(JSON.stringify({type: 'logout'}));
          }
        }
        
        // Check forms
        if (el.tagName === 'FORM') {
          var action = el.getAttribute('action') || '';
          if (action.includes('/logout')) {
            FlutterBridge.postMessage(JSON.stringify({type: 'logout'}));
          }
        }
      }, true);
      
      // Also intercept form submits directly
      document.addEventListener('submit', function(e) {
        var action = e.target.getAttribute('action') || '';
        if (action.includes('/logout')) {
          FlutterBridge.postMessage(JSON.stringify({type: 'logout'}));
        }
      }, true);
    })();
  """);
  }
}
