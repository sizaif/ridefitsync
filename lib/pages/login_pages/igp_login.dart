import 'package:flutter/material.dart';
import '../../managers/igp_manager.dart';
import '../../theme/app_theme.dart';
import '../../l10n/strings.dart';
import 'login_template.dart';

class IGPLoginPage extends StatelessWidget {
  const IGPLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = IGPManager();

    return PasswordLoginPage(
      title: '${S.current.igpsport} ${S.current.login}',
      subtitle: S.current.loginWillAutoSync,
      icon: Icons.pedal_bike,
      brandColor: AppTheme.igpColor,
      usernameLabel: S.current.usernameOrPhone,
      usernameKeyboardType: TextInputType.emailAddress,
      initialUsername: manager.username,
      onLogin: (username, password) => manager.login(username, password),
    );
  }
}
