import 'package:flutter/material.dart';
import '../../managers/giant_manager.dart';
import '../../theme/app_theme.dart';
import '../../l10n/strings.dart';
import 'login_template.dart';

class GiantLoginPage extends StatelessWidget {
  const GiantLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = GiantManager();

    return PasswordLoginPage(
      title: '${S.current.giant} ${S.current.login}',
      subtitle: '${S.current.loginWillAutoSync}',
      icon: Icons.directions_bike,
      brandColor: AppTheme.giantColor,
      usernameLabel: S.current.usernameOrPhone,
      initialUsername: manager.username,
      onLogin: (username, password) => manager.login(username, password),
    );
  }
}
