import 'package:flutter/material.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiit_ui/kiit_ui.dart';

/// One trending node on the radar.
///
/// Two shapes, one widget: a standard academic card (fixed [height] of 128) and
/// a live voice card (210), which adds a stage strip with speaker/listener
/// telemetry. The voice shape is signalled three ways - rail colour, border,
/// and the presence of the stage strip - so it survives a greyscale screenshot.
class TopicPulseCard extends StatelessWidget {
  const TopicPulseCard({
    super.key,
    required this.topic,
    required this.height,
    required this.onOpen,
  });

  final TopicPulse topic;
  final double height;
  final VoidCallback onOpen;

  bool get _live => topic.hasActiveVoiceStage;

  @override
  Widget build(BuildContext context) {
    final accent = _live ? PulsePalette.coralStage : PulsePalette.kiitEmerald;

    return SizedBox(
      height: height,
      child: PulseSurface(
        accent: _live ? accent : null,
        live: _live,
        padding: EdgeInsets.zero,
        onTap: onOpen,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Velocity rail: length encodes score, so the list is scannable
            // without reading a single number.
            _VelocityRail(score: topic.velocityScore, tint: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TitleRow(topic: topic, live: _live),
                    const SizedBox(height: 7),
                    Expanded(
                      child: Text(
                        topic.description,
                        maxLines: _live ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: PulseType.body(12.5).copyWith(
                          color: PulsePalette.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_live)
                      _LiveStageStrip(topic: topic)
                    else
                      _QuietFooter(topic: topic),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VelocityRail extends StatelessWidget {
  const _VelocityRail({required this.score, required this.tint});

  final double score;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    // 260 is roughly the score at which a topic is "surging"; beyond that the
    // rail is full. Relative rather than absolute so the rail stays useful.
    final fraction = (score / 260).clamp(0.04, 1.0);
    return SizedBox(
      width: 34,
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          children: [
            SizedBox(
              height: 46,
              child: RotatedBox(
                quarterTurns: 3,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 3,
                    width: 34 * fraction,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 6),
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(
                  score >= 100
                      ? score.toStringAsFixed(0)
                      : score.toStringAsFixed(1),
                  style: PulseType.telemetry(10).copyWith(
                    color: tint.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.topic, required this.live});

  final TopicPulse topic;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            '#${topic.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PulseType.display(15).copyWith(
              color: PulsePalette.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (live)
          _LiveBadge(zone: topic.zone)
        else if (topic.tag != null)
          _TagChip(label: topic.tag!)
        else
          VelocityBadge(score: topic.velocityScore, compact: true),
      ],
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.zone});

  final CampusZone zone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: PulsePalette.coralAlpha(0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: PulsePalette.coralAlpha(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LiveAudioMeter(active: true, barCount: 3, height: 10),
          const SizedBox(width: 5),
          Text(
            'VOICE',
            style: PulseType.telemetry(8.5).copyWith(
              color: PulsePalette.coralStage,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: PulsePalette.deepObsidian,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: PulsePalette.borderGrey),
      ),
      child: Text(
        label,
        style: PulseType.telemetry(8.5).copyWith(
          color: PulsePalette.textTertiary,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _LiveStageStrip extends StatelessWidget {
  const _LiveStageStrip({required this.topic});

  final TopicPulse topic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: PulsePalette.coralAlpha(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PulsePalette.coralAlpha(0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq_rounded,
              size: 13, color: PulsePalette.coralStage),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${topic.activeSpeakers} speaking · '
              '${topic.activeListeners} listening',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PulseType.body(11.5, weight: FontWeight.w600).copyWith(
                color: PulsePalette.coralStage,
              ),
            ),
          ),
          VelocityBadge(score: topic.velocityScore, compact: true),
        ],
      ),
    );
  }
}

class _QuietFooter extends StatelessWidget {
  const _QuietFooter({required this.topic});

  final TopicPulse topic;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.chat_bubble_outline_rounded,
            size: 12, color: PulsePalette.textTertiary),
        const SizedBox(width: 5),
        Text(
          '${topic.messageCount}',
          style: PulseType.telemetry(10).copyWith(
            color: PulsePalette.textTertiary,
          ),
        ),
        const SizedBox(width: 12),
        Icon(Icons.place_outlined, size: 12, color: PulsePalette.textTertiary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            topic.zone.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PulseType.body(10.5).copyWith(
              color: PulsePalette.textTertiary,
            ),
          ),
        ),
        const Spacer(),
        Text(
          velocityLabel(topic.velocityScore),
          style: PulseType.telemetry(9).copyWith(
            color: topic.isHot
                ? PulsePalette.kiitEmerald
                : PulsePalette.textTertiary,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}
