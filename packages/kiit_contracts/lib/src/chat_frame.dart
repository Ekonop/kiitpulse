/// Ephemeral chat wire frames.
///
/// One envelope, one payload - exactly the `oneof` in the proto. Keeping the
/// envelope shape identical in both languages means the Go hub can forward a
/// frame without ever decoding the payload, and the Dart client can switch on
/// a single key.
library;

class ChatEnvelope {
  const ChatEnvelope({
    this.sendMessage,
    this.reaction,
    this.handRaise,
    this.promoteSpeaker,
    this.velocityTick,
    this.presence,
    this.type,
  });

  final EphemeralMessage? sendMessage;
  final ReactionEvent? reaction;
  final HandRaiseRequest? handRaise;
  final SpeakerPromotion? promoteSpeaker;
  final VelocityTick? velocityTick;
  final PresenceFrame? presence;

  /// Control frames (`ping`, `pong`) that carry no payload.
  final String? type;

  String get kind {
    if (sendMessage != null) return 'send_message';
    if (reaction != null) return 'reaction';
    if (handRaise != null) return 'hand_raise';
    if (promoteSpeaker != null) return 'promote_speaker';
    if (velocityTick != null) return 'velocity_tick';
    if (presence != null) return 'presence';
    return type ?? 'unknown';
  }

  factory ChatEnvelope.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? sub(String key) {
      final v = json[key];
      return v is Map<String, dynamic> ? v : null;
    }

    final msg = sub('send_message');
    final react = sub('reaction');
    final hand = sub('hand_raise');
    final promo = sub('promote_speaker');
    final tick = sub('velocity_tick');
    final presence = sub('presence');

    return ChatEnvelope(
      sendMessage: msg == null ? null : EphemeralMessage.fromJson(msg),
      reaction: react == null ? null : ReactionEvent.fromJson(react),
      handRaise: hand == null ? null : HandRaiseRequest.fromJson(hand),
      promoteSpeaker: promo == null ? null : SpeakerPromotion.fromJson(promo),
      velocityTick: tick == null ? null : VelocityTick.fromJson(tick),
      presence: presence == null ? null : PresenceFrame.fromJson(presence),
      type: json['type'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (sendMessage != null) 'send_message': sendMessage!.toJson(),
        if (reaction != null) 'reaction': reaction!.toJson(),
        if (handRaise != null) 'hand_raise': handRaise!.toJson(),
        if (promoteSpeaker != null) 'promote_speaker': promoteSpeaker!.toJson(),
        if (velocityTick != null) 'velocity_tick': velocityTick!.toJson(),
        if (presence != null) 'presence': presence!.toJson(),
        if (type != null) 'type': type,
      };
}

/// A single ephemeral message in a topic room.
///
/// [status] is client-side only (optimistic rendering); it never goes on the
/// wire and the server never echoes it.
class EphemeralMessage {
  const EphemeralMessage({
    required this.id,
    required this.topicId,
    required this.senderRoll,
    required this.senderBranchTag,
    required this.content,
    required this.timestamp,
    this.status = MessageStatus.sent,
    this.reactions = const {},
    this.replyToId,
    this.clientId,
  });

  final String id;
  final String topicId;
  final String senderRoll;
  final String senderBranchTag;
  final String content;
  final DateTime timestamp;
  final MessageStatus status;

  /// emoji -> count.
  final Map<String, int> reactions;

  final String? replyToId;

  /// The sender's own optimistic id, echoed back by the hub.
  ///
  /// Reconciliation uses this when present so identity is exact. Matching on
  /// sender+content instead would cross-wire two identical messages from the
  /// same student, making one appear to vanish.
  final String? clientId;

  /// First two characters of the roll number, used for the avatar tile.
  String get initials =>
      senderRoll.isEmpty ? '??' : senderRoll.substring(0, 2).toUpperCase();

  EphemeralMessage copyWith({
    String? id,
    String? topicId,
    String? senderRoll,
    String? senderBranchTag,
    String? content,
    DateTime? timestamp,
    MessageStatus? status,
    Map<String, int>? reactions,
    String? replyToId,
    String? clientId,
  }) =>
      EphemeralMessage(
        id: id ?? this.id,
        topicId: topicId ?? this.topicId,
        senderRoll: senderRoll ?? this.senderRoll,
        senderBranchTag: senderBranchTag ?? this.senderBranchTag,
        content: content ?? this.content,
        timestamp: timestamp ?? this.timestamp,
        status: status ?? this.status,
        reactions: reactions ?? this.reactions,
        replyToId: replyToId ?? this.replyToId,
        clientId: clientId ?? this.clientId,
      );

