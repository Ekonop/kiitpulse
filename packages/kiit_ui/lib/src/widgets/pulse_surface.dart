import 'package:flutter/material.dart';

import '../pulse_palette.dart';

/// The card shell used everywhere on the radar and in the passport.
///
/// [accent] drives the border and an optional left "rail" so a live voice card
/// is distinguishable from an academic thread at a glance, without reading.
class PulseSurface extends StatelessWidget {
  const PulseSurface({
    super.key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(14),
    this.radius = 14,
    this.onTap,
    this.live = false,
  });

  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  /// Live surfaces get a slightly stronger border and a soft accent wash.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final borderColor = accent != null
        ? accent!.withValues(alpha: live ? 0.55 : 0.35)
        : PulsePalette.borderGrey;

    final content = Container(
      decoration: BoxDecoration(
        color: PulsePalette.elevatedSurface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        gradient: live && accent != null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent!.withValues(alpha: 0.07),
                  PulsePalette.elevatedSurface,
                ],
                stops: const [0, 0.7],
              )
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: (accent ?? PulsePalette.kiitEmerald)
                .withValues(alpha: 0.08),
            highlightColor: Colors.transparent,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );

    return content;
  }
}
