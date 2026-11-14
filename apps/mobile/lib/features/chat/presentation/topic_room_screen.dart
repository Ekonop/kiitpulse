import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_api_client/kiit_api_client.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiit_ui/kiit_ui.dart';

import '../../voice_room/presentation/pinned_voice_banner.dart';
import '../../voice_room/presentation/voice_providers.dart';
import '../../voice_room/presentation/voice_stage_sheet.dart';
import '../../../core/providers.dart';
import 'chat_providers.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_composer.dart';

/// Topic Hub - the engagement loop.
///
/// One screen, two planes: a retractable live voice banner pinned to the top
/// and the message stream below. The banner is never a modal - a student can
/// read chat while listening, and tapping it expands the full stage.
class TopicRoomScreen extends ConsumerStatefulWidget {
  const TopicRoomScreen({super.key, required this.topic});

  final TopicPulse topic;

  @override
  ConsumerState<TopicRoomScreen> createState() => _TopicRoomScreenState();
}

class _TopicRoomScreenState extends ConsumerState<TopicRoomScreen> {
  final _scroll = ScrollController();
  bool _bannerCollapsed = false;

  @override
  void initState() {
    super.initState();
    // Join the stage passively on entry if one is live: listening costs
    // nothing and is the retention loop.
    if (widget.topic.hasActiveVoiceStage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(voiceStageProvider(widget.topic.id).notifier)
            .joinAsListener(widget.topic.id);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(topicChatProvider(widget.topic.id));
    final stage = ref.watch(voiceStageProvider(widget.topic.id));
    final hasStage = widget.topic.hasActiveVoiceStage || stage.isConnected;

    return Scaffold(
      appBar: _RoomAppBar(topic: widget.topic),
      body: Column(
        children: [
          // Honest transport state. A room whose socket is down must not look
          // identical to a quiet one, or students keep typing into a void.
          _ReconnectBanner(topicId: widget.topic.id),
          if (hasStage)
            PinnedVoiceBanner(
              topic: widget.topic,
              collapsed: _bannerCollapsed,
              onToggleCollapsed: () =>
                  setState(() => _bannerCollapsed = !_bannerCollapsed),
              onExpand: () => showVoiceStageSheet(context, widget.topic),
            ),
          Expanded(
            child: chat.when(
              loading: () => const _ChatLoading(),
              error: (error, _) => _ChatError(
                error: error,
                onRetry: () =>
                    ref.invalidate(topicChatProvider(widget.topic.id)),
              ),
              data: (messages) {
                if (messages.isEmpty) return const _EmptyChat();
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    // reverse: true means index 0 is the newest message.
                    final message = messages[messages.length - 1 - index];
                    final isNewest = index == 0;
                    return MessageBubble(
                      key: ValueKey(message.id),
                      message: message,
                      animateIn: isNewest,
                      onReact: (emoji) => ref
                          .read(topicChatProvider(widget.topic.id).notifier)
                          .react(message.id, emoji),
                      onRetry: () => ref
                          .read(topicChatProvider(widget.topic.id).notifier)
                          .retry(message.id),
                    );
                  },
                );
              },
            ),
          ),
          MessageComposer(
            topicTitle: widget.topic.title,
            onSend: (text) => ref
                .read(topicChatProvider(widget.topic.id).notifier)
                .send(text),
          ),
        ],
      ),
    );
  }
}

class _RoomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _RoomAppBar({required this.topic});

  final TopicPulse topic;

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: PulsePalette.deepObsidian,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  '#${topic.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PulseType.display(15.5).copyWith(
                    color: PulsePalette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              VelocityBadge(score: topic.velocityScore, compact: true),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${topic.zone.label} · disappears 24h after the last reply',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PulseType.body(10.5).copyWith(
              color: PulsePalette.textTertiary,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Ephemeral room info',
          icon: const Icon(Icons.timer_outlined, size: 19),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'This room is ephemeral. Messages are not searchable and '
                  'vanish 24 hours after the last reply.',
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _ChatLoading extends StatelessWidget {
  const _ChatLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      reverse: true,
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisAlignment:
                  i.isEven ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                ShimmerBox(width: 120 + (i * 37).toDouble(), height: 34, radius: 10),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined,
                size: 30, color: PulsePalette.textTertiary),
            const SizedBox(height: 14),
            Text(
              'Nobody has said anything yet',
              style: PulseType.display(15)
                  .copyWith(color: PulsePalette.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'Say the first thing. This room clears itself once it goes cold.',
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

class _ChatError extends StatelessWidget {
  const _ChatError({required this.error, required this.onRetry});

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
            Text(
              'Could not load this room',
              style: PulseType.display(15)
                  .copyWith(color: PulsePalette.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: PulseType.body(12)
                  .copyWith(color: PulsePalette.textTertiary),
            ),
            const SizedBox(height: 16),
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

/// A slim strip shown while the room's socket is down or retrying.
///
/// Deliberately quiet: this is ambient truth, not an error dialog. It appears
/// only for a transport state the gateway actually reports, so the demo gateway
/// (which has no transport) never shows it.
class _ReconnectBanner extends ConsumerStatefulWidget {
  const _ReconnectBanner({required this.topicId});

  final String topicId;

  @override
  ConsumerState<_ReconnectBanner> createState() => _ReconnectBannerState();
}

class _ReconnectBannerState extends ConsumerState<_ReconnectBanner> {
  StreamSubscription<SocketStatus>? _statusSub;
  SocketStatus _state = SocketStatus.open;

  @override
  void initState() {
    super.initState();
    // Subscribe to the gateway's transport stream directly rather than trying
    // to observe the controller: the controller only rebuilds on message
    // changes, so a socket that dies in a quiet room would go unnoticed.
    _statusSub = ref
        .read(pulseGatewayProvider)
        .watchSocketStatus(widget.topicId)
        .listen((s) {
      if (mounted && s != _state) setState(() => _state = s);
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final down = _state == SocketStatus.disconnected ||
        _state == SocketStatus.connecting;

    return AnimatedSize(
      duration: PulseMotion.fast,
      curve: PulseMotion.soft,
      alignment: Alignment.topCenter,
      child: !down
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              color: PulsePalette.amberWarn.withValues(alpha: 0.12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.4,
                      valueColor: AlwaysStoppedAnimation(
                        PulsePalette.amberWarn.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Reconnecting \u2014 messages will send once you are back',
                    style: PulseType.body(10).copyWith(
                      color: PulsePalette.amberWarn,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
