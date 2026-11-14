import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiit_ui/kiit_ui.dart';

import '../../../../core/auth/auth_controller.dart';

/// One message in the ephemeral stream.
///
/// Three visual states that matter:
///   * mine      - emerald tinted, right aligned, no avatar (identity is known)
///   * theirs    - surface shell, left aligned, roll + programme tag header
///   * in flight - reduced opacity + a sending tick, replaced in place on ack
///
/// Reactions are deliberately small: this is a campus corridor, not a social
/// feed, and a wall of emoji would drown the actual exam question.
class MessageBubble extends ConsumerStatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.onReact,
    required this.onRetry,
    this.animateIn = false,
  });

  final EphemeralMessage message;
  final void Function(String emoji) onReact;

  /// Re-send a message that failed to deliver.
  final VoidCallback onRetry;

  /// Plays a rise-and-fade once. Only the newest message animates so a scroll
  /// back through history never re-triggers motion.
  final bool animateIn;

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: PulseMotion.base,
    value: widget.animateIn ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animateIn) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);
    final isMine = session != null &&
        widget.message.senderRoll == session.rollNumber;
    final m = widget.message;
    final failed = m.status == MessageStatus.failed;
    final sending = m.status == MessageStatus.sending;

    final bubble = Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMine) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                m.senderRoll,
                style: PulseType.telemetry(9.5).copyWith(
                  color: PulsePalette.textTertiary,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                m.senderBranchTag,
                style: PulseType.body(9.5).copyWith(
                  color: PulsePalette.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (sending)
              const Padding(
                padding: EdgeInsets.only(right: 5, bottom: 3),
                child: SizedBox(
                  width: 9,
                  height: 9,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: PulsePalette.textTertiary,
                  ),
                ),
              ),
            Flexible(
              child: GestureDetector(
                // Long press is the reaction affordance: no permanent clutter.
                onLongPress: () => _showReactionPicker(context),
                child: Opacity(
                  opacity: sending ? 0.66 : 1,
                  child: _BubbleShell(
                    isMine: isMine,
                    failed: failed,
                    child: Text(
                      m.content,
                      style: PulseType.body(13.5).copyWith(
                        color: isMine
                            ? PulsePalette.textPrimary
                            : PulsePalette.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (m.reactions.isNotEmpty) ...[
          const SizedBox(height: 5),
          Wrap(
            spacing: 5,
            children: [
              for (final entry in m.reactions.entries)
                _ReactionChip(emoji: entry.key, count: entry.value),
            ],
          ),
        ],
        if (failed) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: widget.onRetry,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.refresh_rounded,
                  size: 11,
                  color: PulsePalette.coralStage,
                ),
                const SizedBox(width: 3),
                Text(
                  'Not delivered - tap to retry',
                  style: PulseType.body(9.5)
                      .copyWith(color: PulsePalette.coralStage),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (!widget.animateIn) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: bubble,
      );
    }

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - t)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: bubble,
        ),
      ),
    );
  }

  Future<void> _showReactionPicker(BuildContext context) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PulsePalette.elevatedSurface,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final e in const ['👍', '🔥', '😂', '❓', '👀'])
              _PickerEmoji(emoji: e, onTap: () => Navigator.of(context).pop(e)),
          ],
        ),
      ),
    );
    if (emoji != null) widget.onReact(emoji);
  }
}

class _PickerEmoji extends StatelessWidget {
  const _PickerEmoji({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.85, end: 1),
        duration: PulseMotion.base,
        curve: PulseMotion.emphasis,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Text(emoji, style: const TextStyle(fontSize: 26)),
      ),
    );
  }
}

class _BubbleShell extends StatelessWidget {
  const _BubbleShell({
    required this.child,
    required this.isMine,
    required this.failed,
  });

  final Widget child;
  final bool isMine;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isMine
            ? PulsePalette.kiitEmerald.withValues(alpha: 0.13)
            : PulsePalette.elevatedSurface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(13),
          topRight: const Radius.circular(13),
          bottomLeft: Radius.circular(isMine ? 13 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 13),
        ),
        border: Border.all(
          color: failed
              ? PulsePalette.coralStage.withValues(alpha: 0.5)
              : isMine
                  ? PulsePalette.kiitEmerald.withValues(alpha: 0.3)
                  : PulsePalette.borderGrey,
        ),
      ),
      child: child,
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.emoji, required this.count});

  final String emoji;
  final int count;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: PulseMotion.base,
      curve: PulseMotion.emphasis,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: PulsePalette.deepObsidian,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: PulsePalette.borderGrey),
        ),
        child: Text(
          '$emoji $count',
          style: PulseType.telemetry(9.5)
              .copyWith(color: PulsePalette.textSecondary),
        ),
      ),
    );
  }
}
