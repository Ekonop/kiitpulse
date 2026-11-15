import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiit_api_client/kiit_api_client.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiitpulse/core/auth/auth_controller.dart';
import 'package:kiitpulse/core/providers.dart';
import 'package:kiitpulse/features/chat/presentation/chat_providers.dart';

/// Regression tests for the chat controller.
///
/// These target the failure modes that are invisible in a happy-path widget
/// test: a dead socket in a quiet room, and a history request that fails while
/// the live stream is still perfectly healthy.

/// A gateway whose history always throws but whose live stream works.
///
/// This is the shape that used to produce a permanently silent room: `_boot`
/// awaited history, threw, and never subscribed.
class _HistoryFailsGateway implements PulseGateway {
  _HistoryFailsGateway();

  final _messages = StreamController<EphemeralMessage>.broadcast();
  final _status = StreamController<SocketStatus>.broadcast();
  int watchCalls = 0;
  int sendCalls = 0;
  bool failSend = false;

  void emit(EphemeralMessage m) => _messages.add(m);
  void emitStatus(SocketStatus s) => _status.add(s);

  @override
  Stream<EphemeralMessage> watchMessages(String topicId) {
    watchCalls++;
    return _messages.stream;
  }

  @override
  Stream<SocketStatus> watchSocketStatus(String topicId) => _status.stream;

  @override
  Future<List<EphemeralMessage>> fetchRecentMessages(
    String topicId, {
    int limit = 50,
  }) async {
    throw const GatewayException('history unavailable',
        code: 'UNAVAILABLE', retryable: true);
  }

  @override
  Future<EphemeralMessage> sendMessage({
    required String topicId,
    required String content,
  }) async {
    sendCalls++;
    if (failSend) throw const GatewayException('send failed');
    return EphemeralMessage(
      id: 'srv-\$sendCalls',
      topicId: topicId,
      senderRoll: '241551058',
      senderBranchTag: "CSE-AIML '28",
      content: content,
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
    );
  }

  // ---- not used by these tests -------------------------------------------
  @override
  Stream<List<TopicPulse>> watchRadar(CampusZone zone) => const Stream.empty();
  @override
  Future<List<TopicPulse>> fetchRadar(CampusZone zone) async => const [];
  @override
  Stream<int> watchZonePopulation(CampusZone zone) => const Stream.empty();
  @override
  Future<TopicPulse> createTopic({
    required String title,
    required String description,
    required CampusZone zone,
  }) async =>
      throw UnimplementedError();
  @override
  Future<void> sendReaction({
    required String topicId,
    required String messageId,
    required String emoji,
  }) async {}
  @override
  Future<StageToken> mintStageToken({
    required String topicId,
    required bool asSpeaker,
  }) async =>
      throw UnimplementedError();
  @override
  @override
  Future<void> joinStage(String topicId) async {}

  @override
  Future<void> leaveStage(String topicId) async {}

  @override
  Future<void> setHandRaised({
    required String topicId,
    required bool raised,
  }) async {}
  @override
  Stream<List<VoiceParticipant>> watchStage(String topicId) =>
      const Stream.empty();
  @override
  Future<List<FoilBadge>> fetchBadges(String studentRoll) async => const [];
  @override
  Future<Session> signIn(String email) async => throw UnimplementedError();
  @override
  void dispose() {}
}

EphemeralMessage _msg(String id, String body, {String roll = '241551204'}) {
  return EphemeralMessage(
    id: id,
    topicId: 't1',
    senderRoll: roll,
    senderBranchTag: "CSE-AIML '28",
    content: body,
    timestamp: DateTime.now(),
  );
}

void main() {
  test(
      'live messages still arrive when the history request fails '
      '(regression: room went permanently silent)', () async {
    final gateway = _HistoryFailsGateway();
    final container = ProviderContainer(
      overrides: [pulseGatewayProvider.overrideWithValue(gateway)],
    );
    addTearDown(container.dispose);

    // The provider is autoDispose, so something must hold a subscription or
    // the controller is torn down before it can boot.
    final keepAlive = container.listen(topicChatProvider('t1'), (_, __) {});
    addTearDown(keepAlive.close);

    // _boot awaits history; let it throw and settle.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(gateway.watchCalls, greaterThan(0),
        reason: 'the live stream must be subscribed even if history failed');

    gateway.emit(_msg('srv-1', 'live message after history error'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final state = container.read(topicChatProvider('t1'));
    final messages = state.valueOrNull ?? const <EphemeralMessage>[];
    expect(
      messages.map((m) => m.content),
      contains('live message after history error'),
      reason: 'a failed history fetch must not silence the room',
    );
  });

  test('reports gateway transport status', () async {
    final gateway = _HistoryFailsGateway();
    final container = ProviderContainer(
      overrides: [pulseGatewayProvider.overrideWithValue(gateway)],
    );
    addTearDown(container.dispose);

    final keepAlive = container.listen(topicChatProvider('t1'), (_, __) {});
    addTearDown(keepAlive.close);
    final notifier = container.read(topicChatProvider('t1').notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(notifier.connectionState, SocketStatus.open);

    gateway.emitStatus(SocketStatus.disconnected);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(notifier.connectionState, SocketStatus.disconnected,
        reason: 'the room needs to know the socket died');
  });

  test('a failed send is marked failed and retry re-sends it', () async {
    final gateway = _HistoryFailsGateway()..failSend = true;
    final container = ProviderContainer(
      overrides: [
        pulseGatewayProvider.overrideWithValue(gateway),
        currentSessionProvider.overrideWithValue(
          Session(
            email: '241551058@kiit.ac.in',
            rollNumber: '241551058',
            branchTag: "CSE-AIML '28",
            token: 'test-token',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final keepAlive = container.listen(topicChatProvider('t1'), (_, __) {});
    addTearDown(keepAlive.close);
    final notifier = container.read(topicChatProvider('t1').notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await notifier.send('will fail');
    final failed = (container.read(topicChatProvider('t1')).valueOrNull ??
            const <EphemeralMessage>[])
        .where((m) => m.status == MessageStatus.failed)
        .toList();
    expect(failed, hasLength(1), reason: 'the send error must be visible');

    // Now let it succeed and retry.
    gateway.failSend = false;
    await notifier.retry(failed.single.id);
    final after = container.read(topicChatProvider('t1')).valueOrNull ??
        const <EphemeralMessage>[];

    expect(after.where((m) => m.status == MessageStatus.failed), isEmpty,
        reason: 'retry must clear the failed copy');
    expect(after.map((m) => m.content), contains('will fail'),
        reason: 'retry must re-deliver the original body exactly once');
    expect(
      after.where((m) => m.content == 'will fail'),
      hasLength(1),
      reason: 'retry must not leave a ghost next to its replacement',
    );
  });
}
