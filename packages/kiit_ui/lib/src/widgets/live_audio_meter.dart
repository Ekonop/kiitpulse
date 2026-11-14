import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../pulse_palette.dart';

/// Animated level meter for live voice.
///
/// [level] is a normalised 0..1 amplitude. When [active] is false the bars
/// settle to a flat idle line instead of freezing mid-air, which is what makes
/// a muted speaker read as muted rather than broken.
class LiveAudioMeter extends StatefulWidget {
  const LiveAudioMeter({
    super.key,
    required this.active,
    this.level = 0.6,
    this.barCount = 3,
    this.color = PulsePalette.coralStage,
    this.height = 14,
  });

  final bool active;
  final double level;
  final int barCount;
  final Color color;
  final double height;

  @override
  State<LiveAudioMeter> createState() => _LiveAudioMeterState();
}

class _LiveAudioMeterState extends State<LiveAudioMeter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant LiveAudioMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(widget.barCount, (i) {
            final phase = i * 1.7;
            final wobble =
                0.5 + 0.5 * math.sin(_c.value * math.pi * 2 + phase);
            final scale = widget.active
                ? (0.35 + wobble * 0.65) * widget.level.clamp(0.1, 1.0)
                : 0.18;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.2),
              child: Container(
                width: 2.6,
                height: widget.height * scale.clamp(0.12, 1.0),
                decoration: BoxDecoration(
                  color: widget.color
                      .withValues(alpha: widget.active ? 1.0 : 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
