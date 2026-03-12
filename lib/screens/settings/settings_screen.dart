import 'package:flutter/material.dart';

import '../../config/app_config.dart';

/// Basic settings screen. Can be extended with app preferences, about, etc.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text(AppConfig.appName),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
