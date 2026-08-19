import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

/// Reusable Security Score component.
/// Visually communicates risk metrics (e.g. 18 / 100 LOW RISK) with a dominant
/// numeric display, soft gradient ring, and dynamic status indicator.
class SecurityScore extends StatelessWidget {
  final int score;
  final String statusLabel;
  final bool compact;

  const SecurityScore({
    super.key,
    required this.score,
    this.statusLabel = 'LOW RISK',
    this.compact = false,
  });

  Color get statusColor {
    if (score >= 60) return AppColors.danger;
    if (score >= 30) return AppColors.warning;
    return AppColors.safeEmerald;
  }

  @override
  Widget build(BuildContext context) {
    final color = statusColor;
    final size = compact ? 110.0 : 150.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer Glow Ring
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      color.withValues(alpha: 0.22),
                      color.withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),

              // Circular Progress Indicator
              SizedBox(
                width: size * 0.82,
                height: size * 0.82,
                child: CircularProgressIndicator(
                  value: (score.clamp(0, 100)) / 100.0,
                  strokeWidth: compact ? 6 : 8,
                  backgroundColor: AppColors.border.withValues(alpha: 0.6),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  strokeCap: StrokeCap.round,
                ),
              ),

              // Dominant Score Display
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$score',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: compact ? 28 : 40,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1,
                          ),
                        ),
                        Text(
                          ' /100',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: compact ? 12 : 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Status Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                statusLabel.toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  color: color,
                  fontSize: compact ? 10 : 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