  factory EphemeralMessage.fromJson(Map<String, dynamic> json) =>
      EphemeralMessage(
        id: json['id'] as String? ?? '',
        topicId: json['topic_id'] as String? ?? '',
        senderRoll: json['sender_roll'] as String? ?? '',
        senderBranchTag: json['sender_branch_tag'] as String? ?? '',
        content: json['content'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          ((json['timestamp_unix'] as num?)?.toInt() ?? 0) * 1000,
        ),
        replyToId: json['reply_to_id'] as String?,
        clientId: json['client_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'topic_id': topicId,
        'sender_roll': senderRoll,
        'sender_branch_tag': senderBranchTag,
        'content': content,
        'timestamp_unix': timestamp.millisecondsSinceEpoch ~/ 1000,
        if (replyToId != null) 'reply_to_id': replyToId,
        if (clientId != null) 'client_id': clientId,
      };
}

enum MessageStatus {
  /// Locally rendered, not yet acked.
  sending,

  /// Acked by the hub.
  sent,

  /// Retry pending / failed permanently.
  failed,
}

class ReactionEvent {
  const ReactionEvent({
    required this.topicId,
    required this.messageId,
    required this.emoji,
    required this.senderRoll,
  });

  final String topicId;
  final String messageId;
  final String emoji;
  final String senderRoll;

  factory ReactionEvent.fromJson(Map<String, dynamic> json) => ReactionEvent(
        topicId: json['topic_id'] as String? ?? '',
        messageId: json['message_id'] as String? ?? '',
        emoji: json['emoji'] as String? ?? '',
        senderRoll: json['sender_roll'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'topic_id': topicId,
        'message_id': messageId,
        'emoji': emoji,
        'sender_roll': senderRoll,
      };
}

class HandRaiseRequest {
  const HandRaiseRequest({
    required this.topicId,
    required this.senderRoll,
  });

  final String topicId;
  final String senderRoll;

  factory HandRaiseRequest.fromJson(Map<String, dynamic> json) =>
      HandRaiseRequest(
        topicId: json['topic_id'] as String? ?? '',
        senderRoll: json['sender_roll'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'topic_id': topicId,
        'sender_roll': senderRoll,
      };
}

class SpeakerPromotion {
  const SpeakerPromotion({
    required this.topicId,
    required this.targetRoll,
    required this.granted,
  });

  final String topicId;
  final String targetRoll;
  final bool granted;

  factory SpeakerPromotion.fromJson(Map<String, dynamic> json) =>
      SpeakerPromotion(
        topicId: json['topic_id'] as String? ?? '',
        targetRoll: json['target_roll'] as String? ?? '',
        granted: json['granted'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'topic_id': topicId,
        'target_roll': targetRoll,
        'granted': granted,
      };
}

class VelocityTick {
  const VelocityTick({
    required this.topicId,
    required this.updatedVelocity,
    required this.activeListeners,
  });

  final String topicId;
  final double updatedVelocity;
  final int activeListeners;

  factory VelocityTick.fromJson(Map<String, dynamic> json) => VelocityTick(
        topicId: json['topic_id'] as String? ?? '',
        updatedVelocity:
            (json['updated_velocity'] as num?)?.toDouble() ?? 0,
        activeListeners: json['active_listeners'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'topic_id': topicId,
        'updated_velocity': updatedVelocity,
        'active_listeners': activeListeners,
      };
}

/// Who else is in the room right now. Drives the "N here" counter.
class PresenceFrame {
  const PresenceFrame({
    required this.topicId,
    required this.count,
    this.members = const [],
  });

  final String topicId;
  final int count;
  final List<String> members;

  factory PresenceFrame.fromJson(Map<String, dynamic> json) => PresenceFrame(
        topicId: json['topic_id'] as String? ?? '',
        count: json['count'] as int? ?? 0,
        members: (json['members'] as List?)?.cast<String>() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'topic_id': topicId,
        'count': count,
        'members': members,
      };
}
