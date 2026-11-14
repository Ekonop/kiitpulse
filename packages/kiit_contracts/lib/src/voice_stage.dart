/// LiveKit voice stage contracts.
library;

enum StageRole { listener, handRaised, speaker, moderator }

/// Snapshot of one person on the stage.
class VoiceParticipant {
  const VoiceParticipant({
    required this.identity,
    required this.displayRoll,
    required this.branchTag,
    this.role = StageRole.listener,
    this.isSpeaking = false,
    this.isMuted = true,
    this.joinedAt,
  });

  final String identity;

  /// KIIT roll number, e.g. `241551058`.
  final String displayRoll;

  /// e.g. `CSE-AIML '28`.
  final String branchTag;
  final StageRole role;
  final bool isSpeaking;
  final bool isMuted;
  final DateTime? joinedAt;

  String get initials => displayRoll.isEmpty
      ? '??'
      : displayRoll.substring(0, displayRoll.length >= 2 ? 2 : 1).toUpperCase();

  VoiceParticipant copyWith({
    String? identity,
    String? displayRoll,
    String? branchTag,
    StageRole? role,
    bool? isSpeaking,
    bool? isMuted,
    DateTime? joinedAt,
  }) =>
      VoiceParticipant(
        identity: identity ?? this.identity,
        displayRoll: displayRoll ?? this.displayRoll,
        branchTag: branchTag ?? this.branchTag,
        role: role ?? this.role,
        isSpeaking: isSpeaking ?? this.isSpeaking,
        isMuted: isMuted ?? this.isMuted,
        joinedAt: joinedAt ?? this.joinedAt,
      );
}

/// Credentials returned by `POST /voice/token`.
class StageToken {
  const StageToken({required this.token, required this.wsUrl, this.room});

  final String token;
  final String wsUrl;
  final String? room;

  factory StageToken.fromJson(Map<String, dynamic> json) => StageToken(
        token: json['token'] as String? ?? '',
        wsUrl: json['ws_url'] as String? ?? '',
        room: json['room'] as String?,
      );

  /// Room name convention shared with the Go backend.
  static String roomFor(String topicId) => 'kiit-huddle-$topicId';
}
