import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../utils/navigation_helper.dart';
import '../webview/webview_screen.dart';

/// Splash screen shown at app launch. Displays app name and navigates to WebView after a delay.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateAfterDelay();
  }

  /// Waits for [AppConfig.splashDurationMs] then replaces this screen with WebView.
  Future<void> _navigateAfterDelay() async {
    await Future<void>.delayed(const Duration(milliseconds: AppConfig.splashDurationMs));
    if (!mounted) return;
    NavigationHelper.replaceWith(context, const WebViewScreen());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppConfig.appName,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Image.asset('assets/appLogo.png', width: 100, height: 100,),
          ],
        ),
      ),
    );
  }
}
