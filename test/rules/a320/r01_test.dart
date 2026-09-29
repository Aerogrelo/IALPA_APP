import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/change_of_duty/r01.dart';

void main() {
  group('R-01 — Change of duty, Continental, day of operation, at Base '
      '(3.2.3a)', () {
    final originalReport = DateTime(2026, 9, 29, 10, 0);
    final originalFinish = DateTime(2026, 9, 29, 18, 0);

    test('report 1h earlier, finish 2h later complies (green)', () {
      final result = verifyR01(
        originalReport: originalReport,
        originalFinish: originalFinish,
        newReport: DateTime(2026, 9, 29, 9, 0),
        newFinish: DateTime(2026, 9, 29, 20, 0),
      );
      expect(result.color, RuleColor.green);
    });

    test('report 1h01 earlier does NOT comply (amber)', () {
      final result = verifyR01(
        originalReport: originalReport,
        originalFinish: originalFinish,
        newReport: DateTime(2026, 9, 29, 8, 59),
        newFinish: originalFinish,
      );
      expect(result.color, RuleColor.amber);
    });

    test('finish 2h01 later does NOT comply (amber)', () {
      final result = verifyR01(
        originalReport: originalReport,
        originalFinish: originalFinish,
        newReport: originalReport,
        newFinish: DateTime(2026, 9, 29, 20, 1),
      );
      expect(result.color, RuleColor.amber);
    });

    test('finish 90 min later complies and notes the OWC payment', () {
      final result = verifyR01(
        originalReport: originalReport,
        originalFinish: originalFinish,
        newReport: originalReport,
        newFinish: DateTime(2026, 9, 29, 19, 30),
      );
      expect(result.color, RuleColor.green);
      expect(result.explanation, contains('OWC payment'));
    });
  });
}
