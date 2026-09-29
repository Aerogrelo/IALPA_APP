import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/change_of_duty/r05.dart';

void main() {
  group('R-05 — Change of duty, Intercontinental, day of operation, at '
      'Base (3.2.4b)', () {
    final originalReport = DateTime(2026, 9, 29, 10, 0);

    test('report 1h earlier complies (green)', () {
      final result = verifyR05(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 9, 0),
      );
      expect(result.color, RuleColor.green);
    });

    test('report 2h later complies (green)', () {
      final result = verifyR05(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 0),
      );
      expect(result.color, RuleColor.green);
    });

    test('report 1h01 earlier does NOT comply (amber)', () {
      final result = verifyR05(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 8, 59),
      );
      expect(result.color, RuleColor.amber);
    });

    test('report 2h01 later does NOT comply (amber)', () {
      final result = verifyR05(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 1),
      );
      expect(result.color, RuleColor.amber);
    });
  });
}
