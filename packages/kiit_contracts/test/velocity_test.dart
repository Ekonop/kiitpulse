import 'dart:math' as math;

import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:test/test.dart';

/// The velocity engine is the heart of the radar: it decides what the whole
/// campus is looking at. These tests pin it to the same numbers the Go backend
/// uses (services/backend/radar/velocity.go).
void main() {
  group('weights', () {
    test('match the Go backend exactly', () {
      // If these drift, the client preview and the server ranking disagree and
      // a topic can look hot in the app but rank low on refresh.
      expect(Velocity.messageWeight, 1.0);
      expect(Velocity.reactionWeight, 0.25);
      expect(Velocity.voiceJoinWeight, 3.5);
    });

    test('a voice join outweighs a message', () {
      // Joining a stage is a stronger intent signal than typing.
      expect(Velocity.voiceJoinWeight, greaterThan(Velocity.messageWeight));
    });
  });

  group('rawScore', () {
    test('is the weighted sum', () {
      // 10*1.0 + 4*0.25 + 2*3.5 = 18.0
      final score = Velocity.rawScore(messages: 10, reactions: 4, voiceJoins: 2);
      expect(score, closeTo(18.0, 1e-9));
    });

    test('is zero for an empty topic', () {
      expect(Velocity.rawScore(messages: 0, reactions: 0, voiceJoins: 0), 0);
    });
  });

  group('score', () {
    test('weighted sum at exactly one minute', () {
      final score = Velocity.score(
        messages: 10,
        reactions: 4,
        voiceJoins: 2,
        elapsed: const Duration(minutes: 1),
      );
      expect(score, closeTo(18.0, 1e-9));
    });

    test('divides by elapsed^gamma', () {
      // 18 / 4^1.5 = 18 / 8 = 2.25
      final score = Velocity.score(
        messages: 10,
        reactions: 4,
        voiceJoins: 2,
        elapsed: const Duration(minutes: 4),
      );
      expect(score, closeTo(2.25, 1e-9));
    });

    test('a sub-minute window is clamped so a new topic cannot explode', () {
      final instant = Velocity.score(
        messages: 10,
        reactions: 0,
        voiceJoins: 0,
        elapsed: const Duration(seconds: 1),
      );
      expect(instant, closeTo(10.0, 1e-9),
          reason: 'dividing by ~0 would pin a brand new topic to the top of '
              'the radar forever');
    });

    test('an empty topic scores zero, not NaN', () {
      final score = Velocity.score(
        messages: 0,
        reactions: 0,
        voiceJoins: 0,
        elapsed: Duration.zero,
      );
      expect(score, 0);
      expect(score.isNaN, isFalse);
      expect(score.isInfinite, isFalse);
    });

    test('matches the Go Score() function across windows', () {
      // Go: RawScore(...) / math.Pow(minutes, Gamma) with minutes clamped to 1.
      for (final minutes in [1, 2, 5, 20]) {
        final goRaw = 7 * 1.0 + 3 * 0.25 + 1 * 3.5;
        final expected = goRaw / math.pow(minutes.toDouble(), 1.5);
        final got = Velocity.score(
          messages: 7,
          reactions: 3,
          voiceJoins: 1,
          elapsed: Duration(minutes: minutes),
        );
        expect(got, closeTo(expected, 1e-9),
            reason: 'diverged from the Go backend at $minutes minutes');
      }
    });
  });

  group('decay', () {
    test('0.85 per minute', () {
      expect(Velocity.afterDecay(100, 1), closeTo(85, 1e-9));
      expect(Velocity.afterDecay(100, 0), closeTo(100, 1e-9));
    });

    test('matches the Go decay formula', () {
      // Go: current * math.Pow(DecayFactor, float64(minutes))
      for (final n in [1, 5, 10, 30]) {
        final go = 100 * math.pow(0.85, n);
        expect(Velocity.afterDecay(100, n), closeTo(go, 1e-9));
      }
    });

    test('eventually falls below the purge floor', () {
      // The 24h ephemerality promise depends on this: a score must actually
      // reach the floor, or the sorted set grows without bound.
      var score = 1.0;
      var minutes = 0;
      while (score >= Velocity.purgeFloor && minutes < 1000) {
        score = Velocity.afterDecay(score, 1);
        minutes++;
      }
      expect(score, lessThan(Velocity.purgeFloor),
          reason: 'a 1.0 score never decayed below the purge floor');
      expect(minutes, lessThan(1000));
    });
  });

  group('withEvent', () {
    test('adds the right weight per event kind', () {
      expect(
        Velocity.withEvent(10, kind: VelocityEventKind.message),
        closeTo(11, 1e-9),
      );
      expect(
        Velocity.withEvent(10, kind: VelocityEventKind.reaction),
        closeTo(10.25, 1e-9),
      );
      expect(
        Velocity.withEvent(10, kind: VelocityEventKind.voiceJoin),
        closeTo(13.5, 1e-9),
      );
    });

    test('honours an explicit count', () {
      expect(
        Velocity.withEvent(0, kind: VelocityEventKind.voiceJoin, count: 3),
        closeTo(10.5, 1e-9),
      );
    });
  });

  group('labels', () {
    test('band boundaries are stable', () {
      expect(velocityLabel(200), 'SURGING');
      expect(velocityLabel(150), 'SURGING');
      expect(velocityLabel(149), 'HOT');
      expect(velocityLabel(80), 'HOT');
      expect(velocityLabel(79), 'RISING');
      expect(velocityLabel(30), 'RISING');
      expect(velocityLabel(29), 'WARM');
      expect(velocityLabel(10), 'WARM');
      expect(velocityLabel(9.9), 'COOLING');
      expect(velocityLabel(0), 'COOLING');
    });

    test('never returns an empty string', () {
      // The radar card renders this directly; a blank looks like a bug.
      for (final score in [0.0, 0.1, 50.0, 1000.0]) {
        expect(velocityLabel(score), isNotEmpty);
      }
    });
  });
}
