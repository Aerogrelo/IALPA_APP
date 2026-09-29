import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a330/change_of_duty/verify_change_at_outstation_day_of_operation.dart';

void main() {
  group('A330 — Change of duty at an outstation, day of operation (3.2.9)',
      () {
    final originalReport = DateTime(2026, 9, 29, 10, 0);

    test('not yet reported, 1h earlier complies (green)', () {
      final result = verifyChangeAtOutstationDayOfOperation(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 9, 0),
      );
      expect(result.color, RuleColor.green);
    });

    test('not yet reported, 4h01 later does NOT comply (amber)', () {
      final result = verifyChangeAtOutstationDayOfOperation(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 14, 1),
      );
      expect(result.color, RuleColor.amber);
    });

    test('already reported, 2h later complies (green)', () {
      final result = verifyChangeAtOutstationDayOfOperation(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 0),
        alreadyReported: true,
      );
      expect(result.color, RuleColor.green);
    });

    test('already reported, 2h01 later does NOT comply (amber)', () {
      final result = verifyChangeAtOutstationDayOfOperation(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 1),
        alreadyReported: true,
      );
      expect(result.color, RuleColor.amber);
    });
  });
}
