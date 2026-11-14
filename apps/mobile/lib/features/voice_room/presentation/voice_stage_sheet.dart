import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiit_ui/kiit_ui.dart';

import '../../chat/presentation/widgets/speaker_avatar.dart';
import 'voice_providers.dart';

/// Opens the expanded voice stage as a draggable sheet.
Future<void> showVoiceStageSheet(BuildContext context, TopicPulse topic) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => VoiceStageSheet(topic: topic),
  );
}

/// Full-screen voice stage.
///
/// Layout follows the hierarchy of the conversation, not a grid of equals:
/// moderators and speakers sit in a prominent cluster at the top, the hand
/// queue sits below them in a distinct zone, and listeners are summarised as a
/// count rather than 60 identical circles. That is what keeps a 100-person
/// huddle readable.
class VoiceStageSheet extends ConsumerWidget {
  const VoiceStageSheet({super.key, required this.topic});

  final TopicPulse topic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = ref.watch(voiceStageProvider(topic.id));
    final controller = ref.read(voiceStageProvider(topic.id).notifier);
    final speakers = stage.speakers;
    final queue = stage.handRaised;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: PulsePalette.elevatedSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(
              top: BorderSide(color: PulsePalette.borderGreyStrong),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 3.5,
                decoration: BoxDecoration(
                  color: PulsePalette.borderGreyStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  children: [
                    _StageHeader(topic: topic, stage: stage),
                    const SizedBox(height: 26),

                    if (speakers.isNotEmpty) ...[
                      _SectionLabel(
                        label: 'ON STAGE',
                        count: speakers.length,
                        tint: PulsePalette.coralStage,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 16,
                        runSpacing: 18,
                        children: [
                          for (final p in speakers)
                            FadeSlideIn(
                              child: SpeakerAvatar(
                                participant: p,
                                speaking:
                                    p.identity == stage.activeSpeakerId &&
                                        !p.isMuted,
                                size: 58,
                                showLabel: true,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 26),
                    ],

                    if (queue.isNotEmpty) ...[
                      _SectionLabel(
                        label: 'WAITING TO SPEAK',
                        count: queue.length,
                        tint: PulsePalette.amberWarn,
                      ),
                      const SizedBox(height: 12),
                      for (final p in queue)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: _QueueRow(participant: p),
                        ),
                      const SizedBox(height: 18),
                    ],

                    _ListenersSummary(count: stage.listenerCount),
                  ],
                ),
              ),
              _StageControls(stage: stage, controller: controller),
            ],
          ),
        );
      },
    );
  }
}

class _StageHeader extends StatelessWidget {
  const _StageHeader({required this.topic, required this.stage});

  final TopicPulse topic;
  final VoiceStageState stage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const LiveAudioMeter(active: true, height: 16, barCount: 4),
            const SizedBox(width: 9),
            Text(
              'LIVE HUDDLE',
              style: PulseType.telemetry(10).copyWith(
                color: PulsePalette.coralStage,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          '#${topic.title}',
          style: PulseType.display(21)
              .copyWith(color: PulsePalette.textPrimary),
        ),
        const SizedBox(height: 5),
        Text(
          topic.zone.label,
          style: PulseType.body(12.5)
              .copyWith(color: PulsePalette.textTertiary),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.count,
    required this.tint,
  });

  final String label;
  final int count;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: PulseType.telemetry(9.5).copyWith(
            color: tint,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(width: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$count',
            style: PulseType.telemetry(9)
                .copyWith(color: tint, letterSpacing: 0),
          ),
        ),
      ],
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.participant});

  final VoiceParticipant participant;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: PulsePalette.deepObsidian,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: PulsePalette.borderGrey),
      ),
      child: Row(
        children: [
          const Icon(Icons.front_hand_rounded,
              size: 13, color: PulsePalette.amberWarn),
          const SizedBox(width: 9),
          Text(
            participant.displayRoll,
            style: PulseType.telemetry(10.5)
                .copyWith(color: PulsePalette.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              participant.branchTag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PulseType.body(10.5)
                  .copyWith(color: PulsePalette.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListenersSummary extends StatelessWidget {
  const _ListenersSummary({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: PulsePalette.deepObsidian.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PulsePalette.borderGrey),
      ),
      child: Row(
        children: [
          const Icon(Icons.headphones_rounded,
              size: 14, color: PulsePalette.textTertiary),
          const SizedBox(width: 9),
          Text(
            '$count listening',
            style: PulseType.body(12)
                .copyWith(color: PulsePalette.textSecondary),
          ),
          const Spacer(),
          Text(
            'LISTEN-ONLY',
            style: PulseType.telemetry(8.5).copyWith(
              color: PulsePalette.textTertiary,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageControls extends StatelessWidget {
  const _StageControls({required this.stage, required this.controller});

  final VoiceStageState stage;
  final VoiceStageController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: PulsePalette.borderGrey)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (stage.role == StageRole.speaker)
              _ControlButton(
                icon: stage.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                label: stage.isMuted ? 'Unmute' : 'Mute',
                tint: stage.isMuted
                    ? PulsePalette.coralStage
                    : PulsePalette.kiitEmerald,
                active: !stage.isMuted,
                onTap: controller.toggleMic,
              )
            else
              _ControlButton(
                icon: stage.role == StageRole.handRaised
                    ? Icons.front_hand_rounded
                    : Icons.back_hand_outlined,
                label: stage.role == StageRole.handRaised ? 'Lower' : 'Raise',
                tint: PulsePalette.amberWarn,
                active: stage.role == StageRole.handRaised,
                onTap: controller.toggleHand,
              ),
            _ControlButton(
              icon: Icons.volume_up_rounded,
              label: 'Speaker',
              tint: PulsePalette.textSecondary,
              active: false,
              onTap: () {},
            ),
            _ControlButton(
              icon: Icons.call_end_rounded,
              label: 'Leave',
              tint: PulsePalette.coralStage,
              active: false,
              filled: true,
              onTap: () async {
                await controller.leave();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.tint,
    required this.active,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final bool active;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scale: 0.92,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: PulseMotion.base,
            curve: PulseMotion.enter,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: filled
                  ? tint.withValues(alpha: 0.18)
                  : active
                      ? tint.withValues(alpha: 0.16)
                      : PulsePalette.deepObsidian,
              shape: BoxShape.circle,
              border: Border.all(
                color: filled || active
                    ? tint.withValues(alpha: 0.45)
                    : PulsePalette.borderGrey,
              ),
            ),
            child: Icon(icon, size: 20, color: tint),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: PulseType.body(10.5).copyWith(
              color: PulsePalette.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}