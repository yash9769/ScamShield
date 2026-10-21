// lib/widgets/animated_radar.dart
//
// Custom animated radar visual for premium cybersecurity scanning experience.
// Implements concentric rings, rotating sweep, pulsing center shield, and
// subtle threat markers with smooth, efficient animations.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

class AnimatedRadar extends StatefulWidget {
  final double size;
  final bool isScanning;
  final List<Offset>? threatMarkers;

  const AnimatedRadar({
    super.key,
    this.size = 200,
    this.isScanning = false,
    this.threatMarkers,
  });

  @override
  State<AnimatedRadar> createState() => _AnimatedRadarState();
}

class _AnimatedRadarState extends State<AnimatedRadar>
    with TickerProviderStateMixin {
  late AnimationController _sweepController;
  late AnimationController _pulseController;
  late Animation<double> _sweepAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Sweep animation - continuously rotates when scanning
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    // Pulsing animation for center shield
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _sweepAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _sweepController,
      curve: Curves.linear,
    ));

    _pulseAnimation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    if (widget.isScanning) {
      _sweepController.repeat();
    }
    _pulseController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant AnimatedRadar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning != oldWidget.isScanning) {
      if (widget.isScanning) {
        _sweepController.repeat();
      } else {
        _sweepController.stop();
      }
    }
  }

  @override
  void dispose() {
    _sweepController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_sweepAnimation, _pulseAnimation]),
        builder: (context, child) {
          return CustomPaint(
            painter: RadarPainter(
              sweepAngle: _sweepAnimation.value * 2 * math.pi,
              pulseScale: _pulseAnimation.value,
              isScanning: widget.isScanning,
              threatMarkers: widget.threatMarkers,
            ),
            child: Center(
              child: Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.protectionGradient,
                    boxShadow: [
                      BoxShadow(
                        color: widget.isScanning
                            ? AppColors.radarGlow
                            : AppColors.protectedGlow,
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.isScanning
                        ? Icons.search_rounded
                        : Icons.shield_rounded,
                    color: Colors.white,
                    size: widget.size * 0.18,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  final double sweepAngle;
  final double pulseScale;
  final bool isScanning;
  final List<Offset>? threatMarkers;

  RadarPainter({
    required this.sweepAngle,
    required this.pulseScale,
    required this.isScanning,
    this.threatMarkers,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Draw faint grid lines
    final gridPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw crosshairs
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      gridPaint,
    );

    // Draw concentric rings
    final ringPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 1; i <= 4; i++) {
      final radius = maxRadius * (i / 4);
      canvas.drawCircle(center, radius, ringPaint);
    }

    // Draw threat markers if provided
    if (threatMarkers != null) {
      final markerPaint = Paint()
        ..color = AppColors.danger.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;

      for (final marker in threatMarkers!) {
        canvas.drawCircle(
          Offset(center.dx + marker.dx * maxRadius, center.dy + marker.dy * maxRadius),
          4,
          markerPaint,
        );
      }
    }

    // Draw rotating sweep only when scanning
    if (isScanning) {
      final sweepPaint = Paint()
        ..style = PaintingStyle.fill
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: 0,
          endAngle: math.pi / 3,
          colors: [
            AppColors.primary.withValues(alpha: 0.4),
            AppColors.primary.withValues(alpha: 0.0),
          ],
          transform: GradientRotation(sweepAngle),
        ).createShader(Rect.fromCircle(center: center, radius: maxRadius));

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: maxRadius),
        sweepAngle,
        math.pi / 3,
        true,
        sweepPaint,
      );

      // Draw sweep line
      final linePaint = Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawLine(
        center,
        Offset(
          center.dx + math.cos(sweepAngle) * maxRadius,
          center.dy + math.sin(sweepAngle) * maxRadius,
        ),
        linePaint,
      );
    }

    // Outer glow border
    final outerRingPaint = Paint()
      ..color = isScanning
          ? AppColors.primary.withValues(alpha: 0.3)
          : AppColors.accent.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, maxRadius, outerRingPaint);
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return oldDelegate.sweepAngle != sweepAngle ||
        oldDelegate.pulseScale != pulseScale ||
        oldDelegate.isScanning != isScanning ||
        oldDelegate.threatMarkers != threatMarkers;
  }
}