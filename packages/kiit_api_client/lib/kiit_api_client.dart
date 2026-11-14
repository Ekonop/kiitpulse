/// KIITPulse transport layer.
///
/// The app depends on [PulseGateway] and nothing else. Two implementations
/// exist today:
///   * [DemoGateway]     - in-memory, deterministic, no network. Default on
///                         desktop and in tests so the UI is always runnable.
///   * [LiveGateway]     - real HTTP + WebSocket against the Go backend.
///
/// Swapping one for the other is a single provider override in `main.dart`.
library kiit_api_client;

export 'src/pulse_gateway.dart';
export 'src/demo_gateway.dart';
export 'src/live_gateway.dart';
export 'src/chat_socket_service.dart';
export 'src/gateway_exception.dart';
