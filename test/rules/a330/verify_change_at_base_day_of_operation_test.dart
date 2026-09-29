import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a330/change_of_duty/verify_change_at_base_day_of_operation.dart';

void main() {
  group('A330 — Change of duty at base, day of operation (3.2.4)', () {
    final originalReport = DateTime(2026, 9, 29, 10, 0);

    test('1h earlier complies (green)', () {
      final result = verifyChangeAtBaseDayOfOperation(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 9, 0),
      );
      expect(result.color, RuleColor.green);
    });

    test('1h01 earlier does NOT comply (amber)', () {
      final result = verifyChangeAtBaseDayOfOperation(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 8, 59),
      );
      expect(result.color, RuleColor.amber);
    });

    test('4h later complies (green)', () {
      final result = verifyChangeAtBaseDayOfOperation(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 14, 0),
      );
      expect(result.color, RuleColor.green);
    });

    test('4h01 later does NOT comply (amber)', () {
      final result = verifyChangeAtBaseDayOfOperation(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 14, 1),
      );
      expect(result.color, RuleColor.amber);
    });

    test('change to an augmented crew operation: 2h later complies '
        '(green)', () {
      final result = verifyChangeAtBaseDayOfOperation(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 0),
        changeToAugmentedCrewOperation: true,
      );
      expect(result.color, RuleColor.green);
    });

    test('change to an augmented crew operation: 2h01 later does NOT '
        'comply (amber)', () {
      final result = verifyChangeAtBaseDayOfOperation(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 1),
        changeToAugmentedCrewOperation: true,
      );
      expect(result.color, RuleColor.amber);
    });
  });
}
