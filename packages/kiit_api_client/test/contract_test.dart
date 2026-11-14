import 'dart:convert';

import 'package:kiit_api_client/kiit_api_client.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:test/test.dart';

/// Contract tests: the Dart client and the Go backend must agree on the wire
/// format.
///
/// These decode literal JSON copied from the Go server's response bodies (see
/// services/backend/domain/types.go and api/router.go). If a field is renamed on
/// either side, a test fails here instead of the app silently showing blanks in
/// production - which is exactly how a `velocity_score` typo would surface.
void main() {
  group('auth sign-in response', () {
    // Verbatim shape from POST /auth/signin.
    const body = '''
{
  "branch_tag": "CSE-AIML '28",
  "email": "241551058@kiit.ac.in",
  "expires_in": 43200,
  "roll_number": "241551058",
  "token": "header.payload.signature"
}''';

    test('decodes into a Session with a valid expiry', () {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final session = Session(
        email: json['email'] as String,
        rollNumber: json['roll_number'] as String,
        branchTag: json['branch_tag'] as String,
        token: json['token'] as String,
        expiresAt: DateTime.now()
            .add(Duration(seconds: (json['expires_in'] as num).toInt())),
      );

      expect(session.rollNumber, '241551058');
      expect(session.branchTag, "CSE-AIML '28");
      expect(session.isValid, isTrue);
    });
  });

  group('topic pulse', () {
    // Verbatim shape from GET /radar/zones/:zone.
    const body = '''
[{
  "id": "t-abc123",
  "title": "#Campus15-DSA-Viva",
  "description": "Viva sheet says B-Tree deletion",
  "zone": 1,
  "velocity_score": 42.5,
  "has_active_voice_stage": true,
  "active_speakers": 3,
  "active_listeners": 12,
  "message_count": 27,
  "created_at_unix": 1700000000,
  "last_activity_unix": 1700000600,
  "tag": "ACADEMIC"
}]''';

    test('decodes every field the radar card renders', () {
      final list = jsonDecode(body) as List<dynamic>;
      final topic = TopicPulse.fromJson(list.first as Map<String, dynamic>);

      expect(topic.id, 't-abc123');
      expect(topic.title, '#Campus15-DSA-Viva');
      expect(topic.zone, CampusZone.campus15);
      expect(topic.velocityScore, 42.5);
      expect(topic.hasActiveVoiceStage, isTrue);
      expect(topic.activeSpeakers, 3);
      expect(topic.activeListeners, 12);
      expect(topic.messageCount, 27);
    });

    test('velocity score drives the badge label', () {
      // The badge must not render a blank for a score the server can produce.
      final topic = TopicPulse.fromJson(
        jsonDecode(body).first as Map<String, dynamic>,
      );
      final label = velocityLabel(topic.velocityScore);
      expect(label, isNotEmpty);
      expect(label, anyOf('SURGING', 'HOT', 'RISING', 'WARM', 'COOLING'));
    });
  });

  group('chat message', () {
    // Verbatim shape broadcast by the Go hub, including the echoed client id.
    const frame = '''
{
  "id": "m-9f8e7d6c5b4a3210",
  "topic_id": "t-abc123",
  "client_id": "local-1700000000123456",
  "sender_roll": "241551058",
  "sender_branch_tag": "CSE-AIML '28",
  "content": "viva moved to lab 3",
  "timestamp_unix": 1700000600
}''';

    test('decodes, including client_id used for reconciliation', () {
      final msg = EphemeralMessage.fromJson(
        jsonDecode(frame) as Map<String, dynamic>,
      );

      expect(msg.id, 'm-9f8e7d6c5b4a3210');
      expect(msg.clientId, 'local-1700000000123456',
          reason: 'the sender needs its optimistic id echoed back');
      expect(msg.senderRoll, '241551058');
      expect(msg.content, 'viva moved to lab 3');
      expect(msg.initials, '24');
    });

    test('round-trips through toJson for the socket send', () {
      final original = EphemeralMessage.fromJson(
        jsonDecode(frame) as Map<String, dynamic>,
      );
      final round = EphemeralMessage.fromJson(original.toJson());

      expect(round.id, original.id);
      expect(round.clientId, original.clientId);
      expect(round.content, original.content);
      expect(
        round.timestamp.millisecondsSinceEpoch ~/ 1000,
        original.timestamp.millisecondsSinceEpoch ~/ 1000,
      );
    });
  });

  group('envelope', () {
    test('unwraps a send_message frame', () {
      final env = ChatEnvelope.fromJson({
        'send_message': {
          'id': 'm-1',
          'topic_id': 't1',
          'sender_roll': '241551058',
          'sender_branch_tag': 'x',
          'content': 'hi',
          'timestamp_unix': 1700000000,
        },
      });
      expect(env.sendMessage?.content, 'hi');
    });

    test('unwraps a presence frame', () {
      final env = ChatEnvelope.fromJson({
        'presence': {'topic_id': 't1', 'count': 4, 'members': ['a', 'b']},
      });
      expect(env.presence?.count, 4);
    });

    test('an unknown frame decodes to nothing rather than throwing', () {
      final env = ChatEnvelope.fromJson({'something_new': {'x': 1}});
      expect(env.sendMessage, isNull);
      expect(env.presence, isNull);
    });
  });

  group('campus zones', () {
    test('every zone key the Go server emits parses', () {
      // These strings come from campus.Zone.Key() in the backend.
      const keys = {
        'campus15': CampusZone.campus15,
        'ksac': CampusZone.ksac,
        'kp_hostels': CampusZone.kpHostels,
        'food_court': CampusZone.foodCourt,
        'campus6_7': CampusZone.campus6and7,
        'kims': CampusZone.kims,
        'off_campus': CampusZone.offCampus,
      };

      for (final entry in keys.entries) {
        final zone = CampusZone.values.firstWhere(
          (z) => z.key == entry.key,
          orElse: () => throw StateError(
            'backend zone "${entry.key}" has no Dart equivalent',
          ),
        );
        expect(zone, entry.value);
      }
    });
  });

  group('geofences', () {
    test('known campus coordinates resolve in Dart exactly as in Go', () {
      // Mirrors TestKnownCampusPoints in services/backend/campus.
      expect(KiitGeofences.resolve(20.35475, 85.81900), CampusZone.campus15);
      expect(KiitGeofences.resolve(20.35800, 85.81700), CampusZone.kpHostels);
      expect(KiitGeofences.resolve(20.34000, 85.83000), CampusZone.offCampus);
    });

    test('no two fences overlap, matching the Go invariant', () {
      final all = KiitGeofences.all;
      for (var i = 0; i < all.length; i++) {
        for (var j = i + 1; j < all.length; j++) {
          final a = all[i];
          final b = all[j];
          final overlaps = a.minLat < b.maxLat &&
              b.minLat < a.maxLat &&
              a.minLng < b.maxLng &&
              b.minLng < a.maxLng;
          expect(overlaps, isFalse,
              reason: '${a.zone} and ${b.zone} overlap, so resolve order '
                  'would silently pick one');
        }
      }
    });
  });
}
