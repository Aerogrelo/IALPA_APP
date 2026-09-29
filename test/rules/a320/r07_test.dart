import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/change_of_duty/r07.dart';

void main() {
  group('R-07 — Change of duty, Intercontinental, day of operation, at '
      'Outstation (3.2.4f)', () {
    final originalReport = DateTime(2026, 9, 29, 10, 0);

    test('not yet reported, 1h earlier complies (green)', () {
      final result = verifyR07(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 9, 0),
      );
      expect(result.color, RuleColor.green);
    });

    test('not yet reported, 4h01 later does NOT comply (amber)', () {
      final result = verifyR07(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 14, 1),
      );
      expect(result.color, RuleColor.amber);
    });

    test('already reported, 2h later complies (green)', () {
      final result = verifyR07(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 0),
        alreadyReported: true,
      );
      expect(result.color, RuleColor.green);
    });

    test('already reported, 2h01 later does NOT comply (amber)', () {
      final result = verifyR07(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 1),
        alreadyReported: true,
      );
      expect(result.color, RuleColor.amber);
    });
  });
}
