import 'dart:async';
import 'dart:math' as math;

import 'package:kiit_contracts/kiit_contracts.dart';

import 'chat_socket_service.dart';
import 'pulse_gateway.dart';

/// A fully simulated campus.
///
/// This is not a stub. It runs the same velocity maths as the server, decays
/// topics on a timer, generates plausible student chatter, keeps a presence
/// count per zone and moves voice stages through speaker changes. That makes
/// the Radar read as alive and lets the UI be reviewed before the Go service
/// exists - and it doubles as the fixture for widget tests.
///
/// Everything is driven by a seeded [math.Random], so a test run is repeatable.
class DemoGateway implements PulseGateway {
  DemoGateway({int seed = 20260114, this.pace = const Duration(seconds: 4)})
      : _rng = math.Random(seed) {
    _seedTopics();
    _startClock();
  }

  final math.Random _rng;

  /// How often the simulation ticks (score decay + new chatter).
  final Duration pace;

  final Map<CampusZone, List<TopicPulse>> _radar = {};
  final Map<String, List<EphemeralMessage>> _messages = {};
  final Map<String, StreamController<List<VoiceParticipant>>> _stageCtrls = {};
  final Map<String, List<VoiceParticipant>> _stageState = {};

  final Map<CampusZone, StreamController<List<TopicPulse>>> _radarCtrls = {};
  final Map<CampusZone, StreamController<int>> _popCtrls = {};
  final Map<String, StreamController<EphemeralMessage>> _msgCtrls = {};

  final Map<CampusZone, int> _population = {
    CampusZone.campus15: 420,
    CampusZone.ksac: 168,
    CampusZone.kpHostels: 312,
    CampusZone.foodCourt: 96,
    CampusZone.campus6and7: 241,
    CampusZone.kims: 84,
    CampusZone.offCampus: 0,
    CampusZone.unspecified: 0,
  };

  Timer? _clock;
  Timer? _chatter;
  int _seq = 0;

  static const _rolls = [
    '241551058', '241550912', '241551204', '240503188',
    '240601477', '230501902', '241552310', '241553005',
  ];
  static const _branches = [
    'CSE-AIML \'28', 'CSE \'28', 'IT \'28', 'CSE \'27', 'ECE \'28',
  ];
  static const _chatterLines = [
    'B-Tree deletions are definitely coming, prof just hinted at it',
    'PYQ 2023 with solutions is in the shared drive, filing name is PAPER_2023',
    'who has the viva sheet from Lab 3? guessing DFS ordering',
    'mess closes at 9:30 today, moved from 10',
    'wifi in KP7 block B keeps dropping, raising a ticket',
    'team of 3 looking for a backend person for K1000',
    'auditorium 2 filling up, get here early',
    'anyone else stuck on the aggregation nesting in Q4',
    'senior from batch 22 is on the stage, worth listening',
    'slides uploaded, check the Drive link in the pinned message',
  ];

  // ---------------------------------------------------------------------
  // Radar
  // ---------------------------------------------------------------------

  @override
  Stream<List<TopicPulse>> watchRadar(CampusZone zone) {
    final ctrl = _radarCtrls.putIfAbsent(
      zone,
      () => StreamController<List<TopicPulse>>.broadcast(
        onListen: () => _emitRadar(zone),
      ),
    );
    return ctrl.stream;
  }

  @override
  Future<List<TopicPulse>> fetchRadar(CampusZone zone) async =>
      List.unmodifiable(_radar[zone] ?? const <TopicPulse>[]);

  @override
  Stream<int> watchZonePopulation(CampusZone zone) {
    return _popCtrls
        .putIfAbsent(
          zone,
          () => StreamController<int>.broadcast(
            onListen: () => _emitPopulation(zone),
          ),
        )
        .stream;
  }

  void _emitPopulation(CampusZone zone) {
    final ctrl = _popCtrls[zone];
    if (ctrl == null || ctrl.isClosed) return;
    ctrl.add(_population[zone] ?? 0);
  }

  @override
  Future<TopicPulse> createTopic({
    required String title,
    required String description,
    required CampusZone zone,
  }) async {
    final topic = TopicPulse(
      id: 'local-${++_seq}',
      title: title,
      description: description,
      zone: zone,
      velocityScore: Velocity.rawScore(messages: 1, reactions: 0, voiceJoins: 0),
      messageCount: 1,
      createdAt: DateTime.now(),
      lastActivityAt: DateTime.now(),
      tag: 'NEW',
    );
    (_radar[zone] ??= []).insert(0, topic);
    _emitRadar(zone);
    return topic;
  }

