import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a330/change_of_duty/verify_change_after_reporting_at_base.dart';

void main() {
  group('A330 — Change of duty at base, after reporting (3.2.6)', () {
    final originalFinish = DateTime(2026, 9, 29, 18, 0);

    test('2h later complies (green)', () {
      final result = verifyChangeAfterReportingAtBase(
        originalFinish: originalFinish,
        newFinish: DateTime(2026, 9, 29, 20, 0),
      );
      expect(result.color, RuleColor.green);
    });

    test('2h01 later does NOT comply (amber)', () {
      final result = verifyChangeAfterReportingAtBase(
        originalFinish: originalFinish,
        newFinish: DateTime(2026, 9, 29, 20, 1),
      );
      expect(result.color, RuleColor.amber);
    });
  });
}
