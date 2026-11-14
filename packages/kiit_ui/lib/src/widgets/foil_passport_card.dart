import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../pulse_palette.dart';
import '../pulse_typography.dart';

/// A collectible passport badge rendered with a runtime fragment shader.
///
/// Gyroscope tilt is integrated into a small `_tilt` offset so the foil
/// catches the light as the phone moves. On Linux desktop there is no
/// gyroscope: [gyroAvailable] is false and the badge falls back to a slow
/// autonomous shimmer so the design still reads correctly in review.
class FoilPassportCard extends StatefulWidget {
  FoilPassportCard({
    super.key,
    required this.badgeName,
    required this.subtitle,
    this.accentColor = PulsePalette.kiitEmerald,
    this.width = 160,
    this.height = 220,
    this.issuedAt,
    bool? gyroAvailable,
  }) : gyroAvailable = gyroAvailable ?? _defaultGyroAvailable;

  final String badgeName;

  /// e.g. "KIIT Fest 2026 · Tech Lead"
  final String subtitle;
  final Color accentColor;
  final double width;
  final double height;
  final DateTime? issuedAt;

  /// Whether tilt input is available. Defaults to true only on the platforms
  /// that actually ship a sensor implementation.
  final bool gyroAvailable;

  static bool get _defaultGyroAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<FoilPassportCard> createState() => _FoilPassportCardState();
}

class _FoilPassportCardState extends State<FoilPassportCard>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  Offset _tilt = Offset.zero;
  bool _shaderFailed = false;

  @override
  void initState() {
    super.initState();
    _loadShader();
    if (widget.gyroAvailable) _listenGyro();
  }

  Future<void> _loadShader() async {
    try {
      final program =
          await ui.FragmentProgram.fromAsset('shaders/foil_badge.frag');
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } catch (_) {
      // Shader unavailable (e.g. software rendering): keep the gradient
      // fallback rather than showing a broken card.
      if (!mounted) return;
      setState(() => _shaderFailed = true);
    }
  }

  void _listenGyro() {
    // sensors_plus ships no Linux/Windows implementation. Without this gate the
    // channel throws MissingPluginException from an async context, which lands
    // in the zone as an *unhandled* error and can take the frame down - an
    // `onError` on the subscription does not help because the failure happens
    // before the subscription is established.
    if (!_platformHasSensors) return;

    try {
      _gyroSub = gyroscopeEventStream().listen(
        (GyroscopeEvent e) {
          if (!mounted) return;
          setState(() {
            _tilt = Offset(
              (_tilt.dx + e.y * 0.05).clamp(-1.0, 1.0),
              (_tilt.dy + e.x * 0.05).clamp(-1.0, 1.0),
            );
          });
        },
        onError: (Object _) {},
        cancelOnError: true,
      );
    } catch (_) {
      // Platform has no gyroscope - the autonomous shimmer covers it.
    }
  }

  /// Only Android and iOS ship sensor implementations today.
  bool get _platformHasSensors {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void dispose() {
    _gyroSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final shader = _shader;
              if (shader == null || _shaderFailed) {
                return _fallback();
              }
              return CustomPaint(
                painter: _FoilBadgePainter(
                  shader: shader,
                  time: _controller.value * 2 * math.pi * 12, // seconds -> radians
                  tilt: widget.gyroAvailable ? _tilt : _autonomousTilt(),
                  accentColor: widget.accentColor,
                ),
              );
            },
          ),
          // Legibility scrim: foil is busy, text must still be readable.
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    PulsePalette.deepObsidian.withValues(alpha: 0.15),
                    PulsePalette.deepObsidian.withValues(alpha: 0.86),
                  ],
                  stops: const [0.35, 0.6, 1.0],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  widget.badgeName.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PulseType.display(13.5)
                      .copyWith(color: Colors.white, letterSpacing: 0.2),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PulseType.body(10.5)
                      .copyWith(color: PulsePalette.textSecondary),
                ),
                if (widget.issuedAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _fmtDate(widget.issuedAt!),
                    style: PulseType.telemetry(9.5).copyWith(
                      color: widget.accentColor,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Desktop / no-sensor path: a slow elliptical drift reads as "hand-held".
  Offset _autonomousTilt() {
    final t = _controller.value * 2 * math.pi;
    return Offset(0.55 * math.cos(t), 0.45 * math.sin(t * 0.7));
  }

  String _fmtDate(DateTime d) {
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')} ${d.year}';
  }

  Widget _fallback() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.accentColor.withValues(alpha: 0.4)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            widget.accentColor.withValues(alpha: 0.45),
            PulsePalette.elevatedSurface,
            widget.accentColor.withValues(alpha: 0.2),
          ],
        ),
      ),
    );
  }
}

class _FoilBadgePainter extends CustomPainter {
  _FoilBadgePainter({
    required this.shader,
    required this.time,
    required this.tilt,
    required this.accentColor,
  });

  final ui.FragmentShader shader;
  final double time;
  final Offset tilt;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, tilt.dx)
      ..setFloat(4, tilt.dy)
      ..setFloat(5, accentColor.r)
      ..setFloat(6, accentColor.g)
      ..setFloat(7, accentColor.b)
      ..setFloat(8, 1.0);

    final paint = Paint()..shader = shader;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FoilBadgePainter old) =>
      old.time != time || old.tilt != tilt || old.accentColor != accentColor;
}