  // ---------------------------------------------------------------------
  // Chat
  // ---------------------------------------------------------------------

  @override
  Stream<EphemeralMessage> watchMessages(String topicId) {
    return _msgCtrls
        .putIfAbsent(
          topicId,
          () => StreamController<EphemeralMessage>.broadcast(),
        )
        .stream;
  }

  /// The demo has no transport, so it never reports a status. The room treats
  /// an empty status stream as "assume live", which is correct here: the
  /// in-memory gateway cannot disconnect.
  @override
  Stream<SocketStatus> watchSocketStatus(String topicId) =>
      const Stream<SocketStatus>.empty();

  @override
  Future<List<EphemeralMessage>> fetchRecentMessages(
    String topicId, {
    int limit = 50,
  }) async {
    final all = _messages[topicId] ??= _seedMessages(topicId);
    final slice =
        all.length <= limit ? all : all.sublist(all.length - limit);
    return List.unmodifiable(slice);
  }

  @override
  Future<EphemeralMessage> sendMessage({
    required String topicId,
    required String content,
  }) async {
    // Small, honest latency: the optimistic UI path gets exercised.
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final msg = EphemeralMessage(
      id: 'm-${++_seq}',
      topicId: topicId,
      senderRoll: _selfRoll,
      senderBranchTag: _selfBranch,
      content: content,
      timestamp: DateTime.now(),
    );
    (_messages[topicId] ??= <EphemeralMessage>[]).add(msg);
    _msgCtrls[topicId]?.add(msg);
    _bumpVelocity(topicId, VelocityEventKind.message);
    return msg;
  }

  @override
  Future<void> sendReaction({
    required String topicId,
    required String messageId,
    required String emoji,
  }) async {
    _bumpVelocity(topicId, VelocityEventKind.reaction);
  }

  // ---------------------------------------------------------------------
  // Voice
  // ---------------------------------------------------------------------

  @override
  Future<StageToken> mintStageToken({
    required String topicId,
    required bool asSpeaker,
  }) async {
    if (_stageState[topicId] == null) _seedStage(topicId);
    if (asSpeaker) {
      _stageState[topicId] = [
        ..._stageState[topicId]!,
        VoiceParticipant(
          identity: _selfRoll,
          displayRoll: _selfRoll,
          branchTag: _selfBranch,
          role: StageRole.speaker,
          isMuted: true,
          joinedAt: DateTime.now(),
        ),
      ];
      _stageCtrls[topicId]?.add(_stageState[topicId]!);
      _bumpVelocity(topicId, VelocityEventKind.voiceJoin);
    }
    return StageToken(
      token: 'demo.${asSpeaker ? 'speaker' : 'listener'}',
      wsUrl: 'wss://demo.livekit.invalid',
      room: StageToken.roomFor(topicId),
    );
  }

  @override
  Future<void> setHandRaised({
    required String topicId,
    required bool raised,
  }) async {
    final stage = _stageState[topicId];
    if (stage == null) return;
    final idx = stage.indexWhere((p) => p.identity == _selfRoll);
    if (idx >= 0) {
      stage[idx] = stage[idx].copyWith(
        role: raised ? StageRole.handRaised : StageRole.listener,
      );
      _stageCtrls[topicId]?.add(List.unmodifiable(stage));
    }
  }

  @override
  Stream<List<VoiceParticipant>> watchStage(String topicId) {
    if (_stageState[topicId] == null) _seedStage(topicId);
    return _stageCtrls
        .putIfAbsent(
          topicId,
          () => StreamController<List<VoiceParticipant>>.broadcast(
            onListen: () => _emitStage(topicId),
          ),
        )
        .stream;
  }

  /// Replace the local speaker's role in a stage (used by promotion tests and
  /// by the demo to let the UI see a granted hand raise).
  void simulatePromotion(String topicId, String roll) {
    final stage = _stageState[topicId];
    if (stage == null) return;
    final idx = stage.indexWhere((p) => p.displayRoll == roll);
    if (idx < 0) return;
    stage[idx] = stage[idx].copyWith(
      role: StageRole.speaker,
      isMuted: false,
      isSpeaking: true,
    );
    _emitStage(topicId);
  }

  // ---------------------------------------------------------------------
  // Passport
  // ---------------------------------------------------------------------

