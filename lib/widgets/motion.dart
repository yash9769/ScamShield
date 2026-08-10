import 'package:flutter/material.dart';

/// ScamShield motion toolkit
/// ─────────────────────────
/// Small, dependency-free animation primitives shared across every screen so
/// the app feels cohesive and premium without pulling in extra packages.
///
/// Everything here is built on [TweenAnimationBuilder], [AnimatedScale] and
/// core widgets — no long-lived controllers to leak, safe to use inside lists.

/// A one-shot entrance animation: content fades in while easing upward.
///
/// Use [delay] to stagger a column/grid of items (see [Reveal.step]):
/// ```dart
/// children: items.asMap().entries.map((e) =>
///   Reveal(delay: Reveal.step(e.key), child: e.value)).toList()
/// ```
class Reveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Vertical travel in logical pixels (positive = slides up into place).
  final double offsetY;

  /// Optional horizontal travel (positive = slides left into place).
  final double offsetX;

  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.offsetY = 22,
    this.offsetX = 0,
  });

  /// Staggered delay for the i-th item in a list. Tuned to feel brisk, not laggy.
  static Duration step(int index, {int stepMs = 65, int baseMs = 40}) =>
      Duration(milliseconds: baseMs + index * stepMs);

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> {
  bool _run = false;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _run = true;
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) setState(() => _run = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: _run ? 1 : 0),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final inv = 1 - t;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(inv * widget.offsetX, inv * widget.offsetY),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Tactile tap feedback: gently scales the child down while pressed and springs
/// back on release. Wrap any card/button; keep the child's own visuals intact.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final HitTestBehavior behavior;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A smooth fade-through page transition for explicit navigations.
/// (App-wide default transitions are set in theme.dart's pageTransitionsTheme;
/// use this when you want the effect on a specific push.)
Route<T> fadeThroughRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// A continuously rotating radar sweep — a soft beam of [color] that fades
/// behind itself as it circles. Signature "actively scanning" motif; drop a
/// [child] (e.g. an icon) in the center and it stays still while the beam turns.
class RadarSweep extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;
  final Widget? child;

  const RadarSweep({
    super.key,
    required this.color,
    this.size = 150,
    this.duration = const Duration(seconds: 4),
    this.child,
  });

  @override
  State<RadarSweep> createState() => _RadarSweepState();
}

class _RadarSweepState extends State<RadarSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration)..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(
            turns: _c,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    widget.color.withValues(alpha: 0.0),
                    widget.color.withValues(alpha: 0.0),
                    widget.color.withValues(alpha: 0.28),
                    widget.color.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.62, 0.9, 1.0],
                ),
              ),
            ),
          ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

/// A slow, ambient pulse (opacity + scale) for "live/active" glyphs such as
/// status dots and shield glows. Wrap a small decorative widget.
class LivePulse extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double minOpacity;
  final double minScale;

  const LivePulse({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1600),
    this.minOpacity = 0.45,
    this.minScale = 0.9,
  });

  @override
  State<LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: widget.minOpacity, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: widget.minScale, end: 1.0).animate(
          CurvedAnimation(parent: _c, curve: Curves.easeInOut),
        ),
        child: widget.child,
      ),
    );
  }
}
