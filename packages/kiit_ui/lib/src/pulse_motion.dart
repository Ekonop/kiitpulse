import 'package:flutter/material.dart';

/// Motion tokens for KIITPulse.
///
/// One language everywhere: things arrive by moving *up* a few pixels and
/// fading, never by sliding in from off-screen. Durations are short because
/// the app is checked in a corridor, not admired. Every curve is a decelerate
/// so nothing feels like it is racing the user.
abstract final class PulseMotion {
  // ---- Durations ---------------------------------------------------------
  /// Micro feedback: colour, opacity, icon swaps.
  static const Duration fast = Duration(milliseconds: 140);

  /// Standard state change: pill selection, banner expand.
  static const Duration base = Duration(milliseconds: 240);

  /// Entrances and large layout moves.
  static const Duration slow = Duration(milliseconds: 420);

  /// Staggered list entrance step.
  static const Duration stagger = Duration(milliseconds: 38);

  // ---- Curves ------------------------------------------------------------
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasis = Curves.easeOutBack;
  static const Curve soft = Curves.easeOutQuart;

  // ---- Standard offsets --------------------------------------------------
  /// How far a card rises while fading in.
  static const double riseDistance = 14;

  /// Cap on stagger so a long list does not feel slow past the fold.
  static const int maxStaggerIndex = 8;

  static Duration staggerFor(int index) {
    final capped = index.clamp(0, maxStaggerIndex);
    return Duration(
      milliseconds: stagger.inMilliseconds * capped,
    );
  }

  /// Respect the platform's reduce-motion setting. Callers use this to decide
  /// between an animated transition and an instant one.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Duration that collapses to zero when reduce-motion is on.
  static Duration resolve(BuildContext context, Duration duration) =>
      reduceMotion(context) ? Duration.zero : duration;
}
