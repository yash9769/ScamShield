// lib/utils/accessibility_utils.dart
// Accessibility utilities for semantic labeling and WCAG compliance.

import 'package:flutter/material.dart';

/// Wrapper for adding semantic information to widgets for screen readers.
/// Use this to label interactive elements and ensure accessibility.
class AccessibleWidget extends StatelessWidget {
  final Widget child;
  final String label;
  final String? hint;
  final bool enabled;

  const AccessibleWidget({
    super.key,
    required this.child,
    required this.label,
    this.hint,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      hint: hint,
      enabled: enabled,
      onTap: null,
      child: child,
    );
  }
}

/// Accessible button wrapper with semantic labeling.
class AccessibleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final String label;
  final String? hint;

  const AccessibleButton({
    super.key,
    required this.onPressed,
    required this.child,
    required this.label,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      label: label,
      hint: hint,
      child: child,
    );
  }
}

/// Accessible text input with semantic labeling.
class AccessibleTextInput extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final TextInputType keyboardType;
  final InputDecoration? decoration;

  const AccessibleTextInput({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.keyboardType = TextInputType.text,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      enabled: true,
      label: label,
      hint: hint,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: decoration ??
            InputDecoration(
              labelText: label,
              hintText: hint,
              helperText: 'Enter ${label.toLowerCase()}',
            ),
      ),
    );
  }
}

/// Extension for adding semantic labels to existing widgets.
extension AccessibilityExtension on Widget {
  /// Wrap this widget with semantic information for accessibility.
  Widget withSemantics(
    String label, {
    String? hint,
    bool enabled = true,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      enabled: enabled,
      child: this,
    );
  }

  /// Wrap this widget as a button for accessibility.
  Widget asAccessibleButton(
    String label, {
    String? hint,
    VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      label: label,
      hint: hint,
      child: this,
    );
  }

  /// Mark this widget as a heading for accessibility.
  Widget asHeading() {
    return Semantics(
      enabled: true,
      label: 'Heading',
      child: this,
    );
  }

  /// Mark this as a live region that announces changes.
  Widget asLiveRegion() {
    return Semantics(
      liveRegion: true,
      child: this,
    );
  }
}
