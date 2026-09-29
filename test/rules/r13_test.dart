import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/rest/r13.dart';

void main() {
  group('R-13 — Unscheduled Overnights (3.14.4)', () {
    test('no meal provided: minimum stays at the base value (red below it)',
        () {
      final result = verifyR13(
        baseMinimumRest: const Duration(hours: 12),
        mealProvidedOnGround: false,
        plannedRest: const Duration(hours: 11, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('no meal provided: minimum stays at the base value (green at it)',
        () {
      final result = verifyR13(
        baseMinimumRest: const Duration(hours: 12),
        mealProvidedOnGround: false,
        plannedRest: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.green);
    });

    test(
        'meal provided on the ground: base minimum is reduced by 1h (red '
        'just below the reduced minimum)', () {
      final result = verifyR13(
        baseMinimumRest: const Duration(hours: 12),
        mealProvidedOnGround: true,
        plannedRest: const Duration(hours: 10, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test(
        'meal provided on the ground: base minimum is reduced by 1h (green '
        'at the reduced minimum)', () {
      final result = verifyR13(
        baseMinimumRest: const Duration(hours: 12),
        mealProvidedOnGround: true,
        plannedRest: const Duration(hours: 11),
      );
      expect(result.color, RuleColor.green);
    });
  });
}
