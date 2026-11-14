import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiit_ui/kiit_ui.dart';

import '../../../core/providers.dart';
import '../../../core/zone/zone_selection.dart';
import '../../chat/presentation/topic_room_screen.dart';
import 'radar_providers.dart';
import 'widgets/radar_header.dart';
import 'widgets/topic_pulse_card.dart';
import 'widgets/zone_selector.dart';

/// Radar Home - the discovery loop.
///
/// Fixed card extents keep the scroll cheap: standard discussion cards are
/// 128 tall, live voice cards 210, so the list never has to measure children.
/// A `ListView.separated` with fixed separator height reproduces the effect of
/// the blueprint's `itemExtentBuilder` on the stable channel.
class RadarScreen extends ConsumerWidget {
  const RadarScreen({super.key});

  static const double standardCardHeight = 128;
  static const double voiceCardHeight = 210;
  static const double cardGap = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radar = ref.watch(radarProvider);
    final selection = ref.watch(zoneSelectionProvider);
    final population = ref.watch(zonePopulationProvider);
    final proximity = ref.watch(proximityProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RadarHeader(
              selection: selection,
              population: population.valueOrNull,
              proximity: proximity,
            ),
            const ZoneSelector(),
            const SizedBox(height: 6),
            Expanded(
              child: AnimatedSwitcher(
                duration: PulseMotion.base,
                switchInCurve: PulseMotion.enter,
                switchOutCurve: PulseMotion.exit,
                child: KeyedSubtree(
                  key: ValueKey(radar.hasValue
                      ? 'data-${radar.valueOrNull?.length}'
                      : radar.hasError
                          ? 'error'
                          : 'loading'),
                  child: _body(ref, radar, selection),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openComposer(context, ref, selection),
        backgroundColor: PulsePalette.kiitEmerald,
        foregroundColor: const Color(0xFF00160A),
        icon: const _SpinOnPress(),
        label: Text(
          'Start a pulse',
          style: PulseType.body(13.5, weight: FontWeight.w600)
              .copyWith(color: const Color(0xFF00160A)),
        ),
      ),
    );
  }

  Widget _body(
    WidgetRef ref,
    AsyncValue<List<TopicPulse>> radar,
    ZoneSelection selection,
  ) {
    return radar.when(
        loading: () => const _RadarSkeleton(),
        error: (error, _) => _RadarError(
          error: error,
          onRetry: () => ref.invalidate(radarProvider),
        ),
        data: (topics) {
          if (topics.isEmpty) {
            return _EmptyRadar(zone: selection.label);
          }
          return RefreshIndicator(
            color: PulsePalette.kiitEmerald,
            backgroundColor: PulsePalette.elevatedSurface,
            onRefresh: () async {
              ref.invalidate(radarProvider);
              await ref.read(radarProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 96),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: topics.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: cardGap),
              itemBuilder: (context, index) {
                final topic = topics[index];
                return FadeSlideIn(
                  key: ValueKey(topic.id),
                  index: index,
                  child: TopicPulseCard(
                    topic: topic,
                    height: topic.hasActiveVoiceStage
                        ? voiceCardHeight
                        : standardCardHeight,
                    onOpen: () => _openTopic(context, topic),
                  ),
                );
              },
            ),
          );
        },
    );
  }

  void _openTopic(BuildContext context, TopicPulse topic) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TopicRoomScreen(topic: topic),
      ),
    );
  }

  Future<void> _openComposer(
    BuildContext context,
    WidgetRef ref,
    ZoneSelection selection,
  ) async {
    final draft = await showModalBottomSheet<_TopicDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _TopicComposer(),
    );
    if (draft == null) return;
    final gateway = ref.read(pulseGatewayProvider);
    try {
      await gateway.createTopic(
        title: draft.title,
        description: draft.description,
        zone: selection.effectiveZone,
      );
      ref.invalidate(radarProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start that pulse: $e')),
      );
    }
  }
}

