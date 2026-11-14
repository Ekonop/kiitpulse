import 'package:flutter/material.dart';

import '../pulse_palette.dart';
import '../pulse_typography.dart';

/// Monospaced telemetry readout for a topic's velocity score.
///
/// Shows the score with one decimal plus the unit. Colour encodes state:
/// emerald = hot, amber = decaying, tertiary = cold.
class VelocityBadge extends StatelessWidget {
  const VelocityBadge({
    super.key,
    required this.score,
    this.unit = 'P/M',
    this.compact = false,
  });

  final double score;
  final String unit;
  final bool compact;

  Color get _tint {
    if (score >= 80) return PulsePalette.kiitEmerald;
    if (score >= 20) return PulsePalette.amberWarn;
    return PulsePalette.textTertiary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: PulsePalette.deepObsidian,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _tint.withValues(alpha: 0.35)),
      ),
      child: Text(
        '${score.toStringAsFixed(1)} $unit',
        style: PulseType.telemetry(compact ? 10 : 11)
            .copyWith(color: _tint, fontWeight: FontWeight.w500),
      ),
    );
  }
}
