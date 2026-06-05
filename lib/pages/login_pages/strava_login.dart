import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../managers/strava_manager.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass_card.dart';

class StravaLoginPage extends StatefulWidget {
  const StravaLoginPage({super.key});

  @override
  State<StravaLoginPage> createState() => _StravaLoginPageState();
}

class _StravaLoginPageState extends State<StravaLoginPage> {
  final _manager = StravaManager();
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    if (_manager.hasCredentials) {
      // 凭证已存在
    }
  }

  Future<void> _saveCredentials() async {
    if (_clientIdController.text.isEmpty ||
        _clientSecretController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入Client ID和Client Secret')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _manager.saveCredentials(
        _clientIdController.text,
        _clientSecretController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('凭证已保存，请点击授权')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _authorize() async {
    if (!_manager.hasCredentials) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先保存Client ID和Client Secret')),
      );
      return;
    }

    try {
      final authUrl = _manager.getAuthorizationUrl();
      if (await canLaunchUrl(authUrl)) {
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开授权页面')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('授权错误: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Strava 登录'),
      ),
      body: Container(
        decoration: AppTheme.backgroundGradient,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Strava 品牌图标
              _buildBrandIcon()
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .scale(begin: const Offset(0.8, 0.8)),
              const SizedBox(height: 24),
              Text(
                '连接Strava账号\n同步运动数据',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.6),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
              const SizedBox(height: 32),
              // 已连接状态 / 配置表单
              if (_manager.isAuthenticated)
                _buildConnectedCard()
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 300.ms)
                    .scale(begin: const Offset(0.95, 0.95))
              else
                _buildConfigCard()
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 300.ms)
                    .slideY(begin: 0.15, end: 0),
              const SizedBox(height: 24),
              // 说明卡片
              _buildInstructionsCard()
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 500.ms),
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
        color: AppTheme.stravaColor.withOpacity(0.12),
        boxShadow: [
          BoxShadow(
            color: AppTheme.stravaColor.withOpacity(0.25),
            blurRadius: 40,
            spreadRadius: 5,
          ),
        ],
      ),
      child: const Icon(
        Icons.directions_run,
        size: 56,
        color: AppTheme.stravaColor,
      ),
    );
  }

  Widget _buildConnectedCard() {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      opacity: 0.1,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppTheme.success,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '已连接: ${_manager.athleteName ?? "Strava用户"}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Strava 账号已授权',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () async {
              await _manager.logout();
              setState(() {});
            },
            child: const Text(
              '断开连接',
              style: TextStyle(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigCard() {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      opacity: 0.1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Strava API 配置',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          // Client ID
          TextField(
            controller: _clientIdController,
            decoration: const InputDecoration(
              labelText: 'Client ID',
              prefixIcon: Icon(Icons.key_rounded),
              hintText: '在Strava开发者页面获取',
            ),
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          // Client Secret
          TextField(
            controller: _clientSecretController,
            decoration: const InputDecoration(
              labelText: 'Client Secret',
              prefixIcon: Icon(Icons.lock_outline_rounded),
              hintText: '在Strava开发者页面获取',
            ),
            obscureText: true,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 24),
          // 保存凭证按钮
          SizedBox(
            height: 48,
            child: GradientButton(
              onPressed: _isLoading ? null : _saveCredentials,
              colors: [
                AppTheme.stravaColor.withOpacity(0.6),
                AppTheme.stravaColor.withOpacity(0.4),
              ],
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('保存凭证'),
            ),
          ),
          const SizedBox(height: 12),
          // 授权按钮
          SizedBox(
            height: 48,
            child: GradientButton(
              onPressed: _manager.hasCredentials ? _authorize : null,
              colors: [
                AppTheme.stravaColor,
                AppTheme.stravaColor.withOpacity(0.7),
              ],
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.open_in_new_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('授权 Strava'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      opacity: 0.06,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline_rounded,
                  color: Colors.white.withOpacity(0.6), size: 18),
              const SizedBox(width: 8),
              Text(
                '如何获取 Strava API 凭证',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStep('1', '访问 strava.com/settings/api'),
          _buildStep('2', '创建应用获取 Client ID 和 Secret'),
          _buildStep('3', '授权后即可同步运动数据'),
        ],
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppTheme.stravaColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: AppTheme.stravaColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    super.dispose();
  }
}
