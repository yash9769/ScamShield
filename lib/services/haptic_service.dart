// lib/services/haptic_service.dart
// Haptic feedback service for tactile user feedback.

import 'package:flutter/services.dart';

class HapticService {
  HapticService._();

  /// Light haptic feedback — used for general interactions (button taps, selections)
  static Future<void> lightTap() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {
      // Silently fail on devices without haptic support
    }
  }

  /// Medium haptic feedback — used for significant interactions (scan start/end, warnings)
  static Future<void> mediumImpact() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {
      // Silently fail on devices without haptic support
    }
  }

  /// Heavy haptic feedback — used for critical alerts (breach detected, high risk)
  static Future<void> heavyImpact() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {
      // Silently fail on devices without haptic support
    }
  }

  /// Success pattern — two light taps for positive feedback
  static Future<void> successPattern() async {
    try {
      await HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.lightImpact();
    } catch (_) {
      // Silently fail on devices without haptic support
    }
  }

  /// Error pattern — heavy tap for critical feedback
  static Future<void> errorPattern() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {
      // Silently fail on devices without haptic support
    }
  }

  /// Selection changed feedback
  static Future<void> selectionClick() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {
      // Silently fail on devices without haptic support
    }
  }
}
