import 'package:flutter/widgets.dart';

/// Semantic colour tokens for KIITPulse.
///
/// The blueprint fixes four brand colours. Everything else in the UI derives
/// from these so a re-theme is a one-file change. Never hardcode a hex in a
/// feature file; pull it from here.
abstract final class PulsePalette {
  // ---- Brand / surface ladder -------------------------------------------
  /// App background. Dark-first: KIIT venues are low-light and OLED.
  static const deepObsidian = Color(0xFF0B0D10);

  /// Card shell / pinned banner / app bar.
  static const elevatedSurface = Color(0xFF14181F);

  /// One step above elevated, for inputs, chips and pressed states.
  static const raisedSurface = Color(0xFF1B2129);

  /// Primary brand. Verified, trending, affirmative.
  static const kiitEmerald = Color(0xFF00C853);

  /// Live audio. Speaks for stages, speakers and destructive audio actions.
  static const coralStage = Color(0xFFFF4D4D);

  // ---- Text --------------------------------------------------------------
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9EAEC0);
  static const textTertiary = Color(0xFF5A6E85);

  // ---- Lines -------------------------------------------------------------
  static const borderGrey = Color(0xFF2A343F);
  static const borderGreyStrong = Color(0xFF3A4756);

  // ---- Semantic extras ---------------------------------------------------
  /// Hit "0" in campus; a topic is decaying but not dead.
  static const amberWarn = Color(0xFFFFB300);

  /// Locked / off-campus / mock-GPS detected.
  static const dangerMuted = Color(0xFF7A3A3F);

  // ---- Derived helpers ---------------------------------------------------
  static Color emeraldAlpha(double opacity) =>
      kiitEmerald.withValues(alpha: opacity);

  static Color coralAlpha(double opacity) => coralStage.withValues(alpha: opacity);
}
