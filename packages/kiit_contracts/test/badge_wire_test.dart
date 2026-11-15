import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:test/test.dart';

/// Pins the exact JSON the Go backend emits for a badge.
///
/// This caught a real mismatch: the server sent `type`, the contract read
/// `badge_type`, so every real badge rendered as "UNKNOWN". A unit test on each
/// side in isolation passed; only the wire shape disagreed.
void main() {
  group('badge wire contract', () {
    // Copied from a live GET /passport/:roll response.
    final wire = <String, dynamic>{
      'id': 'b-first-word-241551058',
      'student_roll': '241551058',
      'badge_type': 'FIRST_WORD',
      'label': 'First Word',
      'event_name': '8 messages sent on the campus radar',
      'issued_at_unix': 1794738927,
      'accent_argb': 4278241363,
      'verified': true,
    };

    test('parses the server field names', () {
      final b = FoilBadge.fromJson(wire);
      expect(b.id, 'b-first-word-241551058');
      expect(b.type, 'FIRST_WORD',
          reason: 'the server sends badge_type; reading "type" yields UNKNOWN');
      expect(b.label, 'First Word');
      expect(b.verified, isTrue);
    });

    test('keeps the ARGB colour intact', () {
      final b = FoilBadge.fromJson(wire);
      // 0xFF00C853 exceeds signed 32-bit; the colour must survive the round trip.
      expect(b.accentArgb, 0xFF00C853);
    });

    test('reads the issue time as seconds', () {
      final b = FoilBadge.fromJson(wire);
      expect(b.issuedAt.millisecondsSinceEpoch, 1794738927000);
    });

    test('carries the evidence text, not an attended event', () {
      final b = FoilBadge.fromJson(wire);
      // The server has no attendance feed, so event_name states the evidence
      // that earned the badge. The UI must not present it as an event.
      expect(b.eventName, contains('messages sent'));
    });
  });
}
