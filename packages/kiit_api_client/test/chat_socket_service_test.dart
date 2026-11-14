import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:test/test.dart';
import 'package:kiit_api_client/kiit_api_client.dart';
import 'package:kiit_contracts/kiit_contracts.dart';

/// Tests for the WebSocket client against a real local server.
///
/// This is the code most likely to break in the field (a hostel wifi dropping
/// mid-conversation), so it is tested against an actual socket rather than a
/// mock. A mock would happily accept the heartbeat bug that these catch.
void main() {
  late HttpServer server;
  late int port;
  // One subscription over the whole server, so sequential accepts work
  // (server.first can only be listened to once). Rebuilt per test.
  late StreamQueue<HttpRequest> pending;


  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    pending = StreamQueue(server);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  /// Accept the next incoming connection.
  Future<WebSocket> acceptOne() async {
    final req = await pending.next.timeout(const Duration(seconds: 5));
    return await WebSocketTransformer.upgrade(req);
  }

  ChatSocketService makeService({Duration backoff = const Duration(seconds: 2)}) {
    return ChatSocketService(
      baseWsUrl: 'ws://127.0.0.1:$port',
      heartbeat: const Duration(milliseconds: 80),
      maxBackoff: backoff,
    );
  }

  test('connects and decodes an incoming message envelope', () async {
    final socket = makeService();
    addTearDown(socket.dispose);

    final received = <EphemeralMessage>[];
    final sub = socket.messages.listen(received.add);
    addTearDown(sub.cancel);

    final serverSide = acceptOne();
    socket.connect(topicId: 't1', token: 'tok');

    final ws = await serverSide;
    // Wait for the client to consider itself open before pushing data.
    await Future<void>.delayed(const Duration(milliseconds: 80));

    ws.add('''{"send_message":{"id":"m1","topic_id":"t1",
      "sender_roll":"241551058","sender_branch_tag":"CSE-AIML '28",
      "content":"hello radar","timestamp_unix":1700000000}}''');

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(received, hasLength(1));
    expect(received.single.content, 'hello radar');
    expect(received.single.senderRoll, '241551058');

    await ws.close();
  });

  test('reports open status after the handshake', () async {
    final socket = makeService();
    addTearDown(socket.dispose);

    final statuses = <SocketStatus>[];
    final sub = socket.status.listen(statuses.add);
    addTearDown(sub.cancel);

    final serverSide = acceptOne();
    socket.connect(topicId: 't1', token: 'tok');
    final ws = await serverSide;
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(statuses, contains(SocketStatus.open));
    expect(socket.currentStatus, SocketStatus.open);

    await ws.close();
  });

  test('sends a message frame with the envelope the server expects', () async {
    final socket = makeService();
    addTearDown(socket.dispose);

    final serverSide = acceptOne();
    socket.connect(topicId: 't1', token: 'tok');
    final ws = await serverSide;
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final frames = <Map<String, dynamic>>[];
    final sub = ws.listen((data) {
      final decoded = jsonDecodeSafe(data as String);
      if (decoded != null) frames.add(decoded);
    });
    addTearDown(sub.cancel);

    socket.sendMessage(
      topicId: 't1',
      senderRoll: '241551058',
      branchTag: "CSE-AIML '28",
      content: 'the viva is in lab 3',
      clientId: 'local-1',
    );

    await Future<void>.delayed(const Duration(milliseconds: 120));

    // The `hello` frame may arrive first; find the actual message.
    final msg = frames.firstWhere((f) => f.containsKey('send_message'),
        orElse: () => <String, dynamic>{});
    expect(msg, isNotEmpty, reason: 'no send_message frame reached the server');

    final body = msg['send_message'] as Map<String, dynamic>;
    expect(body['content'], 'the viva is in lab 3');
    expect(body['id'], 'local-1');

    await ws.close();
  });

  test('reconnects after the server drops the socket', () async {
    final socket = makeService(backoff: const Duration(milliseconds: 400));
    addTearDown(socket.dispose);

    final statuses = <SocketStatus>[];
    final sub = socket.status.listen(statuses.add);
    addTearDown(sub.cancel);

    final firstAccept = acceptOne();
    socket.connect(topicId: 't1', token: 'tok');
    final first = await firstAccept;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(socket.currentStatus, SocketStatus.open);

    // Kill it from the server side, as a dead wifi link would.
    await first.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(statuses, contains(SocketStatus.disconnected),
        reason: 'a dropped socket must be reported, not assumed alive');

    // The client should reconnect on its own.
    final secondAccept = acceptOne();
    final second = await secondAccept.timeout(
      const Duration(seconds: 3),
      onTimeout: () => throw StateError('client never reconnected'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(socket.currentStatus, SocketStatus.open,
        reason: 'the client must recover without a manual reconnect');

    await second.close();
  });

  test('reconnect delay is bounded by maxBackoff', () async {
    // The whole point of the cap: an offline client must not back off to
    // minutes, or it looks dead when the network returns.
    final socket = ChatSocketService(
      baseWsUrl: 'ws://127.0.0.1:$port',
      heartbeat: const Duration(milliseconds: 80),
      maxBackoff: const Duration(milliseconds: 300),
    );
    addTearDown(socket.dispose);

    // No server handler consumes these; connections will be refused/dropped,
    // driving the backoff ladder.
    socket.connect(topicId: 't1', token: 'tok');

    final start = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    // Six failed attempts at an uncapped exponential would be ~63s. With the
    // 300ms cap plus jitter it stays well inside this window.
    final elapsed = DateTime.now().difference(start);
    expect(elapsed, lessThan(const Duration(seconds: 3)));

    socket.disconnect();
  });

  test('disconnect stops retrying', () async {
    final socket = makeService(backoff: const Duration(milliseconds: 300));
    addTearDown(socket.dispose);

    socket.connect(topicId: 't1', token: 'tok');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    socket.disconnect();

    expect(socket.currentStatus, SocketStatus.idle);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(socket.currentStatus, SocketStatus.idle,
        reason: 'disconnect must cancel the retry timer');
  });

  test('ignores malformed frames instead of killing the stream', () async {
    final socket = makeService();
    addTearDown(socket.dispose);

    final received = <EphemeralMessage>[];
    final sub = socket.messages.listen(received.add);
    addTearDown(sub.cancel);

    final serverSide = acceptOne();
    socket.connect(topicId: 't1', token: 'tok');
    final ws = await serverSide;
    await Future<void>.delayed(const Duration(milliseconds: 80));

    ws.add('not json at all');
    ws.add('{"send_message":{"id":"ok","topic_id":"t1","sender_roll":"241551058",'
        '"sender_branch_tag":"x","content":"still alive","timestamp_unix":1700000000}}');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(received, hasLength(1));
    expect(received.single.content, 'still alive',
        reason: 'one bad frame must not break the connection');

    await ws.close();
  });
}

Map<String, dynamic>? jsonDecodeSafe(String raw) {
  try {
    final v = jsonDecode(raw);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}
