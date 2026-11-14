import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../../core/auth/auth_controller.dart';
import 'voice_dialable.dart';
import '../../../core/providers.dart';

/// Live stage state for one topic.
///
/// This drives a real LiveKit room. The server mints a token; this class
/// connects, publishes the microphone only when the server granted publish
/// rights, and tears the room down on leave.
///
/// Two rules it must never break:
///   * connect with the token exactly as issued - never "fix up" the grant;
///   * destroy the Room and stop local audio on every exit path, or the phone
///     keeps a hot microphone after the student leaves the stage.
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

  /// The connected LiveKit room, or null when not on a stage.
  lk.Room? _room;
  lk.EventsListener? _events;

  /// Enter the stage as a passive listener.
  ///
  /// Minting a token with `asSpeaker: false` is the only thing the client is
  /// allowed to ask for. If the server returns a token that happens to carry
  /// publish rights, that is the server's decision, not something this class
  /// infers from its own request.
  Future<void> joinAsListener(String incomingTopicId) async {
    if (state.joined) return;
    try {
      final gateway = _ref.read(pulseGatewayProvider);
      final stageToken =
          await gateway.mintStageToken(topicId: topicId, asSpeaker: false);
      if (!mounted) return;

      // An empty token means the deployment has no voice server. Say so instead
      // of pretending to be connected: a green banner over silence is a lie.
      if (!isDialableStageToken(stageToken)) {
        state = state.copyWith(isConnected: false, joined: false);
        return;
      }

      final room = lk.Room();
      await room.connect(stageToken.wsUrl, stageToken.token);
      if (!mounted) {
        await room.disconnect();
        await room.dispose();
        return;
      }
      _room = room;
      _bindRoomEvents(room);

      state = state.copyWith(isConnected: true, joined: true);
    } catch (_) {
      await _teardownRoom();
      if (!mounted) return;
      state = state.copyWith(isConnected: false, joined: false);
    }
  }

  /// Mirror the real room's participants into the stage state.
  void _bindRoomEvents(lk.Room room) {
    _events = room.createListener();
    _events?.on<lk.ParticipantConnectedEvent>((_) => _syncParticipants());
    _events?.on<lk.ParticipantDisconnectedEvent>((_) => _syncParticipants());
    _events?.on<lk.TrackMutedEvent>((_) => _syncParticipants());
    _events?.on<lk.TrackUnmutedEvent>((_) => _syncParticipants());
    _events?.on<lk.ActiveSpeakersChangedEvent>((e) {
      final ids = e.speakers.map((p) => p.identity).toList();
      if (!mounted) return;
      state = state.copyWith(
        activeSpeakerId: ids.isEmpty ? null : ids.first,
        clearActiveSpeaker: ids.isEmpty,
      );
    });
    _events?.on<lk.RoomDisconnectedEvent>((_) async {
      await _teardownRoom();
      if (!mounted) return;
      state = const VoiceStageState();
    });
    _syncParticipants();
  }

  void _syncParticipants() {
    final room = _room;
    if (room == null || !mounted) return;

    final me = room.localParticipant;
    final participants = <VoiceParticipant>[
      if (me != null) _toParticipant(me, isLocal: true),
      for (final p in room.remoteParticipants.values) _toParticipant(p),
    ];

    final self = participants.isEmpty ? null : participants.first;
    state = state.copyWith(
      participants: participants,
      role: self?.role ?? state.role,
      isMuted: self?.isMuted ?? state.isMuted,
    );
  }

  VoiceParticipant _toParticipant(lk.Participant p, {bool isLocal = false}) {
    // Trust the server's grant, not the client's intent: a participant can
    // publish only if their token allowed it. `permissions` is server-issued.
    final canPublish = p.permissions.canPublish;

    return VoiceParticipant(
      identity: p.identity,
      displayRoll: p.identity,
      branchTag: p.name.isNotEmpty ? p.name : p.identity,
      role: canPublish ? StageRole.speaker : StageRole.listener,
      isMuted: !p.isMicrophoneEnabled(),
    );
  }

  Future<void> _teardownRoom() async {
    await _events?.dispose();
    _events = null;
    final room = _room;
    _room = null;
    if (room != null) {
      try {
        await room.localParticipant?.setMicrophoneEnabled(false);
      } catch (_) {}
      await room.disconnect();
      await room.dispose();
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
    if (state.role != StageRole.speaker && state.role != StageRole.moderator) {
      // A listener has no publish grant; there is nothing to unmute.
      return;
    }
    final next = !state.isMuted;
    state = state.copyWith(isMuted: next);
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(!next);
    } catch (_) {
      if (!mounted) return;
      // Roll back: the OS refused the microphone (permission or a busy device).
      state = state.copyWith(isMuted: !next);
    }
  }

  Future<void> leave() async {
    await _sub?.cancel();
    _sub = null;
    await _teardownRoom();
    if (!mounted) return;
    state = const VoiceStageState();
  }

  @override
  void dispose() {
    _sub?.cancel();
    // Fire and forget: dispose cannot await, but the microphone must not stay
    // open after the widget is gone.
    unawaited(_teardownRoom());
    super.dispose();
  }
}

final voiceStageProvider = StateNotifierProvider.autoDispose
    .family<VoiceStageController, VoiceStageState, String>((ref, topicId) {
  return VoiceStageController(ref, topicId);
});
