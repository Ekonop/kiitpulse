import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiit_ui/kiit_ui.dart';

import '../../chat/presentation/widgets/speaker_avatar.dart';
import 'voice_providers.dart';

/// The pinned live voice banner above a topic's message stream.
///
/// Always present while a stage is live, never a modal. Collapsing it keeps the
/// controls (mic, leave) and hides the speaker row, so a student can read chat
/// on a small screen without losing audio context.
class PinnedVoiceBanner extends ConsumerWidget {
  const PinnedVoiceBanner({
    super.key,
    required this.topic,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onExpand,
  });

  final TopicPulse topic;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = ref.watch(voiceStageProvider(topic.id));
    final controller = ref.read(voiceStageProvider(topic.id).notifier);

    final speakers = stage.speakers;
    final speakingLabel = stage.role == StageRole.speaker
        ? (stage.isMuted ? 'Muted' : 'Speaking')
        : stage.role == StageRole.handRaised
            ? 'Hand raised'
            : 'Listening';

    return AnimatedSize(
      duration: PulseMotion.resolve(context, PulseMotion.base),
      curve: PulseMotion.soft,
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          color: PulsePalette.elevatedSurface,
          border: Border(
            bottom: BorderSide(
              color: PulsePalette.coralAlpha(0.25),
            ),
          ),
        ),
        child: Column(
          children: [
            // --- Top row: live dot, label, controls -------------------------
            InkWell(
              onTap: onExpand,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
                child: Row(
                  children: [
                    const _LiveDot(),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                'LIVE STAGE',
                                style: PulseType.telemetry(9.5).copyWith(
                                  color: PulsePalette.coralStage,
                                  letterSpacing: 1.3,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                '· $speakingLabel',
                                style: PulseType.body(10.5).copyWith(
                                  color: PulsePalette.textTertiary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${speakers.length} speaking · '
                            '${stage.listenerCount} listening',
                            style: PulseType.body(11.5).copyWith(
                              color: PulsePalette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (stage.role == StageRole.speaker)
                      _RoundAction(
                        icon: stage.isMuted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        tint: stage.isMuted
                            ? PulsePalette.coralStage
                            : PulsePalette.kiitEmerald,
                        onTap: controller.toggleMic,
                        tooltip: stage.isMuted ? 'Unmute' : 'Mute',
                      ),
                    _RoundAction(
                      icon: collapsed
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      tint: PulsePalette.textSecondary,
                      onTap: onToggleCollapsed,
                      tooltip: collapsed ? 'Show speakers' : 'Hide speakers',
                    ),
                    _RoundAction(
                      icon: Icons.call_end_rounded,
                      tint: PulsePalette.coralStage,
                      onTap: controller.leave,
                      tooltip: 'Leave stage',
                    ),
                  ],
                ),
              ),
            ),

            // --- Speaker row (collapsible) ---------------------------------
            AnimatedSize(
              duration: PulseMotion.resolve(context, PulseMotion.base),
              curve: PulseMotion.soft,
              alignment: Alignment.topCenter,
              child: collapsed
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 11),
                      child: Row(
                        children: [
                          Expanded(
                            // Sized to the avatar content instead of a magic
                            // height: 30px avatar + 12px ring inset + 4px gap +
                            // the mono label line. A hard-coded 54 overflowed by
                            // 2px as soon as the label used the telemetry font.
                            child: SizedBox(
                              height: 62,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: speakers.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, i) {
                                  final p = speakers[i];
                                  return SpeakerAvatar(
                                    participant: p,
                                    speaking:
                                        p.identity == stage.activeSpeakerId &&
                                            !p.isMuted,
                                    size: 30,
                                    showLabel: true,
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _HandRaiseButton(stage: stage, controller: controller),
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

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tint,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final Color tint;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onTap: onTap,
        scale: 0.9,
        child: Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: tint),
        ),
      ),
    );
  }
}

class _HandRaiseButton extends StatelessWidget {
  const _HandRaiseButton({required this.stage, required this.controller});

  final VoiceStageState stage;
  final VoiceStageController controller;

  @override
  Widget build(BuildContext context) {
    if (stage.role == StageRole.speaker) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: PulsePalette.kiitEmerald.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: PulsePalette.kiitEmerald.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          'ON STAGE',
          style: PulseType.telemetry(9).copyWith(
            color: PulsePalette.kiitEmerald,
            letterSpacing: 1.0,
          ),
        ),
      );
    }

    final raised = stage.role == StageRole.handRaised;
    return PressableScale(
      onTap: controller.toggleHand,
      scale: 0.94,
      child: AnimatedContainer(
        duration: PulseMotion.base,
        curve: PulseMotion.enter,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: raised
              ? PulsePalette.amberWarn.withValues(alpha: 0.16)
              : PulsePalette.deepObsidian,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: raised
                ? PulsePalette.amberWarn.withValues(alpha: 0.5)
                : PulsePalette.borderGrey,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              raised ? Icons.front_hand_rounded : Icons.back_hand_outlined,
              size: 13,
              color: raised ? PulsePalette.amberWarn : PulsePalette.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              raised ? 'HAND RAISED' : 'RAISE HAND',
              style: PulseType.telemetry(9).copyWith(
                color:
                    raised ? PulsePalette.amberWarn : PulsePalette.textSecondary,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The coral breathing dot that marks a live audio plane.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

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
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: PulsePalette.coralStage
                .withValues(alpha: 0.55 + 0.45 * _c.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: PulsePalette.coralStage.withValues(alpha: 0.3 * _c.value),
                blurRadius: 7,
                spreadRadius: 1.5,
              ),
            ],
          ),
        );
      },
    );
  }
}
