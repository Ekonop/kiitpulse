import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kiit_contracts/kiit_contracts.dart';

import 'chat_socket_service.dart';
import 'gateway_exception.dart';
import 'pulse_gateway.dart';

/// Live gateway against the Go backend in `services/backend`.
///
/// REST surface:
///   POST /auth/signin
///   GET  /radar/zones/:zone?limit=50
///   GET  /radar/zones/:zone/population
///   POST /radar/topics
///   GET  /topics/:topicID/messages?limit=
///   POST /voice/token
///   POST /voice/hand-raise
///   GET  /voice/stage/:topicID
///   GET  /passport/:roll
///
/// Chat and radar ticks are pushed over `/ws/topics/:topicID`. Zone-level
/// radar refreshes are polled on demand: a campus zone is a coarse signal and
/// a socket per zone would be wasteful for a screen a student looks at for
/// ten seconds.
///
/// Every timer here is cancellable and every stream is closed on [dispose].
class LiveGateway implements PulseGateway {
  LiveGateway({
    required this.baseUrl,
    required this.sessionProvider,
    this.radarPollInterval = const Duration(seconds: 6),
    this.stagePollInterval = const Duration(seconds: 5),
    this.populationPollInterval = const Duration(seconds: 30),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final Session Function() sessionProvider;
  final Duration radarPollInterval;
  final Duration stagePollInterval;
  final Duration populationPollInterval;
  final http.Client _http;

  final _radarCtrls = <CampusZone, StreamController<List<TopicPulse>>>{};
  final _popCtrls = <CampusZone, StreamController<int>>{};
  final _msgCtrls = <String, StreamController<EphemeralMessage>>{};
  final _stageCtrls = <String, StreamController<List<VoiceParticipant>>>{};

  final _radarTimers = <CampusZone, Timer>{};
  final _popTimers = <CampusZone, Timer>{};
  final _stageTimers = <String, Timer>{};
  final _sockets = <String, ChatSocketService>{};
  final _socketSubs = <String, List<StreamSubscription<dynamic>>>{};
  final _statusCtrls = <String, StreamController<SocketStatus>>{};

  bool _disposed = false;

  Uri _uri(String path, [Map<String, Object?>? query]) {
    final base = Uri.parse('$baseUrl$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(
      queryParameters: query.map((k, v) => MapEntry(k, '$v')),
    );
  }

  Map<String, String> get _headers {
    final token = sessionProvider().token;
    return {
      'content-type': 'application/json',
      if (token.isNotEmpty) 'authorization': 'Bearer $token',
    };
  }

  Never _fail(http.Response res) {
    final retryable = res.statusCode == 429 || res.statusCode >= 500;
    throw GatewayException(
      res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body,
      code: 'HTTP_${res.statusCode}',
      retryable: retryable,
    );
  }

  // ---- Radar -------------------------------------------------------------

  @override
  Stream<List<TopicPulse>> watchRadar(CampusZone zone) {
    final ctrl = _radarCtrls.putIfAbsent(
      zone,
      () => StreamController<List<TopicPulse>>.broadcast(
        onListen: () => _startRadarPolling(zone),
        onCancel: () => _stopRadarPolling(zone),
      ),
    );
    return ctrl.stream;
  }

  void _startRadarPolling(CampusZone zone) {
    _refreshRadar(zone);
    _radarTimers[zone]?.cancel();
    _radarTimers[zone] = Timer.periodic(
      radarPollInterval,
      (_) => _refreshRadar(zone),
    );
  }

  void _stopRadarPolling(CampusZone zone) {
    _radarTimers.remove(zone)?.cancel();
  }

  Future<void> _refreshRadar(CampusZone zone) async {
    final ctrl = _radarCtrls[zone];
    if (_disposed || ctrl == null || ctrl.isClosed) return;
    try {
      final topics = await fetchRadar(zone);
      if (_disposed || ctrl.isClosed) return;
      ctrl.add(topics);
    } on GatewayException catch (e) {
      if (!ctrl.isClosed) ctrl.addError(e);
    } catch (e) {
      if (!ctrl.isClosed) ctrl.addError(e);
    }
  }

  @override
  Future<List<TopicPulse>> fetchRadar(CampusZone zone) async {
    final res = await _http
        .get(_uri('/radar/zones/${zone.key}', {'limit': 50}), headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) _fail(res);
    return List.unmodifiable(
      (jsonDecode(res.body) as List<dynamic>)
          .map((e) => TopicPulse.fromJson(e as Map<String, dynamic>)),
    );
  }

  @override
  Stream<int> watchZonePopulation(CampusZone zone) {
    return _popCtrls
        .putIfAbsent(
          zone,
          () => StreamController<int>.broadcast(
            onListen: () => _startPopulationPolling(zone),
            onCancel: () => _popTimers.remove(zone)?.cancel(),
          ),
        )
        .stream;
  }

  void _startPopulationPolling(CampusZone zone) {
    _refreshPopulation(zone);
    _popTimers[zone]?.cancel();
    _popTimers[zone] = Timer.periodic(
      populationPollInterval,
      (_) => _refreshPopulation(zone),
    );
  }

  Future<void> _refreshPopulation(CampusZone zone) async {
    final ctrl = _popCtrls[zone];
    if (_disposed || ctrl == null || ctrl.isClosed) return;
    try {
      final res = await _http
          .get(_uri('/radar/zones/${zone.key}/population'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final count =
          (jsonDecode(res.body) as Map<String, dynamic>)['count'] as int? ?? 0;
      if (!ctrl.isClosed) ctrl.add(count);
    } catch (_) {
      // Population is decoration; a failed poll must not blank the header.
    }
  }

  @override
  Future<TopicPulse> createTopic({
    required String title,
    required String description,
    required CampusZone zone,
  }) async {
    final res = await _http
        .post(
          _uri('/radar/topics'),
          headers: _headers,
          body: jsonEncode({
            'title': title,
            'description': description,
            'campus_zone': zone.key,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 && res.statusCode != 201) _fail(res);
    return TopicPulse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ---- Chat --------------------------------------------------------------

  ChatSocketService _socketFor(String topicId) {
    final existing = _sockets[topicId];
    // Wire the pump before returning, even for an existing socket: a second
    // caller (the chat controller creates one, the radar another) would
    // otherwise get a socket whose stream nobody forwards, and messages would
    // arrive and vanish.
    final socket = existing ?? _createSocket(topicId);
    _pumpSocket(topicId, socket);
    return socket;
  }

  ChatSocketService _createSocket(String topicId) {
    final socket = ChatSocketService(baseWsUrl: _wsBase);
    _sockets[topicId] = socket;
    socket.connect(topicId: topicId, token: sessionProvider().token);
    return socket;
  }

  /// Forward socket frames into the per-topic broadcast controller. Idempotent:
  /// the subscription is keyed by topic so repeat callers do not fan out twice.
  void _pumpSocket(String topicId, ChatSocketService socket) {
    if (_socketSubs.containsKey(topicId)) return;
    final msgCtrl =
        _msgCtrls.putIfAbsent(topicId, () => StreamController.broadcast());
    _socketSubs[topicId] = [
      socket.messages.listen((m) {
        if (!_disposed && !msgCtrl.isClosed) msgCtrl.add(m);
      }),
      // Surface transport state so the room can show "reconnecting" instead of
      // pretending the conversation is live when the socket is down.
      socket.status.listen((s) {
        final ctrl = _statusCtrls[topicId];
        if (!_disposed && ctrl != null && !ctrl.isClosed) ctrl.add(s);
      }),
    ];
  }

  String get _wsBase {
    if (baseUrl.startsWith('https://')) {
      return baseUrl.replaceFirst('https://', 'wss://');
    }
    if (baseUrl.startsWith('http://')) {
      return baseUrl.replaceFirst('http://', 'ws://');
    }
    return baseUrl;
  }

  @override
  Stream<EphemeralMessage> watchMessages(String topicId) {
    _socketFor(topicId);
    return _msgCtrls
        .putIfAbsent(
          topicId,
          () => StreamController<EphemeralMessage>.broadcast(),
        )
        .stream;
  }

  @override
  Stream<SocketStatus> watchSocketStatus(String topicId) {
    _socketFor(topicId);
    return _statusCtrls
        .putIfAbsent(topicId, () => StreamController<SocketStatus>.broadcast())
        .stream;
  }

  @override
  Future<List<EphemeralMessage>> fetchRecentMessages(
    String topicId, {
    int limit = 50,
  }) async {
    final res = await _http
        .get(
          _uri('/topics/$topicId/messages', {'limit': limit}),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) _fail(res);
    return List.unmodifiable(
      (jsonDecode(res.body) as List<dynamic>)
          .map((e) => EphemeralMessage.fromJson(e as Map<String, dynamic>)),
    );
  }

  /// Fire the message onto the socket and return the optimistic copy.
  ///
  /// The server-acked copy (with the real id) arrives through
  /// [watchMessages]; reconciliation is the repository's job because only it
  /// owns the message list.
  @override
  Future<EphemeralMessage> sendMessage({
    required String topicId,
    required String content,
  }) async {
    final session = sessionProvider();
    final now = DateTime.now();
    final optimistic = EphemeralMessage(
      id: 'local-${now.microsecondsSinceEpoch}',
      topicId: topicId,
      senderRoll: session.rollNumber,
      senderBranchTag: session.branchTag,
      content: content,
      timestamp: now,
      status: MessageStatus.sending,
      clientId: 'local-${now.microsecondsSinceEpoch}',
    );
    _socketFor(topicId).sendMessage(
      topicId: topicId,
      senderRoll: session.rollNumber,
      branchTag: session.branchTag,
      content: content,
      clientId: optimistic.id,
    );
    return optimistic;
  }

  @override
  Future<void> sendReaction({
    required String topicId,
    required String messageId,
    required String emoji,
  }) async {
    _socketFor(topicId).sendReaction(
      topicId: topicId,
      messageId: messageId,
      emoji: emoji,
      senderRoll: sessionProvider().rollNumber,
    );
  }

  // ---- Voice -------------------------------------------------------------

  @override
  Future<StageToken> mintStageToken({
    required String topicId,
    required bool asSpeaker,
  }) async {
    final res = await _http
        .post(
          _uri('/voice/token'),
          headers: _headers,
          body: jsonEncode({'topic_id': topicId, 'as_speaker': asSpeaker}),
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) _fail(res);
    return StageToken.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<void> setHandRaised({
    required String topicId,
    required bool raised,
  }) async {
    final res = await _http
        .post(
          _uri('/voice/hand-raise'),
          headers: _headers,
          body: jsonEncode({'topic_id': topicId, 'raised': raised}),
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 && res.statusCode != 204) _fail(res);
  }

  @override
  Stream<List<VoiceParticipant>> watchStage(String topicId) {
    return _stageCtrls
        .putIfAbsent(
          topicId,
          () => StreamController<List<VoiceParticipant>>.broadcast(
            onListen: () => _startStagePolling(topicId),
            onCancel: () => _stageTimers.remove(topicId)?.cancel(),
          ),
        )
        .stream;
  }

  void _startStagePolling(String topicId) {
    _refreshStage(topicId);
    _stageTimers[topicId]?.cancel();
    _stageTimers[topicId] = Timer.periodic(
      stagePollInterval,
      (_) => _refreshStage(topicId),
    );
  }

  Future<void> _refreshStage(String topicId) async {
    final ctrl = _stageCtrls[topicId];
    if (_disposed || ctrl == null || ctrl.isClosed) return;
    try {
      final res = await _http
          .get(_uri('/voice/stage/$topicId'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final list = (jsonDecode(res.body) as List<dynamic>)
          .map((e) => _participantFromJson(e as Map<String, dynamic>))
          .toList();
      if (!ctrl.isClosed) ctrl.add(List.unmodifiable(list));
    } catch (_) {
      // Stage is presence-only; keep the last known list on a bad poll.
    }
  }

  VoiceParticipant _participantFromJson(Map<String, dynamic> json) =>
      VoiceParticipant(
        identity: json['identity'] as String? ?? '',
        displayRoll: json['roll'] as String? ?? '',
        branchTag: json['branch_tag'] as String? ?? '',
        role: _roleFrom(json['role'] as String?),
        isSpeaking: json['is_speaking'] as bool? ?? false,
        isMuted: json['is_muted'] as bool? ?? true,
      );

  StageRole _roleFrom(String? raw) => switch (raw) {
        'moderator' => StageRole.moderator,
        'speaker' => StageRole.speaker,
        'hand_raised' => StageRole.handRaised,
        _ => StageRole.listener,
      };

  // ---- Passport ----------------------------------------------------------

  @override
  Future<List<FoilBadge>> fetchBadges(String studentRoll) async {
    final res = await _http
        .get(_uri('/passport/$studentRoll'), headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) _fail(res);
    return List.unmodifiable(
      (jsonDecode(res.body) as List<dynamic>)
          .map((e) => FoilBadge.fromJson(e as Map<String, dynamic>)),
    );
  }

  // ---- Session -----------------------------------------------------------

  @override
  Future<Session> signIn(String email) async {
    final res = await _http
        .post(
          _uri('/auth/signin'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 409 || res.statusCode == 403) {
      throw const GatewayException(
        'Only verified @kiit.ac.in student accounts are permitted',
        code: 'KIIT_DOMAIN_REQUIRED',
      );
    }
    if (res.statusCode != 200) _fail(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return Session(
      email: json['email'] as String? ?? email,
      rollNumber: json['roll_number'] as String? ?? '',
      branchTag: json['branch_tag'] as String? ?? 'KIIT Student',
      token: json['token'] as String? ?? '',
      expiresAt: DateTime.now().add(
        Duration(seconds: (json['expires_in'] as num?)?.toInt() ?? 12 * 3600),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _radarTimers.values) {
      t.cancel();
    }
    for (final t in _popTimers.values) {
      t.cancel();
    }
    for (final t in _stageTimers.values) {
      t.cancel();
    }
    for (final subs in _socketSubs.values) {
      for (final s in subs) {
        s.cancel();
      }
    }
    for (final s in _sockets.values) {
      s.dispose();
    }
    for (final c in [
      ..._radarCtrls.values,
      ..._popCtrls.values,
      ..._msgCtrls.values,
      ..._stageCtrls.values,
      ..._statusCtrls.values,
    ]) {
      c.close();
    }
    _http.close();
  }
}
