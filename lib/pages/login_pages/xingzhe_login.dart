import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../managers/xingzhe_manager.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass_card.dart';
import '../../l10n/strings.dart';

class XingzheLoginPage extends StatefulWidget {
  const XingzheLoginPage({super.key});

  @override
  State<XingzheLoginPage> createState() => _XingzheLoginPageState();
}

class _XingzheLoginPageState extends State<XingzheLoginPage> {
  final _manager = XingzheManager();

  // 密码登录
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // 验证码登录
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isSending = false;
  int _countdown = 0;
  Timer? _timer;

  bool _isLoading = false;
  bool _isSmsMode = false;

  @override
  void initState() {
    super.initState();
    if (_manager.username != null) {
      _usernameController.text = _manager.username!;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length != 11 || !RegExp(r'^\d+$').hasMatch(phone)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.current.invalidPhone)),
        );
      }
      return;
    }

    setState(() => _isSending = true);
    try {
      final success = await _manager.sendSmsCode(phone);
      if (!mounted) return;
      if (success) {
        _startCountdown();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.current.codeSent} $phone')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.current.codeSendFailed)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.current.loginError}: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      bool success;
      if (_isSmsMode) {
        final phone = _phoneController.text.trim();
        final code = _codeController.text.trim();
        if (phone.isEmpty || code.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.current.enterPhoneAndCode)),
            );
          }
          return;
        }
        if (code.length < 4) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.current.invalidCode)),
            );
          }
          return;
        }
        success = await _manager.loginBySmsCode(phone, code);
      } else {
        final username = _usernameController.text.trim();
        final password = _passwordController.text;
        if (username.isEmpty || password.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.current.enterUsernameAndPassword)),
            );
          }
          return;
        }
        success = await _manager.login(username, password);
      }

      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.current.xingzhe} ${S.current.loginSuccess}')),
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
        SnackBar(content: Text('${S.current.loginError}: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text('${S.current.xingzhe} ${S.current.login}')),
      body: Container(
        decoration: AppTheme.backgroundGradient,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              _buildBrandIcon()
                  .animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.8, 0.8)),
              const SizedBox(height: 24),
              Text(
                _isSmsMode
                    ? '${S.current.login} ${S.current.xingzhe}\n${S.current.enterPhoneAndCode}'
                    : '${S.current.login} ${S.current.xingzhe}\n${S.current.enterUsernamePassword}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.6)),
              ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
              const SizedBox(height: 32),
              _buildLoginModeSwitch().animate().fadeIn(duration: 400.ms, delay: 250.ms),
              const SizedBox(height: 16),
              _buildLoginForm()
                  .animate().fadeIn(duration: 500.ms, delay: 300.ms).slideY(begin: 0.15, end: 0),
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
        color: AppTheme.xingzheColor.withOpacity(0.12),
        boxShadow: [
          BoxShadow(
            color: AppTheme.xingzheColor.withOpacity(0.2),
            blurRadius: 40,
            spreadRadius: 5,
          ),
        ],
      ),
      child: const Icon(Icons.map_rounded, size: 56, color: AppTheme.xingzheColor),
    );
  }

  Widget _buildLoginModeSwitch() {
    return GlassCard(
      padding: const EdgeInsets.all(4),
      opacity: 0.1,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isSmsMode = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_isSmsMode ? AppTheme.xingzheColor.withOpacity(0.3) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 18, color: !_isSmsMode ? Colors.white : Colors.white54),
                    const SizedBox(width: 8),
                    Text(S.current.passwordLogin, style: TextStyle(
                      color: !_isSmsMode ? Colors.white : Colors.white54,
                      fontWeight: !_isSmsMode ? FontWeight.bold : FontWeight.normal,
                    )),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isSmsMode = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _isSmsMode ? AppTheme.xingzheColor.withOpacity(0.3) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sms_outlined, size: 18, color: _isSmsMode ? Colors.white : Colors.white54),
                    const SizedBox(width: 8),
                    Text(S.current.smsLogin, style: TextStyle(
                      color: _isSmsMode ? Colors.white : Colors.white54,
                      fontWeight: _isSmsMode ? FontWeight.bold : FontWeight.normal,
                    )),
                  ],
                ),
              ),
            ),
          ),
        ],
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
          if (!_isSmsMode) ...[
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: S.current.usernameOrPhone,
                prefixIcon: const Icon(Icons.person_outline),
                hintText: S.current.usernameOrPhone,
              ),
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: S.current.password,
                prefixIcon: const Icon(Icons.lock_outline),
                hintText: S.current.password,
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _login(),
            ),
          ] else ...[
            TextField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: S.current.phoneNumber,
                prefixIcon: const Icon(Icons.phone_android_rounded),
                hintText: S.current.phoneNumber,
              ),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              style: const TextStyle(color: Colors.white),
              maxLength: 11,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      labelText: S.current.verifyCode,
                      prefixIcon: const Icon(Icons.pin_outlined),
                      hintText: S.current.verifyCode,
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _login(),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  width: 110,
                  child: ElevatedButton(
                    onPressed: (_countdown > 0 || _isSending) ? null : _sendCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.xingzheColor,
                      disabledBackgroundColor: Colors.white12,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: EdgeInsets.zero,
                    ),
                    child: _isSending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_countdown > 0 ? '${_countdown}s' : S.current.sendCode, style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: GradientButton(
              onPressed: _isLoading ? null : _login,
              colors: [AppTheme.xingzheColor, AppTheme.xingzheColor.withOpacity(0.7)],
              child: _isLoading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
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
        ],
      ),
    );
  }
}
