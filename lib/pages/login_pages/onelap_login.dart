import 'package:flutter/material.dart';
import '../../managers/onelap_manager.dart';
import '../../services/onelap_service.dart';
import '../../theme/app_theme.dart';
import '../../l10n/strings.dart';
import 'login_template.dart';
import 'onelap_webview_login.dart';

class OneLapLoginPage extends StatelessWidget {
  const OneLapLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = OneLapManager();

    return PasswordLoginPage(
      title: '${S.current.onelap} ${S.current.login}',
      subtitle: S.current.loginWillAutoSync,
      icon: Icons.cloud_download_rounded,
      brandColor: AppTheme.onelapColor,
      usernameLabel: S.current.usernameOrPhone,
      initialUsername: manager.username,
      onLogin: (username, password) => manager.login(username, password),
      onTestConnection: () => _testConnection(context),
      additionalActions: _buildWebLoginButton(context, manager),
    );
  }

  Widget _buildWebLoginButton(BuildContext context, OneLapManager manager) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => OneLapWebViewLoginPage(
                onLoginSuccess: ({
                  required String token,
                  String? refreshToken,
                  String? uid,
                  String? nickname,
                }) =>
                    manager.loginViaWebView(
                  token: token,
                  refreshToken: refreshToken,
                  uid: uid,
                  nickname: nickname,
                ),
              ),
            ),
          );
          if (result == true && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.current.loginSuccess)),
            );
            Navigator.pop(context, true);
          }
        },
        icon: const Icon(Icons.language, size: 18),
        label: const Text('验证码登录'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.onelapColor,
          side: BorderSide(color: AppTheme.onelapColor.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Future<void> _testConnection(BuildContext context) async {
    final service = OneLapService();
    final result = await service.testConnection();

    if (!context.mounted) return;

    if (result['success'] == true) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Text(S.current.loginSuccess),
            ],
          ),
          content: Text('状态码: ${result['statusCode']}\n可以正常访问顽鹿服务器'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.current.ok),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('连接失败'),
            ],
          ),
          content: Text('${result['message']}\n\n可能原因:\n1. 网络未连接\n2. 防火墙阻止访问\n3. 服务器维护中'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }
}
