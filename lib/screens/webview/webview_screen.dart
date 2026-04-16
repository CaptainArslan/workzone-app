import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../../config/app_config.dart';
import '../../services/webview_service.dart';
import '../../widgets/error_widget.dart' as app_widgets;
import '../../widgets/loading_widget.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _controller;

  bool _isLoading = true;
  bool _hasError = false;
  bool _hasInternet = true;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySub;
  bool _permissionRequested = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final connected = results.any((r) => r != ConnectivityResult.none);
      setState(() => _hasInternet = connected);
      if (connected) _controller?.reload();
    });

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );

    WebViewService.tryPendingPushRegistration();
  }

  @override
  void dispose() {
    _connectivitySub.cancel(); // ← ADD
    super.dispose();
  }

  void _onPageStarted(String url) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _hasError = false;
    });
  }

  void _onPageFinished(String url) {
    if (!mounted) return;
    setState(() => _isLoading = false);

    WebViewService.tryPendingPushRegistration();

    if (!_permissionRequested) {
      _permissionRequested = true;
      OneSignal.Notifications.requestPermission(true);
    }
  }

  void _onWebResourceError(String url, int code, String message) {
    if (!mounted) return;
    setState(() {
      _hasError = true;
      _hasInternet = false;
      _errorMessage = message.isNotEmpty ? message : 'Failed to load page.';
    });
  }

  Future<void> _reload() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(AppConfig.baseUrl)),
    );
  }

  Future<bool> _showExitDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text(
              'Exit App',
              style: TextStyle(
                color: Color(0xFF04C18A),
                fontWeight: FontWeight.bold,
              ),
            ),
            content: const Text(
              'Are you sure you want to exit?',
              style: TextStyle(color: Colors.black87),
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey,
                ),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF04C18A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Exit'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_controller != null && await _controller!.canGoBack()) {
          await _controller!.goBack();
          return false;
        }
        return await _showExitDialog();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          toolbarHeight: 0,
          backgroundColor: Colors.white,
          elevation: 0,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
        ),
        body: _hasError
            ? (!_hasInternet
                ? _NoInternetWidget(onRetry: _reload)
                : app_widgets.AppErrorWidget(
                    message: _errorMessage,
                    onRetry: () async {
                      if (!mounted) return;
                      await _reload();
                    },
                  ))
            : Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: _reload,
                    child: ColoredBox(
                      color: Colors.white,
                      child: WebViewService.buildInAppWebView(
                        onPageStarted: _onPageStarted,
                        onPageFinished: _onPageFinished,
                        onError: _onWebResourceError,
                        onControllerReady: (c) {
                          _controller = c;
                        },
                      ),
                    ),
                  ),
                  if (_isLoading) const LoadingWidget(),
                ],
              ),
      ),
    );
  }
}

class _NoInternetWidget extends StatelessWidget {
  final VoidCallback onRetry;
  const _NoInternetWidget({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 72, color: Colors.grey),
            const SizedBox(height: 24),
            const Text(
              'No Internet Connection',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF04C18A),
                foregroundColor: Colors.white,
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
