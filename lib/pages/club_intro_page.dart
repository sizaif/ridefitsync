import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../l10n/strings.dart';
import '../theme/glass_card.dart';

class ClubIntroPage extends StatefulWidget {
  const ClubIntroPage({super.key});

  @override
  State<ClubIntroPage> createState() => _ClubIntroPageState();
}

class _ClubIntroPageState extends State<ClubIntroPage> {
  String? _introText;

  @override
  void initState() {
    super.initState();
    _loadIntroText();
  }

  Future<void> _loadIntroText() async {
    try {
      final text = await DefaultAssetBundle.of(context)
          .loadString('assets/club/introduce');
      if (mounted) setState(() => _introText = text);
    } catch (_) {
      // 文件加载失败，保持 null，build 中显示加载中
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(title: Text(S.current.clubIntroTitle)),
      body: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
          children: [
            const SizedBox(height: 8),

            // === 俱乐部 Logo ===
            _buildLogoSection(theme, isDark: isDark)
                .animate()
                .fadeIn(duration: 500.ms)
                .scale(begin: const Offset(0.9, 0.9)),

            const SizedBox(height: 24),

            // === 宣传图片 ===
            _buildPromoImage(theme)
                .animate()
                .fadeIn(duration: 500.ms, delay: 150.ms),

            const SizedBox(height: 24),

            // === 俱乐部介绍文字 ===
            _buildIntroSection(theme)
                .animate()
                .fadeIn(duration: 400.ms, delay: 250.ms)
                .slideY(begin: 0.1, end: 0),

            const SizedBox(height: 16),

            // === 加入方式 ===
            _buildJoinSection(theme)
                .animate()
                .fadeIn(duration: 400.ms, delay: 350.ms)
                .slideY(begin: 0.1, end: 0),

            const SizedBox(height: 32),
          ],
        ),
      ),
      ),
    );
  }

  // ---- Logo 区域 ----
  Widget _buildLogoSection(ThemeData theme, {required bool isDark}) {
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2E7D32).withValues(alpha: isDark ? 0.3 : 0.15),
            const Color(0xFF66BB6A).withValues(alpha: isDark ? 0.2 : 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // Logo
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/club/logo.png',
              width: 100,
              height: 100,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF43A047), Color(0xFF2E7D32)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.directions_bike_rounded,
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            S.current.clubName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            S.current.clubSlogan,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ---- 宣传图片 ----
  Widget _buildPromoImage(ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.asset(
        'assets/club/promo.jpg',
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF4CAF50).withValues(alpha: 0.15),
                const Color(0xFF81C784).withValues(alpha: 0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_rounded,
                  size: 48,
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.4)),
              const SizedBox(height: 8),
              Text(
                'assets/club/promo.jpg',
                style: TextStyle(
                    fontSize: 12,
                    color: theme.hintColor.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 俱乐部介绍 ----
  Widget _buildIntroSection(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(20),
      opacity: 0.08,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: Color(0xFF4CAF50), size: 22),
              const SizedBox(width: 8),
              Text(
                S.current.clubAbout,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_introText == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Text(
              _introText!,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                height: 1.8,
              ),
            ),
        ],
      ),
    );
  }

  // ---- 加入方式 ----
  Widget _buildJoinSection(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(20),
      opacity: 0.08,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_add_rounded,
                  color: Color(0xFF4CAF50), size: 22),
              const SizedBox(width: 8),
              Text(
                S.current.clubJoinUs,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            S.current.clubJoinIntro,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
              height: 1.8,
            ),
          ),
          const SizedBox(height: 12),
          // 微信号 — 重点突出
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.chat_rounded,
                    color: Color(0xFF4CAF50), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '微信',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'wzj19791116qy',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2E7D32),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.copy_rounded,
                    size: 18, color: const Color(0xFF4CAF50).withValues(alpha: 0.6)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            S.current.clubJoinActivity,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }
}
