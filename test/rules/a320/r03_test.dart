import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/change_of_duty/r03.dart';

void main() {
  group('R-03 — Change to a standby duty (3.2.3c)', () {
    final originalFlightReport = DateTime(2026, 9, 29, 10, 0);

    test('standby 1h earlier complies (green)', () {
      final result = verifyR03(
        originalFlightReport: originalFlightReport,
        newStandbyStart: DateTime(2026, 9, 29, 9, 0),
      );
      expect(result.color, RuleColor.green);
    });

    test('standby 1h01 earlier does NOT comply (amber)', () {
      final result = verifyR03(
        originalFlightReport: originalFlightReport,
        newStandbyStart: DateTime(2026, 9, 29, 8, 59),
      );
      expect(result.color, RuleColor.amber);
    });

    test('standby 1h01 later does NOT comply (amber)', () {
      final result = verifyR03(
        originalFlightReport: originalFlightReport,
        newStandbyStart: DateTime(2026, 9, 29, 11, 1),
      );
      expect(result.color, RuleColor.amber);
    });
  });
}
