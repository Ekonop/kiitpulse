import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pulse_palette.dart';
import 'pulse_typography.dart';

/// The single ThemeData for KIITPulse.
///
/// The blueprint is dark-only on purpose (low-light campus venues, OLED). We
/// still declare [ThemeMode.dark] explicitly and keep light==dark so the app
/// never flashes a white frame on cold start.
abstract final class PulseTheme {
  static ThemeData get darkTheme {
    const scheme = ColorScheme.dark(
      primary: PulsePalette.kiitEmerald,
      onPrimary: Color(0xFF00160A),
      secondary: PulsePalette.coralStage,
      onSecondary: Color(0xFF2A0507),
      surface: PulsePalette.elevatedSurface,
      onSurface: PulsePalette.textPrimary,
      surfaceContainerHighest: PulsePalette.raisedSurface,
      error: PulsePalette.coralStage,
      onError: Color(0xFF2A0507),
      outline: PulsePalette.borderGrey,
      outlineVariant: PulsePalette.borderGreyStrong,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: PulsePalette.deepObsidian,
      canvasColor: PulsePalette.deepObsidian,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: PulsePalette.deepObsidian,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: PulseType.display(17)
            .copyWith(color: PulsePalette.textPrimary),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: PulsePalette.elevatedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: PulsePalette.borderGrey),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: PulsePalette.borderGrey,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PulsePalette.raisedSurface,
        hintStyle: PulseType.body(14)
            .copyWith(color: PulsePalette.textTertiary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: _inputBorder(PulsePalette.borderGrey),
        enabledBorder: _inputBorder(PulsePalette.borderGrey),
        focusedBorder: _inputBorder(PulsePalette.kiitEmerald, width: 1.4),
        errorBorder: _inputBorder(PulsePalette.coralStage),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: PulsePalette.kiitEmerald,
          foregroundColor: const Color(0xFF00160A),
          disabledBackgroundColor: PulsePalette.raisedSurface,
          disabledForegroundColor: PulsePalette.textTertiary,
          minimumSize: const Size.fromHeight(48),
          textStyle:
              PulseType.body(14.5, weight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: PulsePalette.textSecondary,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PulsePalette.elevatedSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: PulsePalette.elevatedSurface,
        showDragHandle: true,
        dragHandleColor: PulsePalette.borderGreyStrong,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: PulsePalette.raisedSurface,
        contentTextStyle: PulseType.body(13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: PulsePalette.kiitEmerald,
      ),
      extensions: const <ThemeExtension<dynamic>>[],
    );
  }

  /// The app is dark-only; expose it under the conventional name too.
  static ThemeData get lightTheme => darkTheme;

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    return base.copyWith(
      displayLarge: PulseType.display(30)
          .copyWith(color: PulsePalette.textPrimary),
      displayMedium: PulseType.display(24)
          .copyWith(color: PulsePalette.textPrimary),
      titleLarge: PulseType.display(17)
          .copyWith(color: PulsePalette.textPrimary),
      titleMedium: PulseType.body(15, weight: FontWeight.w600)
          .copyWith(color: PulsePalette.textPrimary),
      titleSmall: PulseType.body(13.5, weight: FontWeight.w600)
          .copyWith(color: PulsePalette.textPrimary),
      bodyLarge: PulseType.body(14.5)
          .copyWith(color: PulsePalette.textSecondary),
      bodyMedium: PulseType.body(13.5)
          .copyWith(color: PulsePalette.textSecondary),
      bodySmall: PulseType.body(12)
          .copyWith(color: PulsePalette.textTertiary),
      labelLarge: PulseType.body(13, weight: FontWeight.w600)
          .copyWith(color: PulsePalette.textPrimary),
      labelSmall: PulseType.telemetry(11)
          .copyWith(color: PulsePalette.kiitEmerald),
    );
  }
}
