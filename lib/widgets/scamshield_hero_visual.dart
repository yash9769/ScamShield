import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Reusable signature hero security visual component.
/// Displays an abstract digital security object with soft atmospheric glow,
/// layered geometric shield, cobalt/violet lighting, subtle emerald highlights,
/// and a restrained breathing animation.
class ScamShieldHeroVisual extends StatefulWidget {
  final double size;
  final bool isThreat;
  final bool isSafe;

  const ScamShieldHeroVisual({
    super.key,
    this.size = 220,
    this.isThreat = false,
    this.isSafe = true,
  });

  @override
  State<ScamShieldHeroVisual> createState() => _ScamShieldHeroVisualState();
}

class _ScamShieldHeroVisualState extends State<ScamShieldHeroVisual>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _breathAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    _breathAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _rotationAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _animController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.isThreat
        ? AppColors.danger
        : (widget.isSafe ? AppColors.cobalt : AppColors.warning);
    final secondaryColor = widget.isThreat
        ? const Color(0xFFFF8A93)
        : (widget.isSafe ? AppColors.softViolet : AppColors.warning);
    final highlightColor = widget.isThreat
        ? AppColors.danger
        : AppColors.safeEmerald;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final breath = _breathAnimation.value;
        final rot = _rotationAnimation.value;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer Atmospheric Soft Glow
              Transform.scale(
                scale: breath,
                child: Container(
                  width: widget.size * 0.9,
                  height: widget.size * 0.9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        primaryColor.withValues(alpha: 0.28),
                        secondaryColor.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),

              // Orbiting Protective Ring
              Transform.rotate(
                angle: rot * 0.15,
                child: Container(
                  width: widget.size * 0.85,
                  height: widget.size * 0.85,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.15),
                      width: 1.5,
                    ),
                  ),
                ),
              ),

              // Inner Protective Dashed Arc Ring
              Transform.rotate(
                angle: -rot * 0.25,
                child: CustomPaint(
                  size: Size(widget.size * 0.72, widget.size * 0.72),
                  painter: _RingArcPainter(
                    color: highlightColor.withValues(alpha: 0.35),
                  ),
                ),
              ),

              // Layered Glass Shield
              Transform.scale(
                scale: breath * 0.98,
                child: CustomPaint(
                  size: Size(widget.size * 0.55, widget.size * 0.65),
                  painter: _GeometricShieldPainter(
                    primaryColor: primaryColor,
                    secondaryColor: secondaryColor,
                    highlightColor: highlightColor,
                  ),
                ),
              ),

              // Central Brand Core Icon
              Icon(
                widget.isThreat
                    ? Icons.gpp_bad_rounded
                    : Icons.verified_user_rounded,
                color: Colors.white,
                size: widget.size * 0.24,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RingArcPainter extends CustomPainter {
  final Color color;

  _RingArcPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      1.2,
      false,
      paint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      3.14,
      1.4,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingArcPainter oldDelegate) =>
      color != oldDelegate.color;
}

class _GeometricShieldPainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;
  final Color highlightColor;

  _GeometricShieldPainter({
    required this.primaryColor,
    required this.secondaryColor,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    final path = Path()
      ..moveTo(width * 0.5, 0)
      ..cubicTo(width * 0.85, 0, width, height * 0.15, width, height * 0.4)
      ..cubicTo(width, height * 0.75, width * 0.6, height * 0.92, width * 0.5, height)
      ..cubicTo(width * 0.4, height * 0.92, 0, height * 0.75, 0, height * 0.4)
      ..cubicTo(0, height * 0.15, width * 0.15, 0, width * 0.5, 0)
      ..close();

    // Glass Inner Fill
    final fillGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        primaryColor.withValues(alpha: 0.35),
        secondaryColor.withValues(alpha: 0.15),
        AppColors.elevatedSurface.withValues(alpha: 0.4),
      ],
    );

    final fillPaint = Paint()
      ..shader = fillGradient.createShader(Rect.fromLTWH(0, 0, width, height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);

    // Glowing Border
    final borderGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        highlightColor.withValues(alpha: 0.8),
        primaryColor,
        secondaryColor.withValues(alpha: 0.4),
      ],
    );

    final borderPaint = Paint()
      ..shader = borderGradient.createShader(Rect.fromLTWH(0, 0, width, height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _GeometricShieldPainter oldDelegate) =>
      primaryColor != oldDelegate.primaryColor ||
      secondaryColor != oldDelegate.secondaryColor ||
      highlightColor != oldDelegate.highlightColor;
}
