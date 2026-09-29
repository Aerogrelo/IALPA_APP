import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a330/change_of_duty/verify_change_at_base_with_notice.dart';

void main() {
  group('A330 — Change of duty at base, with 14h notice (3.2.5)', () {
    final originalReport = DateTime(2026, 9, 29, 10, 0);

    test('14h notice, similar duration, within 2h window: complies '
        '(green)', () {
      final result = verifyChangeAtBaseWithNotice(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 0), // +2h
        noticeGiven: const Duration(hours: 14),
        similarDuration: true,
      );
      expect(result.color, RuleColor.green);
    });

    test('13h59 notice does NOT comply (amber)', () {
      final result = verifyChangeAtBaseWithNotice(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 0),
        noticeGiven: const Duration(hours: 13, minutes: 59),
        similarDuration: true,
      );
      expect(result.color, RuleColor.amber);
    });

    test('more than 2h01 earlier without pilot consent does NOT comply '
        '(amber)', () {
      final result = verifyChangeAtBaseWithNotice(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 7, 59), // 2h01 earlier
        noticeGiven: const Duration(hours: 14),
        similarDuration: true,
      );
      expect(result.color, RuleColor.amber);
    });

    test('more than 2h earlier WITH pilot consent complies (green)', () {
      final result = verifyChangeAtBaseWithNotice(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 6, 0), // 4h earlier
        noticeGiven: const Duration(hours: 14),
        similarDuration: true,
        pilotConsents: true,
      );
      expect(result.color, RuleColor.green);
    });

    test('not a duty of similar duration does NOT comply (amber)', () {
      final result = verifyChangeAtBaseWithNotice(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 0),
        noticeGiven: const Duration(hours: 14),
        similarDuration: false,
      );
      expect(result.color, RuleColor.amber);
    });

    test('more than 2h later than the original does NOT comply (amber)',
        () {
      final result = verifyChangeAtBaseWithNotice(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 1), // 2h01 later
        noticeGiven: const Duration(hours: 14),
        similarDuration: true,
      );
      expect(result.color, RuleColor.amber);
    });
  });
}
