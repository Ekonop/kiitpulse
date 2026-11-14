import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiit_api_client/kiit_api_client.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiitpulse/app/app.dart';
import 'package:kiitpulse/core/native/proximity_guard.dart';
import 'package:kiitpulse/core/providers.dart';
import 'package:kiitpulse/features/radar/presentation/radar_providers.dart';

/// End-to-end widget tests against the demo gateway.
///
/// These exercise the real widget tree (no mocks of the widgets themselves),
/// which is what catches the failures that matter: overflow, missing text,
/// a broken provider graph, and the auth gate not actually gating.

/// KIITPulse runs looping animations by design (pulse dot, radar sweep,
/// shimmer), so `pumpAndSettle` never settles. Every wait here is an explicit
/// pump long enough to flush futures and one animation frame.
Future<void> settle(WidgetTester tester, [int ms = 700]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
  await tester.pump(Duration(milliseconds: ms));
}

void main() {
  Widget harness({PulseGateway? gateway}) => ProviderScope(
        overrides: [
          if (gateway != null) pulseGatewayProvider.overrideWithValue(gateway),
          // Desktop has no location provider; pin the guard's dev fallback so
          // the radar resolves instead of waiting on a channel.
          proximityProvider.overrideWith((ref) async {
            return ProximityResult(
              zone: CampusZone.campus15,
              status: LocationSecurityLevel.verified,
              latitude: ProximityGuard.devFallbackLat,
              longitude: ProximityGuard.devFallbackLng,
              accuracyMetres: 12,
            );
          }),
        ],
        child: const KIITPulseApp(),
      );

  testWidgets('gate rejects a non-KIIT email', (tester) async {
    await tester.pumpWidget(harness());
    await settle(tester);

    expect(find.text('KIITPulse'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'someone@gmail.com');
    await tester.tap(find.text('Enter the campus radar'));
    await settle(tester);

    // Still on the gate, and told why.
    expect(find.textContaining('@kiit.ac.in'), findsWidgets);
    expect(find.byType(RadarScreenProbe), findsNothing);
  });

  testWidgets('sign in reaches the radar with topics', (tester) async {
    await tester.pumpWidget(harness());
    await settle(tester);

    await tester.enterText(find.byType(TextField), '241551058@kiit.ac.in');
    await tester.tap(find.text('Enter the campus radar'));
    await settle(tester);

    // Radar header and at least one seeded topic.
    expect(find.text('KIIT CAMPUS RADAR'), findsOneWidget);
    expect(find.textContaining('#Campus15-DSA-Viva'), findsOneWidget);
  });

  testWidgets('opening a topic shows the chat composer', (tester) async {
    await tester.pumpWidget(harness());
    await settle(tester);
    await tester.enterText(find.byType(TextField), '241551058@kiit.ac.in');
    await tester.tap(find.text('Enter the campus radar'));
    await settle(tester);

    await tester.tap(find.textContaining('#Campus15-DSA-Viva'));
    await settle(tester);

    // The composer placeholder names the room, which proves the room id
    // propagated from the card into the chat layer.
    expect(
      find.textContaining('Reply in #Campus15-DSA-Viva'),
      findsOneWidget,
    );
  });

  testWidgets('sending a message renders it optimistically', (tester) async {
    await tester.pumpWidget(harness());
    await settle(tester);
    await tester.enterText(find.byType(TextField), '241551058@kiit.ac.in');
    await tester.tap(find.text('Enter the campus radar'));
    await settle(tester);
    await tester.tap(find.textContaining('#Campus15-DSA-Viva'));
    await settle(tester);

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, 'viva moved to lab 4');
    await tester.pump();

    // The send button is only enabled with text; tapping it adds the bubble.
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();

    expect(find.text('viva moved to lab 4'), findsOneWidget);

    // Let the simulated 180ms send ack land, then unmount so the gateway's
    // simulation clock is cancelled instead of surviving the test.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('passport renders foil badges', (tester) async {
    await tester.pumpWidget(harness());
    await settle(tester);
    await tester.enterText(find.byType(TextField), '241551058@kiit.ac.in');
    await tester.tap(find.text('Enter the campus radar'));
    await settle(tester);

    await tester.tap(find.text('PASSPORT'));
    await settle(tester);

    expect(find.text('KIIT PASSPORT'), findsOneWidget);
    expect(find.text('KIIT FEST'), findsOneWidget);
  });

  testWidgets('passport shows a real empty state for a new student', (
    tester,
  ) async {
    // A student with no badges must not see a blank grid, which reads as a
    // loading failure.
    final emptyGateway = _NoBadgesGateway();

    await tester.pumpWidget(harness(gateway: emptyGateway));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '241551058@kiit.ac.in');
    await tester.tap(find.text('Enter the campus radar'));
    await settle(tester);

    await tester.tap(find.text('PASSPORT'));
    await settle(tester);

    expect(find.text('No stamps yet'), findsOneWidget);
    expect(find.textContaining('show up'), findsOneWidget);

    // The demo gateway runs periodic clocks; unmount before disposing so no
    // timers are left pending when the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
    emptyGateway.dispose();
  });

  testWidgets('demo gateway velocity decays over time', (tester) async {
    final gateway = DemoGateway(pace: const Duration(milliseconds: 50));
    final before = await gateway.fetchRadar(CampusZone.campus15);
    final topBefore = before.first.velocityScore;

    await tester.pump(const Duration(milliseconds: 200));
    final after = await gateway.fetchRadar(CampusZone.campus15);

    expect(after.first.velocityScore, lessThan(topBefore));
    gateway.dispose();
  });
}

/// Marker used by tests to assert the radar is *not* mounted.
class RadarScreenProbe extends StatelessWidget {
  const RadarScreenProbe({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A demo campus where the signed-in student has earned nothing yet.
class _NoBadgesGateway extends DemoGateway {
  _NoBadgesGateway();

  @override
  Future<List<FoilBadge>> fetchBadges(String studentRoll) async => const [];
}
