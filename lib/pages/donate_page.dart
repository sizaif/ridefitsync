import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import '../l10n/strings.dart';

class DonatePage extends StatelessWidget {
  const DonatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(S.current.donateTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.withValues(alpha: 0.15), Colors.red.withValues(alpha: 0.1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.favorite_rounded, color: Colors.red, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    S.current.donateThanks,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.current.donateDesc,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: theme.hintColor, height: 1.5),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms),
            const SizedBox(height: 24),

            _buildQrCard(
              context,
              theme,
              title: S.current.alipay,
              icon: Icons.account_balance_wallet_rounded,
              color: const Color(0xFF1677FF),
              assetPath: 'assets/donate/zfb.jpg',
              isDark: isDark,
            ),
            const SizedBox(height: 16),

            _buildQrCard(
              context,
              theme,
              title: S.current.wechatPay,
              icon: Icons.chat_rounded,
              color: const Color(0xFF07C160),
              assetPath: 'assets/donate/wx.png',
              isDark: isDark,
            ),
            const SizedBox(height: 32),

            Text(
              S.current.donateFooter,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: theme.hintColor.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 8),
            Text(
              S.current.donateThanks2,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrCard(
    BuildContext context,
    ThemeData theme, {
    required String title,
    required IconData icon,
    required Color color,
    required String assetPath,
    required bool isDark,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _showFullScreenImage(context, assetPath),
              onLongPress: () => _saveImage(context, assetPath),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 220,
                  height: 220,
                  color: isDark ? Colors.white : theme.scaffoldBackgroundColor,
                  child: Image.asset(
                    assetPath,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_2_rounded, size: 64, color: theme.hintColor.withValues(alpha: 0.3)),
                          const SizedBox(height: 8),
                          Text(
                            '请将收款码放入\n$assetPath',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: theme.hintColor.withValues(alpha: 0.5)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 200.ms);
  }

  void _showFullScreenImage(BuildContext context, String assetPath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.asset(assetPath),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveImage(BuildContext context, String assetPath) async {
    try {
      final byteData = await DefaultAssetBundle.of(context).load(assetPath);
      final bytes = byteData.buffer.asUint8List();

      // 保存到 Pictures 目录
      final dir = await getApplicationDocumentsDirectory();
      final ext = assetPath.split('.').last;
      final fileName = 'donate_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.current.donateThanks} 图片已保存到 $fileName')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }
}
