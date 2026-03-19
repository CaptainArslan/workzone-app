import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
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
  late final WebViewController _controller;

  bool _isLoading = true;
  bool _hasError = false;
  bool _permissionRequested = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );

    _controller = WebViewService.createController(
      onPageStarted: _onPageStarted,
      onPageFinished: _onPageFinished,
      onError: _onWebResourceError,
    )
      ..setBackgroundColor(Colors.white)
      ..loadRequest(Uri.parse(AppConfig.baseUrl));

    WebViewService.tryPendingPushRegistration();
  }

  // ---------------------------------------------------------------------------
  // WebView lifecycle callbacks (wired up via WebViewService)
  // ---------------------------------------------------------------------------

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

    // Retry any pending push registration now that the page is loaded.
    WebViewService.tryPendingPushRegistration();

    // Request push notification permission once after the first page load.
    if (!_permissionRequested) {
      _permissionRequested = true;
      OneSignal.Notifications.requestPermission(true);
    }
  }

  void _onWebResourceError(WebResourceError error) {
    if (!mounted) return;
    setState(() {
      _hasError = true;
      _errorMessage = error.description.isNotEmpty
          ? error.description
          : 'Failed to load page.';
    });
  }

  // ---------------------------------------------------------------------------
  // Navigation helpers
  // ---------------------------------------------------------------------------

  Future<void> _reload() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    await _controller.loadRequest(Uri.parse(AppConfig.baseUrl));
  }

  Future<bool> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

Future<bool> _showExitDialog() async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white, // Dialog background
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            'Exit App',
            style: TextStyle(
              color: Color(0xFF04C18A), // App green color
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
                foregroundColor: Colors.grey, // Cancel button text
              ),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF04C18A), // Green button
                foregroundColor: Colors.white, // White text
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
      false; // return false if dialog dismissed
}

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
    onWillPop: () async {
      // Check if WebView can go back
      if (await _controller.canGoBack()) {
        await _controller.goBack();
        return false; // prevent app from closing
      } else {
        // Show exit confirmation dialog
        return await _showExitDialog();
      }
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
            ? app_widgets.AppErrorWidget(
                message: _errorMessage,
                onRetry: () async {
                  if (!mounted) return;
                  await _reload();
                },
              )
            : Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: _reload,
                    child: WebViewWidget(controller: _controller),
                  ),
                  if (_isLoading)
                    const LoadingWidget(),
                ],
              ),
      ),
    );
  }
}