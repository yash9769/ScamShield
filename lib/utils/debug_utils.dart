// lib/utils/debug_utils.dart
// Debug utilities that respect debug/release build mode.

import 'package:flutter/foundation.dart';

/// Log a debug message. Only prints in debug and profile modes,
/// completely removed in release mode by the compiler.
void appDebugPrint(String message, {String? tag}) {
  if (kDebugMode) {
    final prefix = tag != null ? '[$tag] ' : '';
    debugPrint('$prefix$message');
  }
}

/// Log an error message. Only prints in debug and profile modes,
/// completely removed in release mode by the compiler.
void appErrorPrint(String message, {String? tag, Error? error, StackTrace? stackTrace}) {
  if (kDebugMode) {
    final prefix = tag != null ? '[$tag] ERROR: ' : 'ERROR: ';
    debugPrint('$prefix$message');
    if (error != null) {
      debugPrint('Exception: $error');
    }
    if (stackTrace != null) {
      debugPrint('Stack trace:\n$stackTrace');
    }
  }
}

/// Log a warning message. Only prints in debug and profile modes,
/// completely removed in release mode by the compiler.
void appWarningPrint(String message, {String? tag}) {
  if (kDebugMode) {
    final prefix = tag != null ? '[$tag] WARNING: ' : 'WARNING: ';
    debugPrint('$prefix$message');
  }
}

/// Check if running in debug mode (includes profile builds).
bool get isDebugMode => kDebugMode;

/// Check if running in release mode.
bool get isReleaseMode => kReleaseMode;
