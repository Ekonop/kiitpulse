import 'package:flutter_test/flutter_test.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiitpulse/features/voice_room/presentation/voice_dialable.dart';

StageToken _token(String token, String url) =>
    StageToken(token: token, wsUrl: url, room: 'kiit-huddle-t1');

void main() {
  group('voice is only dialled when there is somewhere to dial', () {
    test('a real wss url is dialable', () {
      expect(
        isDialableStageToken(_token('jwt', 'wss://voice.kiitpulse.app')),
        isTrue,
      );
    });

    test('the demo placeholder is never dialled', () {
      // RFC 2606 reserves .invalid so it can never resolve. Dialling it would
      // spin LiveKit's reconnect timers against a dead host.
      expect(
        isDialableStageToken(_token('demo.listener', 'wss://demo.livekit.invalid')),
        isFalse,
      );
    });

    test('an empty token or url is not dialable', () {
      expect(isDialableStageToken(_token('', 'wss://voice.kiitpulse.app')), isFalse);
      expect(isDialableStageToken(_token('jwt', '')), isFalse);
    });

    test('a url with no host is not dialable', () {
      expect(isDialableStageToken(_token('jwt', 'not-a-url')), isFalse);
    });
  });
}
