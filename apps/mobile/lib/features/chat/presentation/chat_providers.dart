import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_api_client/kiit_api_client.dart';
import 'package:kiit_contracts/kiit_contracts.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/providers.dart';

/// Messages for one topic room, with optimistic sends reconciled in place.
///
/// Ordering contract: the list is chronological (oldest first). The view
/// reverses it. Keeping the source list in time order means an optimistic
/// message never jumps after an ack.
class TopicChatController extends StateNotifier<AsyncValue<List<EphemeralMessage>>> {
  TopicChatController(this._ref, this.topicId) : super(const AsyncValue.loading()) {
    _boot();
  }

  final Ref _ref;
  final String topicId;
  StreamSubscription<EphemeralMessage>? _sub;
  StreamSubscription<SocketStatus>? _statusSub;

  /// Transport state, surfaced so the room can be honest about a dead socket.
  SocketStatus get connectionState => _connection;

  SocketStatus _connection = SocketStatus.open;

  Future<void> _boot() async {
    final gateway = _ref.read(pulseGatewayProvider);

    // Subscribe *before* awaiting history, and independently of whether the
    // history fetch succeeds. A failure to load the last 50 messages must not
    // also mean the room never receives live ones - that turned a transient
    // 503 into a permanently silent chat.
    _sub = gateway.watchMessages(topicId).listen(
      _onIncoming,
      onError: (Object _) {},
    );

    _statusSub = gateway.watchSocketStatus(topicId).listen((s) {
      if (!mounted) return;
      _connection = s;
      // Bump listeners without disturbing the message list.
      state = AsyncValue.data(state.valueOrNull ?? const <EphemeralMessage>[]);
    });

    try {
      final history = await gateway.fetchRecentMessages(topicId);
      if (!mounted) return;
      // Merge rather than replace: a live message that arrived while the
      // history request was in flight would otherwise be wiped out.
      final current = state.valueOrNull ?? const <EphemeralMessage>[];
      final known = {for (final m in current) m.id};
      final merged = [
        ...history.where((m) => !known.contains(m.id)),
        ...current,
      ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      state = AsyncValue.data(merged);
    } catch (e, st) {
      if (!mounted) return;
      // Only show the error state if we have nothing to show.
      if (state.valueOrNull == null) state = AsyncValue.error(e, st);
    }
  }

  void _onIncoming(EphemeralMessage incoming) {
    if (!mounted) return;
    final current = state.valueOrNull ?? const <EphemeralMessage>[];

    // Reconcile: if this is the ack for our optimistic copy, replace it in
    // place instead of appending a duplicate.
    //
    // Prefer the echoed client id, which is exact. The sender+content fallback
    // stays for older hubs that do not echo it, but on its own it cross-wires
    // two identical messages from the same student.
    final echoId = incoming.clientId;
    final pendingIndex = echoId == null
        ? current.indexWhere(
            (m) =>
                m.status == MessageStatus.sending &&
                m.senderRoll == incoming.senderRoll &&
                m.content == incoming.content,
          )
        : current.indexWhere((m) => m.id == echoId);
    if (pendingIndex != -1) {
      final next = [...current];
      next[pendingIndex] = incoming.copyWith(status: MessageStatus.sent);
      state = AsyncValue.data(next);
      return;
    }

    if (current.any((m) => m.id == incoming.id)) return;
    state = AsyncValue.data([...current, incoming]);
  }

  /// Render immediately, send in the background. Returns the local id so the
  /// UI can highlight the message while it is in flight.
  Future<void> send(String text) async {
    final body = text.trim();
    if (body.isEmpty) return;

    final session = _ref.read(currentSessionProvider);
    if (session == null) return;

    final gateway = _ref.read(pulseGatewayProvider);
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = EphemeralMessage(
      id: localId,
      topicId: topicId,
      senderRoll: session.rollNumber,
      senderBranchTag: session.branchTag,
      content: body,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      clientId: localId,
    );

    final current = state.valueOrNull ?? const <EphemeralMessage>[];
    state = AsyncValue.data([...current, optimistic]);

    try {
      final acked = await gateway.sendMessage(
        topicId: topicId,
        content: body,
      );
      if (!mounted) return;
      final list = state.valueOrNull ?? const <EphemeralMessage>[];
      final idx = list.indexWhere((m) => m.id == localId);
      if (idx == -1) return;
      final next = [...list];
      // The demo gateway returns the real message; the live gateway returns the
      // optimistic copy and the real one arrives over the socket. Handle both.
      next[idx] = acked.id == localId
          ? acked
          : acked.copyWith(status: MessageStatus.sent);
      state = AsyncValue.data(next);
    } catch (_) {
      if (!mounted) return;
      final list = state.valueOrNull ?? const <EphemeralMessage>[];
      final idx = list.indexWhere((m) => m.id == localId);
      if (idx == -1) return;
      final next = [...list];
      next[idx] = next[idx].copyWith(status: MessageStatus.failed);
      state = AsyncValue.data(next);
    }
  }

  /// Retry a message that failed to send.
  ///
  /// Drops the failed copy and re-sends its body, so the user gets exactly one
  /// visible message rather than a ghost next to its replacement.
  Future<void> retry(String messageId) async {
    final list = state.valueOrNull ?? const <EphemeralMessage>[];
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    final failed = list[idx];
    if (failed.status != MessageStatus.failed) return;

    final next = [...list]..removeAt(idx);
    state = AsyncValue.data(next);
    await send(failed.content);
  }

  Future<void> react(String messageId, String emoji) async {
    final gateway = _ref.read(pulseGatewayProvider);
    // Optimistic reaction count.
    final list = state.valueOrNull ?? const <EphemeralMessage>[];
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final next = [...list];
      final reactions = {...next[idx].reactions};
      reactions[emoji] = (reactions[emoji] ?? 0) + 1;
      next[idx] = next[idx].copyWith(reactions: reactions);
      state = AsyncValue.data(next);
    }
    try {
      await gateway.sendReaction(
        topicId: topicId,
        messageId: messageId,
        emoji: emoji,
      );
    } catch (_) {
      // A reaction is not worth an error dialog; drop it silently.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}

final topicChatProvider = StateNotifierProvider.autoDispose
    .family<TopicChatController, AsyncValue<List<EphemeralMessage>>, String>(
  (ref, topicId) {
    return TopicChatController(ref, topicId);
  },
);
