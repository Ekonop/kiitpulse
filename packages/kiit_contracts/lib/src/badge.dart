/// Passport badge contracts.
library;

/// Hardware-signed collectible issued for participation.
///
/// The signature is what makes a badge non-forgeable: on device it is produced
/// from a key held in the Android Keystore, so a badge cannot be minted from a
/// rooted or re-flashed handset without invalidating it.
class FoilBadge {
  const FoilBadge({
    required this.id,
    required this.studentRoll,
    required this.type,
    required this.label,
    required this.issuedAt,
    this.eventName,
    this.signature,
    this.accentArgb = 0xFF00C853,
    this.verified = true,
  });

  final String id;
  final String studentRoll;

  /// `KIIT_FEST`, `KRITARTH`, `CYBERVAULT`, `HACKNIGHT`, `SOCIETY_WORKSHOP`.
  final String type;
  final String label;
  final DateTime issuedAt;
  final String? eventName;

  /// Base64 hardware signature. `null` for demo/unverified badges.
  final String? signature;
  final int accentArgb;
  final bool verified;

  bool get isVerified => verified && (signature?.isNotEmpty ?? false);

  factory FoilBadge.fromJson(Map<String, dynamic> json) => FoilBadge(
        id: json['id'] as String? ?? '',
        studentRoll: json['student_roll'] as String? ?? '',
        type: json['badge_type'] as String? ?? 'UNKNOWN',
        label: json['label'] as String? ?? '',
        issuedAt: DateTime.fromMillisecondsSinceEpoch(
          ((json['issued_at_unix'] as num?)?.toInt() ?? 0) * 1000,
        ),
        eventName: json['event_name'] as String?,
        signature: json['signature'] as String?,
        accentArgb: json['accent_argb'] as int? ?? 0xFF00C853,
        verified: json['verified'] as bool? ?? false,
      );
}
