import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

/// Reusable Premium CTA Button component.
/// Displays a sleek Cobalt gradient action button with subtle elevation,
/// smooth press feedback, and crisp typography.
class PremiumCTA extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isSecondary;
  final bool isDanger;
  final double height;
  final double? width;

  const PremiumCTA({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isSecondary = false,
    this.isDanger = false,
    this.height = 56,
    this.width,
  });

  @override
  State<PremiumCTA> createState() => _PremiumCTAState();
}

class _PremiumCTAState extends State<PremiumCTA> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onPressed != null) _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onPressed != null) _controller.reverse();
  }

  void _onTapCancel() {
    if (widget.onPressed != null) _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    final Color bgColor = widget.isDanger
        ? AppColors.danger
        : (widget.isSecondary ? AppColors.surface : AppColors.cobalt);

    final Gradient? gradient = widget.isSecondary || widget.isDanger || !enabled
        ? null
        : const LinearGradient(
            colors: [AppColors.cobalt, AppColors.electricBlue],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          );

    final Color textColor = widget.isSecondary
        ? AppColors.textPrimary
        : (enabled ? Colors.white : AppColors.mutedText);

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: widget.width ?? double.infinity,
            height: widget.height,
            decoration: BoxDecoration(
              gradient: gradient,
              color: gradient == null ? bgColor : null,
              borderRadius: BorderRadius.circular(16),
              border: widget.isSecondary
                  ? Border.all(color: AppColors.border, width: 1.5)
                  : null,
              boxShadow: !widget.isSecondary && enabled
                  ? [
                      BoxShadow(
                        color: (widget.isDanger ? AppColors.danger : AppColors.cobalt)
                            .withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: textColor, size: 20),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    widget.label,
                    style: GoogleFonts.plusJakartaSans(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
