import 'package:flutter/material.dart';
import '../../managers/xingzhe_manager.dart';
import '../../theme/app_theme.dart';
import '../../l10n/strings.dart';
import 'login_template.dart';

class XingzheLoginPage extends StatelessWidget {
  const XingzheLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = XingzheManager();

    return PasswordLoginPage(
      title: '${S.current.xingzhe} ${S.current.login}',
      subtitle: S.current.loginWillAutoSync,
      icon: Icons.map_rounded,
      brandColor: AppTheme.xingzheColor,
      usernameLabel: S.current.usernameOrPhone,
      initialUsername: manager.username,
      onLogin: (username, password) => manager.login(username, password),
    );
  }
}
