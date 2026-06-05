import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 毛玻璃效果卡片组件
class GlassCard extends StatelessWidget {
  final Widget child;
  final double? blur;
  final double? opacity;
  final double? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.blur,
    this.opacity,
    this.borderRadius,
    this.padding,
    this.margin,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBlur = blur ?? AppTheme.glassBlur;
    final effectiveOpacity = opacity ?? AppTheme.glassOpacity;
    final effectiveRadius = borderRadius ?? AppTheme.glassBorderRadius;

    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(effectiveRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(effectiveOpacity),
            borderRadius: BorderRadius.circular(effectiveRadius),
            border: Border.all(
              color: Colors.white.withOpacity(AppTheme.glassBorderOpacity),
              width: 1,
            ),
          ),
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }

    return card;
  }
}

/// 带呼吸光晕效果的容器
class GlowContainer extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final double borderRadius;

  const GlowContainer({
    super.key,
    required this.child,
    this.glowColor = AppTheme.accent,
    this.borderRadius = 16,
  });

  @override
  State<GlowContainer> createState() => _GlowContainerState();
}

class _GlowContainerState extends State<GlowContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withOpacity(_animation.value * 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 渐变按钮
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final List<Color>? colors;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.colors,
    this.borderRadius = 12,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColors = colors ??
        [AppTheme.accent, AppTheme.accent.withOpacity(0.8)];
    final isEnabled = onPressed != null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: isEnabled
            ? LinearGradient(colors: effectiveColors)
            : null,
        color: isEnabled ? null : Colors.white.withOpacity(0.1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: padding ??
                const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              child: IconTheme(
                data: const IconThemeData(color: Colors.white),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