  @override
  Future<List<FoilBadge>> fetchBadges(String studentRoll) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final now = DateTime.now();
    return [
      FoilBadge(
        id: 'b-kiitfest',
        studentRoll: studentRoll,
        type: 'KIIT_FEST',
        label: 'KIIT Fest',
        eventName: 'KIIT Fest 2026 · Core Team',
        issuedAt: now.subtract(const Duration(days: 61)),
        signature: 'demo-sig-kiitfest',
        accentArgb: 0xFF00C853,
      ),
      FoilBadge(
        id: 'b-kritarth',
        studentRoll: studentRoll,
        type: 'KRITARTH',
        label: 'Kritarth',
        eventName: 'Kritarth 7.0 · Volunteer',
        issuedAt: now.subtract(const Duration(days: 128)),
        signature: 'demo-sig-kritarth',
        accentArgb: 0xFF00B0FF,
      ),
      FoilBadge(
        id: 'b-cybervault',
        studentRoll: studentRoll,
        type: 'CYBERVAULT',
        label: 'CyberVault',
        eventName: 'CyberVault CTF · Top 20',
        issuedAt: now.subtract(const Duration(days: 22)),
        signature: 'demo-sig-cybervault',
        accentArgb: 0xFFFF4D4D,
      ),
      FoilBadge(
        id: 'b-hacknight',
        studentRoll: studentRoll,
        type: 'HACKNIGHT',
        label: 'K1000 HackNight',
        eventName: 'K1000 HackNight · Speaker',
        issuedAt: now.subtract(const Duration(days: 9)),
        signature: 'demo-sig-hacknight',
        accentArgb: 0xFFFFB300,
      ),
    ];
  }

  // ---------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------

  @override
  Future<Session> signIn(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    final clean = email.trim().toLowerCase();
    final roll = clean.split('@').first;
    _selfRoll = roll.toUpperCase();
    _selfBranch = branchTagFor(roll);
    return Session(
      email: clean,
      rollNumber: _selfRoll,
      branchTag: _selfBranch,
      token: 'demo-session-$roll',
      expiresAt: DateTime.now().add(const Duration(hours: 12)),
    );
  }

  String _selfRoll = '241551058';
  String _selfBranch = 'CSE-AIML \'28';

  /// Roll-number to programme tag. Exposed so the auth guard and the demo
  /// share one implementation instead of drifting apart.
  static String branchTagFor(String roll) {
    final r = roll.trim();
    if (r.startsWith('24155')) return 'CSE-AIML \'28';
    if (r.startsWith('24156')) return 'IT \'28';
    if (r.startsWith('2405')) return 'CSE \'28';
    if (r.startsWith('2406')) return 'IT \'28';
    if (r.startsWith('2305')) return 'CSE \'27';
    if (r.startsWith('2306')) return 'IT \'27';
    if (r.startsWith('22')) return 'Senior';
    return 'KIIT Student';
  }

  // ---------------------------------------------------------------------
  // Simulation
  // ---------------------------------------------------------------------

  void _startClock() {
    _clock = Timer.periodic(pace, (_) {
      for (final zone in _radar.keys.toList()) {
        final list = _radar[zone]!;
        for (var i = 0; i < list.length; i++) {
          final t = list[i];
          final decayed = t.copyWith(
            velocityScore: math.max(0.0, t.velocityScore * 0.985),
            lastActivityAt: DateTime.now(),
          );
          list[i] = decayed;
        }
        _emitRadar(zone);
      }
    });

    _chatter = Timer.periodic(pace * 2, (_) {
      final zones = _radar.keys.where((z) => z.isPhysical).toList();
      if (zones.isEmpty) return;
      final zone = zones[_rng.nextInt(zones.length)];
      final topics = _radar[zone] ?? const <TopicPulse>[];
      if (topics.isEmpty) return;
      final topic = topics[_rng.nextInt(topics.length)];
      final msg = EphemeralMessage(
        id: 'm-${++_seq}',
        topicId: topic.id,
        senderRoll: _rolls[_rng.nextInt(_rolls.length)],
        senderBranchTag: _branches[_rng.nextInt(_branches.length)],
        content: _chatterLines[_rng.nextInt(_chatterLines.length)],
        timestamp: DateTime.now(),
      );
      final list = _messages[topic.id] ??= _seedMessages(topic.id);
      list.add(msg);
      _msgCtrls[topic.id]?.add(msg);
    });
  }

  void _bumpVelocity(String topicId, VelocityEventKind kind) {
    for (final entry in _radar.entries) {
      final list = entry.value;
      final idx = list.indexWhere((t) => t.id == topicId);
      if (idx == -1) continue;
      list[idx] = list[idx].copyWith(
        velocityScore: Velocity.withEvent(list[idx].velocityScore, kind: kind),
        messageCount: list[idx].messageCount +
            (kind == VelocityEventKind.message ? 1 : 0),
      );
      _emitRadar(entry.key);
      return;
    }
  }

  void _emitRadar(CampusZone zone) {
    final ctrl = _radarCtrls[zone];
    if (ctrl == null || ctrl.isClosed) return;
    final list = [...?_radar[zone]]
      ..sort((a, b) => b.velocityScore.compareTo(a.velocityScore));
    ctrl.add(List.unmodifiable(list));
    _emitPopulation(zone);
  }

  void _emitStage(String topicId) {
    final ctrl = _stageCtrls[topicId];
    if (ctrl == null || ctrl.isClosed) return;
    ctrl.add(List.unmodifiable(_stageState[topicId] ?? const []));
  }

  TopicPulse _topic({
    required String id,
    required String title,
    required String description,
    required CampusZone zone,
    required double velocity,
    required int messages,
    bool live = false,
    int speakers = 0,
    int listeners = 0,
    String? tag,
  }) =>
      TopicPulse(
        id: id,
        title: title,
        description: description,
        zone: zone,
        velocityScore: velocity,
        messageCount: messages,
        hasActiveVoiceStage: live,
        activeSpeakers: speakers,
        activeListeners: listeners,
        createdAt: DateTime.now().subtract(
          Duration(minutes: messages * 2 + 10),
        ),
        lastActivityAt: DateTime.now(),
        tag: tag,
      );

  void _seedTopics() {
    _radar[CampusZone.campus15] = [
      _topic(
        id: 'kiit-15-dsa',
        title: 'Campus15-DSA-Viva',
        description:
            'Lab 3 viva questions dropping. B-Tree traversal and graph DFS are '
            'what faculty are asking this round.',
        zone: CampusZone.campus15,
        velocity: 184.2,
        messages: 96,
        live: true,
        speakers: 4,
        listeners: 112,
        tag: 'EXAM',
      ),
      _topic(
        id: 'c15-dbms-pyq',
        title: 'DBMS-PYQ-Drop',
        description:
            'Normalisation and transaction isolation PYQs, 2019-2024, with worked '
            'solutions. Filing name PAPER_DBMS.',
        zone: CampusZone.campus15,
        velocity: 71.4,
        messages: 41,
        tag: 'PYQ',
      ),
      _topic(
        id: 'c15-os-labs',
        title: 'OS-Lab-Viva',
        description:
            'Deadlock detection and paging questions from today\'s slot, plus '
            'what the external examiner asked last semester.',
        zone: CampusZone.campus15,
        velocity: 33.8,
        messages: 22,
        tag: 'EXAM',
      ),
      _topic(
        id: 'c15-k1000-teams',
        title: 'K1000-Team-Forming',
        description:
            'Looking for one backend and one design person for K1000. Have two '
            'Flutter devs already.',
        zone: CampusZone.campus15,
        velocity: 12.1,
        messages: 8,
        tag: 'TEAM',
      ),
    ];

    _radar[CampusZone.ksac] = [
      _topic(
        id: 'ksac-hack-1000',
        title: 'KSAC-K1000-HackNight',
        description:
            'CyberVault and GFG Student Chapter live jam at Auditorium 2. Team '
            'formation for the 24 hour hackathon is open on stage.',
        zone: CampusZone.ksac,
        velocity: 128.5,
        messages: 64,
        live: true,
        speakers: 2,
        listeners: 65,
        tag: 'EVENT',
      ),
      _topic(
        id: 'ksac-auditions',
        title: 'Society-Auditions',
        description:
            'Music and dramatics auditions moved to Friday 5pm. Bring your own '
            'backing track if you have one.',
        zone: CampusZone.ksac,
        velocity: 46.2,
        messages: 19,
        tag: 'EVENT',
      ),
      _topic(
        id: 'ksac-gym-slots',
        title: 'KSAC-Gym-Timings',
        description:
            'New 6am slot opened, capacity 40. Sign-up sheet at the front desk.',
        zone: CampusZone.ksac,
        velocity: 8.4,
        messages: 5,
      ),
    ];

    _radar[CampusZone.kpHostels] = [
      _topic(
        id: 'kp7-mess',
        title: 'KP7-Mess-Update',
        description:
            'Special dinner menu tonight plus a thread on the Wi-Fi latency '
            'fixes the warden promised.',
        zone: CampusZone.kpHostels,
        velocity: 74.0,
        messages: 53,
        tag: 'HOSTEL',
      ),
      _topic(
        id: 'kp7-wifi',
        title: 'KP7-Wifi-Down',
        description:
            'Block B has been dropping every 10 minutes since 4pm. Ticket '
            'raised, post your room number if you are affected.',
        zone: CampusZone.kpHostels,
        velocity: 39.6,
        messages: 27,
        live: true,
        speakers: 1,
        listeners: 34,
        tag: 'HOSTEL',
      ),
      _topic(
        id: 'qc-laundry',
        title: 'QC-Laundry-Slot',
        description: 'Machine 3 is stuck mid-cycle again, use 1 and 2.',
        zone: CampusZone.kpHostels,
        velocity: 5.7,
        messages: 4,
      ),
    ];

    _radar[CampusZone.foodCourt] = [
      _topic(
        id: 'fc-late-night',
        title: 'FoodCourt-LateNight',
        description:
            'Which counter is still open past 11? Nescafe closes at 11:30 now.',
        zone: CampusZone.foodCourt,
        velocity: 57.3,
        messages: 31,
        tag: 'FOOD',
      ),
      _topic(
        id: 'fc-momo',
        title: 'Momo-Counter-Queue',
        description: 'Queue is 15 deep, come after 3.',
        zone: CampusZone.foodCourt,
        velocity: 16.9,
        messages: 11,
      ),
    ];

    _radar[CampusZone.campus6and7] = [
      _topic(
        id: 'c67-placement',
        title: 'Placement-Briefing',
        description:
            'Pre-placement talk at 2pm in Campus 6 auditorium. Resume'
            ' shortlist goes out tonight.',
        zone: CampusZone.campus6and7,
        velocity: 96.8,
        messages: 48,
        live: true,
        speakers: 3,
        listeners: 88,
        tag: 'CAREER',
      ),
      _topic(
        id: 'c67-seminar',
        title: 'Guest-Seminar-Notes',
        description:
            'Notes from the distributed systems guest talk, shared as a PDF.',
        zone: CampusZone.campus6and7,
        velocity: 21.4,
        messages: 13,
      ),
    ];

    _radar[CampusZone.kims] = [
      _topic(
        id: 'kims-blood',
        title: 'KIMS-Blood-Drive',
        description: 'O+ needed today, walk-in at the KIMS lobby until 6pm.',
        zone: CampusZone.kims,
        velocity: 42.0,
        messages: 17,
        tag: 'HELP',
      ),
    ];
  }

  List<EphemeralMessage> _seedMessages(String topicId) {
    final now = DateTime.now();
    final count = 14 + _rng.nextInt(10);
    return List.generate(count, (i) {
      final roll = _rolls[_rng.nextInt(_rolls.length)];
      return EphemeralMessage(
        id: '$topicId-seed-$i',
        topicId: topicId,
        senderRoll: roll,
        senderBranchTag: _branches[_rng.nextInt(_branches.length)],
        content: _chatterLines[_rng.nextInt(_chatterLines.length)],
        timestamp: now.subtract(Duration(minutes: (count - i) * 3)),
      );
    });
  }

  void _seedStage(String topicId) {
    final people = <VoiceParticipant>[];
    final speakerCount = 2 + _rng.nextInt(3);
    for (var i = 0; i < speakerCount; i++) {
      final roll = _rolls[_rng.nextInt(_rolls.length)];
      people.add(
        VoiceParticipant(
          identity: roll,
          displayRoll: roll,
          branchTag: _branches[_rng.nextInt(_branches.length)],
          role: i == 0 ? StageRole.moderator : StageRole.speaker,
          isSpeaking: i == 0,
          isMuted: false,
          joinedAt: DateTime.now().subtract(Duration(minutes: 4 + i)),
        ),
      );
    }
    _stageState[topicId] = people;
  }

  @override
  void dispose() {
    _clock?.cancel();
    _chatter?.cancel();
    for (final c in _radarCtrls.values) {
      c.close();
    }
    for (final c in _popCtrls.values) {
      c.close();
    }
    for (final c in _msgCtrls.values) {
      c.close();
    }
    for (final c in _stageCtrls.values) {
      c.close();
    }
  }
}
