import 'campus_zone.dart';

/// A trending node on the campus radar.
///
/// Mirrors `TopicPulse` in the proto. `velocityScore` and the live-stage counts
/// are server-owned telemetry: the client only ever displays them.
class TopicPulse {
  const TopicPulse({
    required this.id,
    required this.title,
    required this.description,
    required this.zone,
    required this.velocityScore,
    this.hasActiveVoiceStage = false,
    this.activeSpeakers = 0,
    this.activeListeners = 0,
    this.messageCount = 0,
    this.createdAt,
    this.lastActivityAt,
    this.tag,
  });

  final String id;

  /// Displayed with a leading `#`.
  final String title;
  final String description;
  final CampusZone zone;

  /// Messages-weighted events per minute, exponentially decayed.
  final double velocityScore;

  final bool hasActiveVoiceStage;
  final int activeSpeakers;
  final int activeListeners;
  final int messageCount;
  final DateTime? createdAt;
  final DateTime? lastActivityAt;

  /// Free-form chip label, e.g. `EXAM`, `PYQ`, `HOSTEL`, `EVENT`.
  final String? tag;

  bool get isHot => velocityScore >= 80;
  bool get isCooling => velocityScore < 20;

  TopicPulse copyWith({
    String? id,
    String? title,
    String? description,
    CampusZone? zone,
    double? velocityScore,
    bool? hasActiveVoiceStage,
    int? activeSpeakers,
    int? activeListeners,
    int? messageCount,
    DateTime? createdAt,
    DateTime? lastActivityAt,
    String? tag,
  }) {
    return TopicPulse(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      zone: zone ?? this.zone,
      velocityScore: velocityScore ?? this.velocityScore,
      hasActiveVoiceStage: hasActiveVoiceStage ?? this.hasActiveVoiceStage,
      activeSpeakers: activeSpeakers ?? this.activeSpeakers,
      activeListeners: activeListeners ?? this.activeListeners,
      messageCount: messageCount ?? this.messageCount,
      createdAt: createdAt ?? this.createdAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      tag: tag ?? this.tag,
    );
  }

  factory TopicPulse.fromJson(Map<String, dynamic> json) => TopicPulse(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        zone: CampusZone.fromWire(json['zone'] as int?),
        velocityScore: (json['velocity_score'] as num?)?.toDouble() ?? 0,
        hasActiveVoiceStage: json['has_active_voice_stage'] as bool? ?? false,
        activeSpeakers: json['active_speakers'] as int? ?? 0,
        activeListeners: json['active_listeners'] as int? ?? 0,
        messageCount: json['message_count'] as int? ?? 0,
        createdAt: _ts(json['created_at_unix']),
        lastActivityAt: _ts(json['last_activity_unix']),
        tag: json['tag'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'zone': zone.wire,
        'velocity_score': velocityScore,
        'has_active_voice_stage': hasActiveVoiceStage,
        'active_speakers': activeSpeakers,
        'active_listeners': activeListeners,
        'message_count': messageCount,
        'created_at_unix': createdAt?.millisecondsSinceEpoch ?? 0,
        'last_activity_unix': lastActivityAt?.millisecondsSinceEpoch ?? 0,
        if (tag != null) 'tag': tag,
      };

  static DateTime? _ts(Object? v) {
    final n = (v as num?)?.toInt() ?? 0;
    if (n <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(n);
  }
}
