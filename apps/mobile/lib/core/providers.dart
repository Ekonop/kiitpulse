import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_api_client/kiit_api_client.dart';

import 'auth/auth_controller.dart';
/// Which backend the app talks to.
enum PulseBackend { demo, live }

/// Chosen at compile time: `--dart-define=PULSE_BACKEND=live`.
/// Default is [PulseBackend.demo] so a fresh clone runs with no services.
const _backend = String.fromEnvironment('PULSE_BACKEND', defaultValue: 'demo');

/// `--dart-define=PULSE_API_URL=https://api.kiitpulse.app`
const _apiUrl = String.fromEnvironment(
  'PULSE_API_URL',
  defaultValue: 'http://127.0.0.1:8080',
);

/// True when the app is running against the in-memory campus simulation.
final isDemoProvider = Provider<bool>(
  (_) => _backend != 'live',
);

/// The single transport handle for the app.
///
/// Every feature provider depends on this, never on `http` or a socket
/// directly, which is what makes the demo/live swap a one-line change.
final Provider<PulseGateway> pulseGatewayProvider = Provider<PulseGateway>((ref) {
  final PulseGateway gateway;
  if (_backend == 'live') {
    gateway = LiveGateway(
      baseUrl: _apiUrl,
      // Late-bound: the gateway reads the token at call time instead of the
      // provider graph depending on auth on every rebuild.
      sessionProvider: () {
        final session = ref.read(currentSessionProvider);
        if (session == null) {
          throw const GatewayException(
            'Session expired. Sign in again.',
            code: 'UNAUTHENTICATED',
          );
        }
        return session;
      },
    );
  } else {
    gateway = DemoGateway();
  }
  ref.onDispose(gateway.dispose);
  return gateway;
});
