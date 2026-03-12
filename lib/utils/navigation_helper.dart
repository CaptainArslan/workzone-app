import 'package:flutter/material.dart';

/// Helper for consistent navigation and back-button handling.
/// Use for replacing the current route (e.g. splash -> webview) without stack buildup.
class NavigationHelper {
  NavigationHelper._();

  /// Pushes [route] and removes all previous routes so user cannot go back to splash.
  static void replaceWith(BuildContext context, Widget route) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => route),
    );
  }

  /// Pushes [route] on top of the current one (back goes to previous screen).
  static void push(BuildContext context, Widget route) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => route),
    );
  }

  /// Pops the current route if [Navigator] can pop.
  static void maybePop(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}
