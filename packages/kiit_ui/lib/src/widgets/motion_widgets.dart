import 'dart:async';

import 'package:flutter/material.dart';

import '../pulse_motion.dart';

/// Fades and lifts its child into place once, on first build.
///
/// Used by the radar list so a fresh feed assembles rather than snapping in.
/// [index] staggers siblings; it is capped so item 40 does not wait 1.5s.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = PulseMotion.slow,
    this.distance = PulseMotion.riseDistance,
  });

  final Widget child;
  final int index;
  final Duration duration;
  final double distance;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  Animation<double>? _curve;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _curve = CurvedAnimation(parent: _c, curve: PulseMotion.enter);
    // Let the frame land before starting, so the entrance is visible even on
    // a cold first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _delay = Timer(PulseMotion.staggerFor(widget.index), () {
        if (mounted) _c.forward();
      });
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _curve!;
    if (PulseMotion.reduceMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) {
        final t = curve.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, widget.distance * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// A number that counts to its new value instead of jumping.
///
/// Telemetry reads as live when the digits move. Used for the population
/// readout and velocity figures.
class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    required this.builder,
    this.duration = PulseMotion.base,
  });

  /// Null renders whatever the builder does with null (typically `--`).
  final int? value;
  final Widget Function(BuildContext context, int? value) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final motion = PulseMotion.reduceMotion(context);
    if (motion) return builder(context, value);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: (value ?? 0).toDouble()),
      duration: duration,
      curve: PulseMotion.soft,
      builder: (context, animated, _) {
        // While there is no value at all, show the empty state rather than 0.
        if (value == null) return builder(context, null);
        return builder(context, animated.round());
      },
    );
  }
}

/// Presses a card in slightly while held.
///
/// Subtle by design: 0.985 scale, not a bounce. A card that jumps feels cheap.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.985,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final motion = PulseMotion.reduceMotion(context);
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _down = false),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => _down = false);
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down && !motion ? widget.scale : 1.0,
        duration: PulseMotion.fast,
        curve: PulseMotion.enter,
        child: widget.child,
      ),
    );
  }
}

/// A shimmering line shown while content loads.
///
/// A gradient sweep rather than a spinner: it reads as "data is arriving"
/// instead of "the app is stuck".
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height = 10,
    this.radius = 4,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const base = Color(0xFF1B2129);
    const highlight = Color(0xFF232B35);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(-1 - _c.value * 2, 0),
                end: Alignment(1 - _c.value * 2, 0),
                colors: const [base, highlight, base],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Expands / collapses its child with an accordion, not a jump.
class AnimatedAccordion extends StatelessWidget {
  const AnimatedAccordion({
    super.key,
    required this.expanded,
    required this.child,
    this.duration = PulseMotion.base,
  });

  final bool expanded;
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: PulseMotion.resolve(context, duration),
      curve: PulseMotion.soft,
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: AnimatedVisible(
          visible: expanded,
          child: child,
        ),
      ),
    );
  }
}

/// Fades + clips so a collapsed widget takes no space without losing state.
class AnimatedVisible extends StatelessWidget {
  const AnimatedVisible({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: PulseMotion.resolve(context, PulseMotion.base),
      curve: PulseMotion.enter,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: child,
    );
  }
}
