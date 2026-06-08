import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass_card.dart';
import '../../l10n/strings.dart';

/// 密码登录页面的统一模板
class PasswordLoginPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color brandColor;
  final String usernameLabel;
  final String usernameHint;
  final TextInputType usernameKeyboardType;
  final String? initialUsername;
  final Future<bool> Function(String username, String password) onLogin;
  final Future<void> Function()? onTestConnection;
  final Widget? additionalActions;  // 额外操作按钮（如"网页登录"）

  const PasswordLoginPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.brandColor,
    this.usernameLabel = '用户名/手机号', // 由各平台页面覆盖
    this.usernameHint = '',
    this.usernameKeyboardType = TextInputType.text,
    this.initialUsername,
    required this.onLogin,
    this.onTestConnection,
    this.additionalActions,
  });

  @override
  State<PasswordLoginPage> createState() => _PasswordLoginPageState();
}

class _PasswordLoginPageState extends State<PasswordLoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialUsername != null) {
      _usernameController.text = widget.initialUsername!;
    }
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.current.enterUsernameAndPassword)),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final success = await widget.onLogin(
        _usernameController.text,
        _passwordController.text,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.current.loginSuccess)),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.current.loginFailed)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.current.loginError} $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Container(
        decoration: AppTheme.backgroundGradient,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // 品牌图标 + 光晕
              _buildBrandIcon()
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .scale(begin: const Offset(0.8, 0.8)),
              const SizedBox(height: 24),
              // 说明文字
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.6),
                ),
              )
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 200.ms),
              const SizedBox(height: 32),
              // 登录表单卡片
              _buildLoginForm()
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 300.ms)
                  .slideY(begin: 0.15, end: 0),
              // 额外操作（如网页登录入口）
              if (widget.additionalActions != null) ...[
                const SizedBox(height: 16),
                widget.additionalActions!,
              ],
              const SizedBox(height: 24),
              // 提示文字
              Text(
                S.current.loginWillAutoSync,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.35),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 600.ms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrandIcon() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.brandColor.withOpacity(0.12),
        boxShadow: [
          BoxShadow(
            color: widget.brandColor.withOpacity(0.2),
            blurRadius: 40,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Icon(
        widget.icon,
        size: 56,
        color: widget.brandColor,
      ),
    );
  }

  Widget _buildLoginForm() {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      opacity: 0.1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 用户名输入框
          TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: widget.usernameLabel,
              prefixIcon: const Icon(Icons.person_outline_rounded),
            ),
            keyboardType: widget.usernameKeyboardType,
            textInputAction: TextInputAction.next,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          // 密码输入框
          TextField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: S.current.password,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.white38,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
            ),
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 28),
          // 登录按钮
          SizedBox(
            height: 52,
            child: GradientButton(
              onPressed: _isLoading ? null : _login,
              colors: [
                widget.brandColor,
                widget.brandColor.withOpacity(0.7),
              ],
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.login_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(S.current.login),
                      ],
                    ),
            ),
          ),
          // 测试连接按钮（如果提供了回调）
          if (widget.onTestConnection != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _isLoading ? null : widget.onTestConnection,
              icon: const Icon(Icons.wifi_find_rounded, size: 18),
              label: const Text('测试网络连接'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white54,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
