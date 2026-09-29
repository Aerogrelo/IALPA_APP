import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/rules/a330/max_duty/latest_push_back.dart';

void main() {
  group('A330 — latest push-back time (3.10)', () {
    test('finds the latest push-back that keeps the delayed two-pilot max '
        '(12h + 1h = 13h) green', () {
      // Report fixed clear of the night window (see verify_max_duty_test
      // for why 06:35 is a safe report time). 5h remaining duty duration
      // from push-back onward. delayed:true so the 3.10.1 extension
      // (+1h over the 12h planning limit) applies.
      final duty = Duty(
        report: DateTime(2026, 9, 29, 6, 35),
        end: DateTime(2026, 9, 29, 11, 35), // placeholder, not used directly
        type: DutyType.flight,
      );

      final result = latestPushBackTimeA330(
        duty: duty,
        remainingDutyDuration: const Duration(hours: 5),
        earliestPushBack: DateTime(2026, 9, 29, 6, 35),
        delayed: true,
      );

      // report + 13h (12h planning + 1h delay extension) - 5h remaining
      // = report + 8h = 14:35
      expect(result, DateTime(2026, 9, 29, 14, 35));
    });

    test('returns null when even the earliest push-back already breaches '
        'the maximum', () {
      final duty = Duty(
        report: DateTime(2026, 9, 29, 6, 35),
        end: DateTime(2026, 9, 29, 23, 35),
        type: DutyType.flight,
      );

      final result = latestPushBackTimeA330(
        duty: duty,
        remainingDutyDuration: const Duration(hours: 17), // > any max
        earliestPushBack: DateTime(2026, 9, 29, 6, 35),
        delayed: true,
      );

      expect(result, isNull);
    });
  });
}
