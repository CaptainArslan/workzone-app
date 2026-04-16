import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../config/app_config.dart';
import '../services/push_token_storage.dart';

typedef OnPageStarted = void Function(String url);
typedef OnPageFinished = void Function(String url);
typedef OnWebResourceError = void Function(
    String url, int code, String message);

class WebViewService {
  WebViewService._();

  static InAppWebViewController? _activeController;

  static const String _mobileChromeUserAgent =
      'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// Builds a fully configured [InAppWebView] (same behavior as the previous
  /// [WebViewController] setup: bridge, injections, logout, push).
  static Widget buildInAppWebView({
    required OnPageStarted onPageStarted,
    required OnPageFinished onPageFinished,
    required OnWebResourceError onError,
    void Function(InAppWebViewController controller)? onControllerReady,
  }) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(AppConfig.baseUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: _mobileChromeUserAgent,
        supportZoom: false,
        builtInZoomControls: false,
        displayZoomControls: false,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        useOnDownloadStart: true,
        transparentBackground: false,
        underPageBackgroundColor: Colors.white,
      ),
      onWebViewCreated: (controller) {
        _activeController = controller;
        controller.addJavaScriptHandler(
          handlerName: 'FlutterBridge',
          callback: (args) {
            for (final arg in args) {
              handleBridgeMessage(arg);
            }
          },
        );
        onControllerReady?.call(controller);
      },
      onLoadStart: (controller, url) {
        final u = url.toString();
        if (isLogoutUrl(u)) {
          clearSession();
        }
        onPageStarted(u);
      },
      onLoadStop: (controller, url) async {
        final u = url.toString();
        onPageFinished(u);
        await _injectFlutterBridgeShim(controller);
        await _injectViewportMeta(controller);
        await _injectLogoutDetector(controller);
        await tryPendingPushRegistration();
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame == false) return;
        final u = request.url.toString();
        onError(u, -1, error.description);
      },
      onPermissionRequest: (controller, request) async {
        return PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.GRANT,
        );
      },
    );
  }

  static Future<void> _injectFlutterBridgeShim(
      InAppWebViewController controller) async {
    await controller.evaluateJavascript(source: """
      (function() {
        try {
          if (!window.flutter_inappwebview) return;
          window.FlutterBridge = window.FlutterBridge || {};
          window.FlutterBridge.postMessage = function(message) {
            window.flutter_inappwebview.callHandler('FlutterBridge', message);
          };
        } catch (e) {
          console.log('FlutterBridge shim error: ' + e);
        }
      })();
    """);
  }

  static Future<void> _injectViewportMeta(
      InAppWebViewController controller) async {
    await controller.evaluateJavascript(source: """
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

  // static void handleBridgeMessage(dynamic message) {
  //   final msg = message.toString();
  //   try {
  //     final data = jsonDecode(msg);
  //     if (data is Map && data['type'] == 'push_auth_payload') {
  //       final encryptedUserId = data['pushAuthPayload'] as String?;
  //       if (encryptedUserId != null && encryptedUserId.isNotEmpty) {
  //         print('[PUSH] push_auth_payload received');
  //         onPushAuthPayload(encryptedUserId);
  //       }
  //     } else if (data is Map && data['type'] == 'logout') {
  //       print('[AUTH] logout received → clearing session');
  //       clearSession();
  //     }
  //   } catch (_) {
  //     if (msg == 'login_success') {
  //       print('[PUSH] login_success (plain string)');
  //     } else {
  //       print('[PUSH] unrecognized message');
  //     }
  //   }
  // }

  static void handleBridgeMessage(dynamic message) {
    final msg = message.toString();

    try {
      final data = jsonDecode(msg);

      if (data is Map && data['type'] == 'push_auth_payload') {
        final encryptedUserId = data['pushAuthPayload'] as String?;
        if (encryptedUserId != null && encryptedUserId.isNotEmpty) {
          print('[PUSH] push_auth_payload received');
          onPushAuthPayload(encryptedUserId);
        }
      }

      // ✅ NEW: Ask permission ONLY when website tells
      else if (data is Map && data['type'] == 'request_push_permission') {
        print('[PUSH] Requesting notification permission...');
        _requestPushPermission();
      } else if (data is Map && data['type'] == 'logout') {
        print('[AUTH] logout received → clearing session');
        clearSession();
      }
    } catch (_) {
      if (msg == 'login_success') {
        print('[PUSH] login_success (plain string)');
      } else {
        print('[PUSH] unrecognized message');
      }
    }
  }

  static Future<void> _requestPushPermission() async {
    final granted = await OneSignal.Notifications.requestPermission(true);

    print('[PUSH] Permission granted: $granted');

    if (granted) {
      await OneSignal.User.pushSubscription.optIn();
    }
  }

  static Future<void> onPushAuthPayload(String encryptedUserId) async {
    String? subscriptionId = await PushTokenStorage.getPushSubscriptionId() ??
        OneSignal.User.pushSubscription.id;

    if (subscriptionId == null) {
      await Future.delayed(const Duration(seconds: 2));
      subscriptionId = OneSignal.User.pushSubscription.id ??
          await PushTokenStorage.getPushSubscriptionId();
    }

    if (subscriptionId != null && subscriptionId.isNotEmpty) {
      final ok = await registerPushToken(encryptedUserId, subscriptionId);
      if (ok) await PushTokenStorage.clearPendingPushAuthPayload();
    } else {
      await PushTokenStorage.setPendingPushAuthPayload(encryptedUserId);
    }
  }

  static Future<void> tryPendingPushRegistration() async {
    final pending = await PushTokenStorage.getPendingPushAuthPayload();
    if (pending == null) return;

    final subscriptionId = await PushTokenStorage.getPushSubscriptionId() ??
        OneSignal.User.pushSubscription.id;

    if (subscriptionId == null) return;

    final ok = await registerPushToken(pending, subscriptionId);
    if (ok) await PushTokenStorage.clearPendingPushAuthPayload();
  }

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
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  static bool isLogoutUrl(String url) =>
      url.contains('/seller/logout') || url.contains('/buyer/logout');

  static Future<void> clearSession() async {
    if (_activeController == null) return;
    final c = _activeController!;
    await CookieManager.instance().deleteAllCookies();
    await InAppWebViewController.clearAllCache();
    await c.evaluateJavascript(source: """
      try {
        localStorage.clear();
        sessionStorage.clear();
      } catch (e) {}
    """);
    await c.loadUrl(
      urlRequest: URLRequest(url: WebUri(AppConfig.baseUrl)),
    );
  }

  static Future<void> _injectLogoutDetector(
      InAppWebViewController controller) async {
    await controller.evaluateJavascript(source: """
    (function() {
      document.addEventListener('click', function(e) {
        var el = e.target.closest('a, button, form');
        if (!el) return;
        if (el.tagName === 'A') {
          var href = el.getAttribute('href') || '';
          if (href.includes('/logout')) {
            FlutterBridge.postMessage(JSON.stringify({type: 'logout'}));
          }
        }
        if (el.tagName === 'FORM') {
          var action = el.getAttribute('action') || '';
          if (action.includes('/logout')) {
            FlutterBridge.postMessage(JSON.stringify({type: 'logout'}));
          }
        }
      }, true);
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
