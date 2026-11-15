import 'package:kiit_contracts/kiit_contracts.dart';

import 'chat_socket_service.dart';

/// Everything the app needs from the outside world.
///
/// An interface with this few methods is the whole point: the UI cannot grow a
/// dependency on a specific backend shape. Every method is a stream or a
/// future, so demo and live implementations are interchangeable.
abstract interface class PulseGateway {
  // ---- Radar -------------------------------------------------------------

  /// Live radar for a zone. Emits the full sorted list on every change; the
  /// server is responsible for ordering, the client never re-sorts.
  Stream<List<TopicPulse>> watchRadar(CampusZone zone);

  /// One-shot read, used on pull-to-refresh and cold start.
  Future<List<TopicPulse>> fetchRadar(CampusZone zone);

  /// How many students are in a zone right now (the header telemetry).
  Stream<int> watchZonePopulation(CampusZone zone);

  /// Open a new topic node in [zone].
  Future<TopicPulse> createTopic({
    required String title,
    required String description,
    required CampusZone zone,
  });

  // ---- Chat --------------------------------------------------------------

  /// Ephemeral message stream for a topic, newest last.
  Stream<EphemeralMessage> watchMessages(String topicId);

  /// Transport state for a topic room.
  ///
  /// The UI needs this to say "reconnecting" honestly instead of showing a
  /// live-looking room whose socket is actually down. Gateways with no
  /// transport (the demo) emit nothing, which the UI reads as "assume live".
  Stream<SocketStatus> watchSocketStatus(String topicId);

  /// Recent history (last N) for cold open.
  Future<List<EphemeralMessage>> fetchRecentMessages(
    String topicId, {
    int limit = 50,
  });

  /// Send a message. Returns the server-acked message.
  Future<EphemeralMessage> sendMessage({
    required String topicId,
    required String content,
  });

  /// React to a message. Fire-and-forget on the wire.
  Future<void> sendReaction({
    required String topicId,
    required String messageId,
    required String emoji,
  });

  // ---- Voice -------------------------------------------------------------

  /// Mint a LiveKit token for the topic's stage.
  ///
  /// [asSpeaker] must be false for a normal listener: the client cannot grant
  /// itself publish rights. Promotion happens server-side.
  Future<StageToken> mintStageToken({
    required String topicId,
    required bool asSpeaker,
  });

  /// Announce that this student is on a topic's stage.
  ///
  /// Separate from [mintStageToken] because minting happens before a socket
  /// exists; joining is what puts the student on the roster and scores a voice
  /// join on the radar.
  Future<void> joinStage(String topicId);

  /// Announce that this student has left a topic's stage.
  Future<void> leaveStage(String topicId);

  /// Raise / lower a hand on a stage.
  Future<void> setHandRaised({
    required String topicId,
    required bool raised,
  });

  /// Who is on the stage right now.
  Stream<List<VoiceParticipant>> watchStage(String topicId);

  // ---- Passport ----------------------------------------------------------

  Future<List<FoilBadge>> fetchBadges(String studentRoll);

  // ---- Session -----------------------------------------------------------

  /// Verify an @kiit.ac.in identity and return a session token.
  Future<Session> signIn(String email);

  void dispose();
}

/// The authenticated student.
class Session {
  const Session({
    required this.email,
    required this.rollNumber,
    required this.branchTag,
    required this.token,
    required this.expiresAt,
  });

  final String email;
  final String rollNumber;
  final String branchTag;
  final String token;
  final DateTime expiresAt;

  bool get isValid => DateTime.now().isBefore(expiresAt);
}
