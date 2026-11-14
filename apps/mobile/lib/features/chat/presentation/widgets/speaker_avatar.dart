import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiit_ui/kiit_ui.dart';

/// Avatar for someone on a voice stage.
///
/// The speaking ring is the whole point: it expands and brightens only while
/// that participant is talking. A muted speaker shows a dim, static ring so a
/// silent line is visibly silent rather than ambiguous.
class SpeakerAvatar extends StatefulWidget {
  const SpeakerAvatar({
    super.key,
    required this.participant,
    required this.speaking,
    this.size = 48,
    this.showLabel = false,
  });

  final VoiceParticipant participant;
  final bool speaking;
  final double size;
  final bool showLabel;

  @override
  State<SpeakerAvatar> createState() => _SpeakerAvatarState();
}

class _SpeakerAvatarState extends State<SpeakerAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.speaking) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant SpeakerAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.speaking && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.speaking && _c.isAnimating) {
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
    final p = widget.participant;
    final isModerator = p.role == StageRole.moderator;
    final tint = isModerator ? PulsePalette.kiitEmerald : PulsePalette.coralStage;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final pulse = widget.speaking
                ? 0.5 + 0.5 * math.sin(_c.value * math.pi * 2)
                : 0.0;
            return SizedBox(
              width: widget.size + 12,
              height: widget.size + 12,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (widget.speaking)
                    Container(
                      width: widget.size + 6 + pulse * 6,
                      height: widget.size + 6 + pulse * 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: tint.withValues(alpha: 0.25 + 0.35 * pulse),
                          width: 1.5,
                        ),
                      ),
                    ),
                  Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.isMuted
                          ? PulsePalette.raisedSurface
                          : tint.withValues(alpha: 0.16),
                      border: Border.all(
                        color: p.isMuted
                            ? PulsePalette.borderGrey
                            : tint.withValues(alpha: 0.6),
                        width: 1.2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      p.initials,
                      style: PulseType.telemetry(
                        widget.size * 0.29,
                      ).copyWith(
                        color:
                            p.isMuted ? PulsePalette.textTertiary : tint,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  if (p.isMuted)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: const BoxDecoration(
                          color: PulsePalette.deepObsidian,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.mic_off_rounded,
                          size: 9,
                          color: PulsePalette.textTertiary,
                        ),
                      ),
                    ),
                  if (isModerator)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: const BoxDecoration(
                          color: PulsePalette.deepObsidian,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          size: 9,
                          color: PulsePalette.kiitEmerald,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        if (widget.showLabel) ...[
          const SizedBox(height: 4),
          SizedBox(
            width: widget.size + 16,
            child: Text(
              p.displayRoll,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: PulseType.telemetry(8.5).copyWith(
                color: PulsePalette.textTertiary,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
