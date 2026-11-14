import 'dart:async';
import 'dart:convert';

import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket client for `/ws/topics/:topicID`.
///
/// Responsibilities kept strictly here:
///   * one connection per topic room
///   * exponential backoff reconnect with jitter
///   * a heartbeat so a silently dead socket is detected, not assumed alive
///   * decode envelopes, emit typed events; send optimistic messages
///
/// It never stores message history (that is the repository's job) and never
/// touches widget state.
class ChatSocketService {
  ChatSocketService({
    required this.baseWsUrl,
    this.heartbeat = const Duration(seconds: 25),
    this.maxBackoff = const Duration(seconds: 20),
  });

  /// e.g. `wss://api.kiitpulse.app`
  final String baseWsUrl;
  final Duration heartbeat;
  final Duration maxBackoff;

  final _messages = StreamController<EphemeralMessage>.broadcast();
  final _presence = StreamController<PresenceFrame>.broadcast();
  final _ticks = StreamController<VelocityTick>.broadcast();
  final _connection = StreamController<SocketStatus>.broadcast();

  Stream<EphemeralMessage> get messages => _messages.stream;
  Stream<PresenceFrame> get presence => _presence.stream;
  Stream<VelocityTick> get velocityTicks => _ticks.stream;
  Stream<SocketStatus> get status => _connection.stream;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _ping;
  Timer? _retry;
  String? _topicId;
  String? _token;
  int _attempt = 0;
  bool _disposed = false;
  SocketStatus _state = SocketStatus.idle;

  SocketStatus get currentStatus => _state;

  /// Attach to a topic room. Safe to call repeatedly with the same topic.
  void connect({required String topicId, required String token}) {
    if (_disposed) return;
    if (_topicId == topicId && _state == SocketStatus.open) return;
    _topicId = topicId;
    _token = token;
    _open();
  }

  void _open() {
    _retry?.cancel();
    _teardownSocket();
    final topic = _topicId;
    if (topic == null || _disposed) return;

    _setStatus(SocketStatus.connecting);
    final uri = Uri.parse('${_trimmed(baseWsUrl)}/ws/topics/$topic')
        .replace(queryParameters: {
      if (_token != null) 'access_token': _token!,
    });

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _sub = channel.stream.listen(
        _onData,
        onError: (Object _) => _onDrop(),
        onDone: _onDrop,
        cancelOnError: false,
      );
      _channel!.ready.then((_) {
        if (_disposed) return;
        _attempt = 0;
        _setStatus(SocketStatus.open);
        _startHeartbeat();
        // Ask for the current presence snapshot on (re)connect.
        _send({'type': 'hello', 'topic_id': topic});
      }).catchError((Object _) {
        _onDrop();
      });
    } catch (_) {
      _onDrop();
    }
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    late final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      json = decoded;
    } catch (_) {
      return;
    }

    final envelope = ChatEnvelope.fromJson(json);
    final msg = envelope.sendMessage;
    if (msg != null) {
      if (!_messages.isClosed) _messages.add(msg);
      return;
    }
    final presence = envelope.presence;
    if (presence != null) {
      if (!_presence.isClosed) _presence.add(presence);
      return;
    }
    final tick = envelope.velocityTick;
    if (tick != null) {
      if (!_ticks.isClosed) _ticks.add(tick);
      return;
    }
    // send_message echo from our own optimistic send: ignore, we already
    // rendered it. Reactions and hand raises are server-side only.
  }

  /// Send a message. The caller has already rendered it optimistically.
  void sendMessage({
    required String topicId,
    required String senderRoll,
    required String branchTag,
    required String content,
    String? clientId,
  }) {
    _send({
      'send_message': {
        'id': clientId ?? '',
        'topic_id': topicId,
        'sender_roll': senderRoll,
        'sender_branch_tag': branchTag,
        'content': content,
        'timestamp_unix': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
    });
  }

  void sendReaction({
    required String topicId,
    required String messageId,
    required String emoji,
    required String senderRoll,
  }) {
    _send({
      'reaction': {
        'topic_id': topicId,
        'message_id': messageId,
        'emoji': emoji,
        'sender_roll': senderRoll,
      },
    });
  }

  void sendHandRaise({
    required String topicId,
    required String senderRoll,
    required bool raised,
  }) {
    _send({
      'hand_raise': {
        'topic_id': topicId,
        'sender_roll': senderRoll,
        'raised': raised,
      },
    });
  }

  void _send(Map<String, dynamic> frame) {
    final channel = _channel;
    if (channel == null || _state != SocketStatus.open) return;
    try {
      channel.sink.add(jsonEncode(frame));
    } catch (_) {
      _onDrop();
    }
  }

  void _startHeartbeat() {
    _ping?.cancel();
    _ping = Timer.periodic(heartbeat, (_) {
      if (_state != SocketStatus.open) return;
      _send({'type': 'ping'});
    });
  }

  void _onDrop() {
    if (_disposed) return;
    _teardownSocket();
    _setStatus(SocketStatus.disconnected);
    if (_topicId == null) return;

    _attempt++;
    // Exponential backoff capped at maxBackoff: 1s, 2s, 4s, 8s, 16s, 20s...
    // The floor is min(1000, maxBackoff): clamping to a lower bound above the
    // upper bound throws, so a client configured with a sub-second backoff
    // (tests, or a latency-critical room) must not crash here.
    final maxMs = maxBackoff.inMilliseconds;
    final floorMs = maxMs < 1000 ? maxMs : 1000;
    final exponential = 1000 * (1 << _attempt.clamp(1, 5));
    final capped = exponential.clamp(floorMs, maxMs).toInt();

    // Jitter must be *symmetric* around the base delay. A jitter that only ever
    // adds time (abs()) is worse than none: when a campus-wide outage ends,
    // every client waits longer than it needs to and they still arrive
    // together. Better to spread them across the interval.
    final spread = (capped * 0.3).toInt();
    final jitter = ((_jitterSeed() * 2) - 1) * spread;
    final delayMs =
        (capped + jitter).clamp(0.0, maxMs.toDouble()).toInt();

    _retry?.cancel();
    _retry = Timer(Duration(milliseconds: delayMs), () {
      if (!_disposed) _open();
    });
  }

  /// A value in [0,1). Not cryptographic; it only needs to differ per client.
  double _jitterSeed() =>
      (DateTime.now().microsecondsSinceEpoch % 10000) / 10000.0;

  void _teardownSocket() {
    _ping?.cancel();
    _ping = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _setStatus(SocketStatus next) {
    _state = next;
    if (!_connection.isClosed) _connection.add(next);
  }

  /// Leave the room and stop retrying.
  void disconnect() {
    _topicId = null;
    _retry?.cancel();
    _teardownSocket();
    _setStatus(SocketStatus.idle);
  }

  Future<void> dispose() async {
    _disposed = true;
    disconnect();
    await _messages.close();
    await _presence.close();
    await _ticks.close();
    await _connection.close();
  }

  static String _trimmed(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

enum SocketStatus { idle, connecting, open, disconnected }
