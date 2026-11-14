import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography roles from the blueprint:
///   Display header : Space Grotesk 700 / 500
///   Body / UI      : Inter 400 / 500 / 600
///   Telemetry      : JetBrains Mono 500
///
/// Telemetry is used for anything that is a *measurement* - velocity scores,
/// listener counts, precision radius, timestamps. Keeping that rule makes the
/// radar read like an instrument, not a feed.
abstract final class PulseType {
  static TextStyle display(double size, {FontWeight? weight}) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.1,
      );

  static TextStyle body(double size, {FontWeight? weight}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        height: 1.35,
      );

  /// Monospaced telemetry. Always uppercase, always letter-spaced.
  static TextStyle telemetry(double size, {FontWeight? weight}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w500,
        letterSpacing: 0.6,
        height: 1.2,
      );

  /// Smallest label used on pills, zone chips and section headers.
  static TextStyle microLabel({double size = 10.5}) => GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
      );
}
