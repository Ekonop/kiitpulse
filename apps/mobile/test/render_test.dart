import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiit_ui/kiit_ui.dart';
import 'package:kiitpulse/features/chat/presentation/widgets/message_bubble.dart';
import 'package:kiitpulse/features/radar/presentation/widgets/topic_pulse_card.dart';
import 'package:kiitpulse/features/voice_room/presentation/pinned_voice_banner.dart';

/// Layout checks at phone size.
///
/// These are the tests that catch the failures a screenshot review would catch
/// late: RenderFlex overflow, text that does not fit, and an exception thrown
/// during layout.
void main() {
  Widget phone(Widget child) => MaterialApp(
        theme: PulseTheme.darkTheme,
        home: Scaffold(body: child),
      );

  void setPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('topic card renders both shapes without overflow', (tester) async {
    setPhone(tester);

    final quiet = TopicPulse(
      id: 'a',
      title: 'DBMS-PYQ-Drop',
      description:
          'Normalisation and transaction isolation PYQs, 2019-2024, with worked '
          'solutions.',
      zone: CampusZone.campus15,
      velocityScore: 71.4,
      messageCount: 41,
      tag: 'PYQ',
    );
    final live = TopicPulse(
      id: 'b',
      title: 'Campus15-DSA-Viva',
      description:
          'Lab 3 viva questions dropping. B-Tree traversal and graph DFS.',
      zone: CampusZone.campus15,
      velocityScore: 184.2,
      hasActiveVoiceStage: true,
      activeSpeakers: 4,
      activeListeners: 112,
    );

    await tester.pumpWidget(
      phone(
        Column(
          children: [
            TopicPulseCard(topic: quiet, height: 128, onOpen: () {}),
            TopicPulseCard(topic: live, height: 210, onOpen: () {}),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('#DBMS-PYQ-Drop'), findsOneWidget);
    expect(find.text('#Campus15-DSA-Viva'), findsOneWidget);
    expect(find.textContaining('4 speaking'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('message bubble fits a long message', (tester) async {
    setPhone(tester);

    await tester.pumpWidget(
      ProviderScope(
        child: phone(
          MessageBubble(
            message: EphemeralMessage(
              id: 'm1',
              topicId: 't',
              senderRoll: '241551204',
              senderBranchTag: "CSE-AIML '28",
              content:
                  'The viva sheet says B-Tree deletion, graph DFS ordering and '
                  'maybe amortised analysis. Get to Lab 3 early because the '
                  'external is checking attendance this time.',
              timestamp: DateTime.now(),
            ),
            onReact: (_) {},
            onRetry: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('B-Tree deletion'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned voice banner fits without overflow', (tester) async {
    setPhone(tester);

    final topic = TopicPulse(
      id: 'kiit-15-dsa',
      title: 'Campus15-DSA-Viva',
      description: 'Viva questions dropping.',
      zone: CampusZone.campus15,
      velocityScore: 184.2,
      hasActiveVoiceStage: true,
      activeSpeakers: 4,
      activeListeners: 112,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: phone(
          PinnedVoiceBanner(
            topic: topic,
            collapsed: false,
            onToggleCollapsed: () {},
            onExpand: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('LIVE STAGE'), findsOneWidget);
    expect(find.text('RAISE HAND'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
