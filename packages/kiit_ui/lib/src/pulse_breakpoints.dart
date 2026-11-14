import 'package:flutter/widgets.dart';

/// Where a layout stops being a phone and starts being a window.
///
/// Three shapes, because there are three honest answers to "how much room is
/// there": a phone (one column, thumb-reachable nav at the bottom), a small
/// window or a tablet held sideways (one column, but with room to breathe), and
/// a desktop browser (a side rail and a column that does not stretch to the
/// full width of a 27-inch monitor).
///
/// The numbers are the CSS conventions a web user already expects, so the app
/// does not feel like a phone simulator on a laptop.
enum PulseFormFactor {
  /// A phone. Bottom navigation, edge-to-edge content.
  compact,

  /// A tablet, or a small laptop window. Bottom navigation, narrower content.
  medium,

  /// A desktop browser. Side rail, content column capped so text stays legible.
  expanded;

  /// Whether navigation belongs on the bottom edge.
  bool get usesBottomNav => this != PulseFormFactor.expanded;

  /// Whether navigation belongs on the leading side.
  bool get usesSideRail => this == PulseFormFactor.expanded;
}

/// Layout constants shared by the shell and the screens.
abstract final class PulseBreakpoints {
  /// Below this the layout is a phone.
  static const double compactMax = 700;

  /// At or above this the layout gets a side rail.
  static const double expandedMin = 1100;

  /// The widest the main column is allowed to get.
  ///
  /// A radar card stretched across 1600 pixels is unreadable - the eye cannot
  /// track from a title on the left to a velocity badge on the right. Capping
  /// the column is what makes the web build feel designed rather than scaled.
  static const double contentMaxWidth = 720;

  /// Width of the navigation rail in the expanded layout.
  static const double railWidth = 232;

  /// Classify a window width.
  static PulseFormFactor of(double width) {
    if (width >= expandedMin) return PulseFormFactor.expanded;
    if (width >= compactMax) return PulseFormFactor.medium;
    return PulseFormFactor.compact;
  }
}

/// Reads the current form factor from the widget tree.
///
/// Use this instead of checking `Platform.isAndroid` or a raw `MediaQuery`
/// width at each call site: one place decides what "mobile" means, and a
/// browser resized by the user is handled by the rebuild rather than a reload.
PulseFormFactor pulseFormFactorOf(BuildContext context) =>
    PulseBreakpoints.of(MediaQuery.sizeOf(context).width);

/// Constrains content to a readable column and centres it.
///
/// On a phone this is a no-op - the column is already narrower than the max,
/// so it stays edge to edge and no padding is added.
class PulseContentColumn extends StatelessWidget {
  const PulseContentColumn({
    super.key,
    required this.child,
    this.maxWidth = PulseBreakpoints.contentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
