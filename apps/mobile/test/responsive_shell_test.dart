import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiitpulse/app/app.dart';
import 'package:kiitpulse/core/native/proximity_guard.dart';
import 'package:kiitpulse/features/radar/presentation/radar_providers.dart';

/// The shell presents the same two destinations in a shape that fits the
/// window. Getting this wrong is not cosmetic: a bottom bar on a 27-inch monitor
/// strands navigation in the far corner, disconnected from the content.
void main() {
  // Same harness shape as app_flow_test: the demo gateway and a pinned
  // location, so the shell is reached without a network or a method channel.
  Widget app() => ProviderScope(
        overrides: [
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

  /// The radar has continuously running animations (the pulse dot), so
  /// pumpAndSettle would never return. Pump fixed frames instead.
  Future<void> settle(WidgetTester tester, [int ms = 700]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump(Duration(milliseconds: ms));
  }

  /// Sign in so HomeShell is mounted - the gate itself has no navigation.
  Future<void> signIn(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.enterText(find.byType(TextField), '241551058@kiit.ac.in');
    await tester.tap(find.text('Enter the campus radar'));
    await settle(tester);
  }

  testWidgets('a phone gets a bottom navigation bar', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await signIn(tester);

    expect(find.byKey(const ValueKey('pulse-nav-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('pulse-nav-rail')), findsNothing,
        reason: 'a side rail on a 390px phone would squeeze out the content');
  });

  testWidgets('a wide window gets a side rail', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await signIn(tester);

    expect(find.byKey(const ValueKey('pulse-nav-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('pulse-nav-bar')), findsNothing,
        reason: 'a bottom bar on a desktop wastes the vertical axis');
  });
}
