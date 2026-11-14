import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiit_ui/kiit_ui.dart';

void main() {
  group('form factor', () {
    test('a phone is compact', () {
      expect(PulseBreakpoints.of(390), PulseFormFactor.compact);
      expect(PulseBreakpoints.of(430), PulseFormFactor.compact);
    });

    test('a tablet or small window is medium', () {
      expect(PulseBreakpoints.of(700), PulseFormFactor.medium);
      expect(PulseBreakpoints.of(1024), PulseFormFactor.medium);
    });

    test('a browser is expanded', () {
      expect(PulseBreakpoints.of(1100), PulseFormFactor.expanded);
      expect(PulseBreakpoints.of(2560), PulseFormFactor.expanded);
    });

    test('the boundaries themselves are not ambiguous', () {
      // 699 is the last compact width, 700 the first medium one.
      expect(PulseBreakpoints.of(699.9), PulseFormFactor.compact);
      expect(PulseBreakpoints.of(700), PulseFormFactor.medium);
      expect(PulseBreakpoints.of(1099.9), PulseFormFactor.medium);
      expect(PulseBreakpoints.of(1100), PulseFormFactor.expanded);
    });

    test('exactly one navigation shape is chosen per width', () {
      for (final width in [320.0, 700.0, 1100.0, 1920.0]) {
        final f = PulseBreakpoints.of(width);
        expect(f.usesBottomNav && f.usesSideRail, isFalse,
            reason: 'both or neither at $width - navigation would duplicate');
        expect(f.usesBottomNav || f.usesSideRail, isTrue,
            reason: 'no navigation at all at $width');
      }
    });
  });

  group('PulseContentColumn', () {
    testWidgets('does not narrow a phone', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PulseContentColumn(
              child: SizedBox(
                key: Key('c'),
                height: 10,
                width: double.infinity,
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const Key('c'))).width, 390,
          reason: 'a phone is already narrower than the cap; adding padding or '
              'a narrower column would break the edge-to-edge look');
    });

    testWidgets('caps the column on a wide window and centres it',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PulseContentColumn(
              child: SizedBox(
                key: Key('c'),
                height: 10,
                width: double.infinity,
              ),
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byKey(const Key('c')));
      expect(size.width, PulseBreakpoints.contentMaxWidth);

      final left = tester.getTopLeft(find.byKey(const Key('c'))).dx;
      final right = tester.getTopRight(find.byKey(const Key('c'))).dx;
      expect((left - (1600 - right)).abs() < 1, isTrue,
          reason: 'the column must be centred, not left-aligned');
    });
  });
}
