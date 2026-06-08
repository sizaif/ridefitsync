import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../managers/edge_ride_manager.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass_card.dart';
import '../../l10n/strings.dart';

class EdgeRideLoginPage extends StatefulWidget {
  const EdgeRideLoginPage({super.key});

  @override
  State<EdgeRideLoginPage> createState() => _EdgeRideLoginPageState();
}

class _EdgeRideLoginPageState extends State<EdgeRideLoginPage> {
  final _manager = EdgeRideManager();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isSending = false;
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
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
    if (phone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.current.invalidPhone)));
      return;
    }
    if (phone.length != 11 || !RegExp(r'^\d+$').hasMatch(phone)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.current.invalidPhone)));
      return;
    }

    setState(() => _isSending = true);

    try {
      final success = await _manager.sendSmsCode(phone);
      if (!mounted) return;

      if (success) {
        _startCountdown();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${S.current.codeSent} $phone')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(S.current.codeSendFailed)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${S.current.loginError}: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _login() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();

    if (phone.isEmpty || code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.current.enterPhoneAndCode)));
      return;
    }
    if (code.length < 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.current.invalidCode)));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final success = await _manager.login(phone, code);

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('EdgeRide ${S.current.loginSuccess}')),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(S.current.loginFailed)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${S.current.loginError}: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(title: Text('EdgeRide ${S.current.login}')),
      body: Container(
        decoration: AppTheme.loginBackgroundFor(context),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              _buildBrandIcon()
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .scale(begin: const Offset(0.8, 0.8)),
              const SizedBox(height: 24),
              Text(
                '${S.current.login} EdgeRide\n${S.current.enterPhoneAndCode}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: colorScheme.onSurfaceVariant,
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
              const SizedBox(height: 32),
              _buildLoginForm()
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 300.ms)
                  .slideY(begin: 0.15, end: 0),
              const SizedBox(height: 24),
              Text(
                S.current.uploadEdgeRideHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
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
        color: const Color(0xFF00C853).withOpacity(0.12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00C853).withOpacity(0.2),
            blurRadius: 40,
            spreadRadius: 5,
          ),
        ],
      ),
      child: const Icon(
        Icons.electric_bike_rounded,
        size: 56,
        color: Color(0xFF00C853),
      ),
    );
  }

  Widget _buildLoginForm() {
    final colorScheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(24),
      opacity: 0.1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 手机号输入框
          TextField(
            controller: _phoneController,
            decoration: InputDecoration(
              labelText: S.current.phoneNumber,
              prefixIcon: const Icon(Icons.phone_android_rounded),
              hintText: S.current.phoneNumber,
            ),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            style: TextStyle(color: colorScheme.onSurface),
            maxLength: 11,
          ),
          const SizedBox(height: 12),
          // 验证码输入框 + 发送按钮
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
                  style: TextStyle(color: colorScheme.onSurface),
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
                    backgroundColor: const Color(0xFF00C853),
                    disabledBackgroundColor: colorScheme.onSurface.withOpacity(
                      0.12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _countdown > 0
                              ? '${_countdown}s'
                              : S.current.sendCode,
                          style: const TextStyle(fontSize: 13),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 登录按钮
          SizedBox(
            height: 52,
            child: GradientButton(
              onPressed: _isLoading ? null : _login,
              colors: const [Color(0xFF00C853), Color(0xFF69F0AE)],
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
        ],
      ),
    );
  }
}