class _TopicDraft {
  const _TopicDraft(this.title, this.description);

  final String title;
  final String description;
}

class _TopicComposer extends StatefulWidget {
  const _TopicComposer();

  @override
  State<_TopicComposer> createState() => _TopicComposerState();
}

class _TopicComposerState extends State<_TopicComposer> {
  final _title = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 4, 18, 18 + insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start a campus pulse',
            style: PulseType.display(19)
                .copyWith(color: PulsePalette.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'It lives for 24 hours after the last reply, then disappears.',
            style: PulseType.body(12.5)
                .copyWith(color: PulsePalette.textTertiary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: 48,
            textCapitalization: TextCapitalization.words,
            style: PulseType.body(14.5)
                .copyWith(color: PulsePalette.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Topic',
              hintText: 'DBMS-PYQ-Drop',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            maxLines: 3,
            maxLength: 180,
            style: PulseType.body(14.5)
                .copyWith(color: PulsePalette.textPrimary),
            decoration: const InputDecoration(
              labelText: 'What is happening',
              hintText: 'Papers from 2019-2024 with worked solutions.',
              counterText: '',
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () {
              final title = _title.text.trim();
              final body = _body.text.trim();
              if (title.isEmpty || body.isEmpty) return;
              Navigator.of(context).pop(_TopicDraft(title, body));
            },
            child: const Text('Put it on the radar'),
          ),
        ],
      ),
    );
  }
}

/// Rotates a quarter turn each time it is tapped, so the FAB acknowledges the
/// press even before the sheet opens.
class _SpinOnPress extends StatefulWidget {
  const _SpinOnPress();

  @override
  State<_SpinOnPress> createState() => _SpinOnPressState();
}

class _SpinOnPressState extends State<_SpinOnPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: PulseMotion.base,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _c.forward(from: 0),
      child: RotationTransition(
        turns: Tween<double>(begin: 0, end: 0.25).animate(
          CurvedAnimation(parent: _c, curve: PulseMotion.emphasis),
        ),
        child: const Icon(Icons.add_rounded, size: 20),
      ),
    );
  }
}

class _RadarSkeleton extends StatelessWidget {
  const _RadarSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 96),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _SkeletonCard(tall: i == 0),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.tall});

  final bool tall;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: tall ? 210 : 128,
      decoration: BoxDecoration(
        color: PulsePalette.elevatedSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PulsePalette.borderGrey),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerBox(width: 150, height: 12),
          const SizedBox(height: 12),
          const ShimmerBox(width: double.infinity, height: 10),
          const SizedBox(height: 7),
          const ShimmerBox(width: 210, height: 10),
          const Spacer(),
          const ShimmerBox(width: 120, height: 9),
        ],
      ),
    );
  }
}

class _RadarError extends StatelessWidget {
  const _RadarError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: PulsePalette.textTertiary, size: 34),
            const SizedBox(height: 14),
            Text(
              'Radar sync failed',
              style: PulseType.display(16)
                  .copyWith(color: PulsePalette.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: PulseType.body(12.5)
                  .copyWith(color: PulsePalette.textTertiary),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: PulsePalette.borderGreyStrong),
                foregroundColor: PulsePalette.textPrimary,
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRadar extends StatelessWidget {
  const _EmptyRadar({required this.zone});

  final String zone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: PulsePalette.borderGrey),
              ),
              child: const Icon(Icons.radar_rounded,
                  color: PulsePalette.textTertiary, size: 26),
            ),
            const SizedBox(height: 16),
            Text(
              'Quiet in $zone',
              style: PulseType.display(16)
                  .copyWith(color: PulsePalette.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'Nothing trending here right now. Start a pulse and it will '
              'surface for everyone within the geofence.',
              textAlign: TextAlign.center,
              style: PulseType.body(12.5)
                  .copyWith(color: PulsePalette.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
