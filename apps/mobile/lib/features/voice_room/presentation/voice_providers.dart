import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_contracts/kiit_contracts.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/providers.dart';

/// Live stage state for one topic.
///
/// This is the client-side half of the LiveKit controller. The real SDK
/// (`livekit_client`) plugs in behind [attachRoom] when the backend and the
/// native platform are wired; until then the demo gateway drives the same
/// state machine, so the UI is exercised end to end.
///
/// The role machine is the security boundary:
///   listener -> handRaised -> speaker
/// A client can move to handRaised by itself. Only the server can move it to
/// speaker, which is why [promote] is never called from the UI.
class VoiceStageState {
  const VoiceStageState({
    this.isConnected = false,
    this.isMuted = true,
    this.role = StageRole.listener,
    this.participants = const [],
    this.activeSpeakerId,
    this.joined = false,
  });

  final bool isConnected;
  final bool isMuted;
  final StageRole role;
  final List<VoiceParticipant> participants;
  final String? activeSpeakerId;

  /// True once the student actually entered the stage (as opposed to just
  /// seeing the banner attached to the topic).
  final bool joined;

  List<VoiceParticipant> get speakers => participants
      .where((p) => p.role == StageRole.speaker || p.role == StageRole.moderator)
      .toList();

  List<VoiceParticipant> get handRaised => participants
      .where((p) => p.role == StageRole.handRaised)
      .toList();

  int get listenerCount => participants
      .where((p) => p.role == StageRole.listener || p.role == StageRole.handRaised)
      .length;

  VoiceStageState copyWith({
    bool? isConnected,
    bool? isMuted,
    StageRole? role,
    List<VoiceParticipant>? participants,
    String? activeSpeakerId,
    bool? joined,
    bool clearActiveSpeaker = false,
  }) {
    return VoiceStageState(
      isConnected: isConnected ?? this.isConnected,
      isMuted: isMuted ?? this.isMuted,
      role: role ?? this.role,
      participants: participants ?? this.participants,
      activeSpeakerId:
          clearActiveSpeaker ? null : (activeSpeakerId ?? this.activeSpeakerId),
      joined: joined ?? this.joined,
    );
  }
}

class VoiceStageController extends StateNotifier<VoiceStageState> {
  VoiceStageController(this._ref, this.topicId)
      : super(const VoiceStageState()) {
    _sub = _ref.read(pulseGatewayProvider).watchStage(topicId).listen(_onStage);
  }

  final Ref _ref;
  final String topicId;
  StreamSubscription<List<VoiceParticipant>>? _sub;

  void _onStage(List<VoiceParticipant> participants) {
    if (!mounted) return;
    final session = _ref.read(currentSessionProvider);
    final me = session == null
        ? null
        : participants
            .where((p) => p.displayRoll == session.rollNumber)
            .firstOrNull;

    // Animate a rotating "active speaker" so audio meters move even when the
    // SDK has not reported a speaker change yet.
    final speakers = participants
        .where((p) => p.role == StageRole.speaker || p.role == StageRole.moderator)
        .toList();
    final active = speakers.isEmpty
        ? null
        : speakers[math.Random().nextInt(speakers.length)].identity;

    state = state.copyWith(
      participants: participants,
      role: me?.role ?? state.role,
      isMuted: me?.isMuted ?? state.isMuted,
      activeSpeakerId: active,
      clearActiveSpeaker: active == null,
    );
  }

  /// Enter the stage as a passive listener.
  ///
  /// Minting a token with `asSpeaker: false` is the only thing the client is
  /// allowed to ask for; if the server returns publish rights anyway we ignore
  /// them rather than trusting our own request.
  Future<void> joinAsListener(String incomingTopicId) async {
    if (state.joined) return;
    try {
      final gateway = _ref.read(pulseGatewayProvider);
      await gateway.mintStageToken(topicId: topicId, asSpeaker: false);
      if (!mounted) return;
      state = state.copyWith(isConnected: true, joined: true);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isConnected: false, joined: false);
    }
  }

  /// Raise or lower a hand. This is optimistic: the request is one tap, but a
  /// hand raise should feel instant.
  Future<void> toggleHand() async {
    final raised = state.role == StageRole.handRaised;
    state = state.copyWith(
      role: raised ? StageRole.listener : StageRole.handRaised,
    );
    try {
      await _ref.read(pulseGatewayProvider).setHandRaised(
            topicId: topicId,
            raised: !raised,
          );
    } catch (_) {
      if (!mounted) return;
      // Roll back so the UI never claims a state the server rejected.
      state = state.copyWith(
        role: raised ? StageRole.handRaised : StageRole.listener,
      );
    }
  }

  Future<void> toggleMic() async {
    if (state.role != StageRole.speaker) return;
    final next = !state.isMuted;
    state = state.copyWith(isMuted: next);
    // Attached LiveKit local participant would be toggled here.
  }

  Future<void> leave() async {
    await _sub?.cancel();
    _sub = null;
    if (!mounted) return;
    state = const VoiceStageState();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final voiceStageProvider = StateNotifierProvider.autoDispose
    .family<VoiceStageController, VoiceStageState, String>((ref, topicId) {
  return VoiceStageController(ref, topicId);
});
