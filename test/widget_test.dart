// Replaced 29/09: this used to be Flutter's default counter-demo smoke
// test (tap '+', expect the counter to go from 0 to 1), left over from
// `flutter create`. Now that main.dart starts on [FleetSelectionScreen]
// instead of the counter demo, that test no longer applies — replaced with
// a smoke test for the real first screens.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ialpa_app/main.dart';

void main() {
  testWidgets('App starts on the fleet selection screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const IalpaApp());

    expect(find.text('Which fleet do you fly?'), findsOneWidget);
    expect(find.text('A320 / A321 / Neo'), findsOneWidget);
    expect(find.text('A330'), findsOneWidget);
  });

  testWidgets('Tapping a fleet opens the check-type screen, which opens '
      'the max duty input screen', (WidgetTester tester) async {
    await tester.pumpWidget(const IalpaApp());

    await tester.tap(find.text('A320 / A321 / Neo'));
    await tester.pumpAndSettle();

    // 29/09: fleet selection now opens an intermediate check-type screen
    // (Maximum Duty vs Change of Duty) rather than going straight to the
    // max duty form.
    expect(find.text('Maximum Duty'), findsOneWidget);
    expect(find.text('Change of Duty'), findsOneWidget);

    await tester.tap(find.text('Maximum Duty'));
    await tester.pumpAndSettle();

    expect(find.text('Maximum Duty — A320/321'), findsOneWidget);

    // The form is long enough (29/09: added the preceding-standby fields)
    // that the 'Verify' button starts outside the ListView's built
    // viewport — a plain find.text() would report 0 widgets, since
    // ListView only builds what's near-visible. scrollUntilVisible drags
    // the list down step by step until the finder resolves.
    await tester.scrollUntilVisible(
      find.text('Verify'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Verify'), findsOneWidget);
  });

  testWidgets('Tapping a fleet then Change of Duty opens the change of '
      'duty input screen', (WidgetTester tester) async {
    await tester.pumpWidget(const IalpaApp());

    await tester.tap(find.text('A330'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change of Duty'));
    await tester.pumpAndSettle();

    expect(find.text('Change of Duty — A330'), findsOneWidget);
    expect(find.text('At base, day of operation (3.2.4)'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Verify'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Verify'), findsOneWidget);
  });
}
