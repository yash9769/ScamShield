// lib/widgets/ui_kit.dart
//
// The shared component vocabulary for ScamShield's screens.
//
// Before this existed, every screen hand-rolled its own Container with its own
// padding, radius, border alpha and shadow — which is why "a card" looked
// subtly different on Home, History, Family and Profile, and why changing the
// look of anything meant editing twenty files. These are the pieces screens
// compose from now, so consistency is the default rather than something each
// screen has to remember.
//
// Deliberately small. Six components covers essentially every layout in the
// app; a kit that tries to cover every case stops being learnable and screens
// go back to hand-rolling.

import 'package:flutter/material.dart';

import '../theme.dart';

// ── Verdicts ─────────────────────────────────────────────────────────────────

/// The three answers ScamShield can give. Everything about how a verdict looks
/// and what it tells the user to do lives here, so the Scan screen, History,
/// Home and Simple Mode cannot drift into describing the same result three
/// different ways — which they previously did.
enum Verdict { safe, caution, scam }

class VerdictStyle {
  final Verdict verdict;
  final Color color;
  final IconData icon;

  /// The one-word answer.
  final String label;

  /// What to actually do about it. This is the part that matters: a risk score
  /// is a measurement, and someone mid-scam needs an instruction.
  final String advice;

  const VerdictStyle({
    required this.verdict,
    required this.color,
    required this.icon,
    required this.label,
    required this.advice,
  });
}

/// Maps the stored classification string ('safe' | 'suspicious' | 'scam') to
/// its presentation. Unknown values fall back to caution rather than safe —
/// telling someone a message is fine because we failed to parse our own
/// verdict is the one mistake worth engineering against.
VerdictStyle verdictStyleFor(String classification) {
  switch (classification.trim().toLowerCase()) {
    case 'scam':
      return const VerdictStyle(
        verdict: Verdict.scam,
        color: AppColors.danger,
        icon: Icons.dangerous_rounded,
        label: 'Scam',
        advice: 'Do not reply, tap any link, or send money. It is safe to delete this.',
      );
    case 'safe':
      return const VerdictStyle(
        verdict: Verdict.safe,
        color: AppColors.success,
        icon: Icons.check_circle_rounded,
        label: 'Looks safe',
        advice: 'Nothing dangerous found. Still never share a code with someone who '
            'contacted you first.',
      );
    default:
      return const VerdictStyle(
        verdict: Verdict.caution,
        color: AppColors.warning,
        icon: Icons.warning_rounded,
        label: 'Be careful',
        advice: 'This may not be genuine. Do not send money or share any code.',
      );
  }
}

/// A compact verdict chip for lists and headers.
///
/// Always icon + word, never colour alone: roughly one in twelve men has some
/// form of colour blindness, and red/green is the pair they most often can't
/// separate — which happens to be exactly the distinction this app exists to
/// communicate.
class VerdictBadge extends StatelessWidget {
  final String classification;
  final bool compact;

  const VerdictBadge(this.classification, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final v = verdictStyleFor(classification);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: v.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(v.icon, color: v.color, size: compact ? 13 : 15),
          const SizedBox(width: 5),
          Text(
            v.label,
            style: TextStyle(
              color: v.color,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Surfaces ─────────────────────────────────────────────────────────────────

/// The standard raised surface: one radius, one border, one padding.
///
/// [tone] tints the border and background for the rare case where a card
/// carries a verdict — used for the scan result, not for decoration.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? tone;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = tone?.withValues(alpha: 0.35) ?? AppColors.surfaceLight;
    final content = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tone?.withValues(alpha: 0.08) ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: content,
      ),
    );
  }
}

/// A labelled group of content. The label is sentence case and muted — the
/// replacement for the old ALL-CAPS, letter-spaced section headers.
class AppSection extends StatelessWidget {
  final String label;
  final Widget child;

  /// Optional right-aligned action ("See all").
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppSection({
    super.key,
    required this.label,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppText.label)),
            if (actionLabel != null && onAction != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    );
  }
}

// ── Rows ─────────────────────────────────────────────────────────────────────

/// The workhorse row: leading icon, title, optional subtitle, optional
/// trailing. Used for settings, menus and any tappable list item.
///
/// The icon sits in a neutral tile rather than being tinted a different colour
/// per row. Twelve differently-coloured icons in a settings list is twelve
/// things competing for attention, none of which is the one the user came for.
class AppListRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// For genuinely destructive rows only (delete account, erase data).
  final bool destructive;

  const AppListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final tint = destructive ? AppColors.danger : AppColors.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: destructive
                      ? AppColors.danger.withValues(alpha: 0.12)
                      : AppColors.surfaceLight.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 19, color: tint),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppText.subheading.copyWith(color: tint),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AppText.secondary),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ] else if (onTap != null)
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Groups [AppListRow]s into one card with hairlines between them, the way a
/// settings list is expected to look.
class AppListGroup extends StatelessWidget {
  final List<Widget> children;

  const AppListGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            // Inset so the rule starts at the text, not the card edge — it
            // separates rows without cutting the card in half.
            if (i != children.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 64, right: AppSpacing.lg),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Empty states ─────────────────────────────────────────────────────────────

/// What a screen shows when it has nothing — which, for a brand-new install,
/// is most screens. Treated as a real state with an action rather than a
/// shrug, because it is the first thing a new user actually sees.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxxl,
        horizontal: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: AppText.subheading, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs),
          Text(message, style: AppText.secondary, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
