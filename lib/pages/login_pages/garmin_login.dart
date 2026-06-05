import 'package:flutter/material.dart';
import '../../managers/garmin_manager.dart';
import '../../l10n/strings.dart';
import 'login_template.dart';

class GarminLoginPage extends StatelessWidget {
  const GarminLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = GarminManager();

    return PasswordLoginPage(
      title: S.current.garmin,
      subtitle: S.current.loginWillAutoSync,
      icon: Icons.watch_rounded,
      brandColor: const Color(0xFF11AEED),
      usernameLabel: S.current.usernameOrPhone,
      usernameHint: '',
      usernameKeyboardType: TextInputType.emailAddress,
      initialUsername: null,
      onLogin: (username, password) => manager.login(username, password),
    );
  }
}
