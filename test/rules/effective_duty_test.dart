import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/rules/a320/max_duty/effective_duty.dart';

void main() {
  group('effectiveFlightDutyTime (3.17.2c, 50% STBH rule)', () {
    test('with no preceding STBH, effective duty equals actual duty', () {
      final duty = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 18, 0), // 10h
        type: DutyType.flight,
      );
      expect(effectiveFlightDutyTime(duty), const Duration(hours: 10));
    });

    test('with a preceding STBH portion, only half of it counts', () {
      final duty = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 18, 0), // 10h
        type: DutyType.flight,
      );
      final effective = effectiveFlightDutyTime(
        duty,
        stbhPortion: const Duration(hours: 2), // counts as 1h
      );
      expect(effective, const Duration(hours: 11));
    });
  });

  group('effectiveFlightDutyTime (2.16.1b, 100% STBA rule)', () {
    test('with a preceding STBA portion, all of it counts', () {
      final duty = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 18, 0), // 10h
        type: DutyType.flight,
      );
      final effective = effectiveFlightDutyTime(
        duty,
        stbaPortion: const Duration(hours: 2), // counts as 2h, not 1h
      );
      expect(effective, const Duration(hours: 12));
    });

    test('STBA counts double what the same portion of STBH would', () {
      final duty = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 18, 0),
        type: DutyType.flight,
      );
      final withStbh = effectiveFlightDutyTime(
        duty,
        stbhPortion: const Duration(hours: 2),
      );
      final withStba = effectiveFlightDutyTime(
        duty,
        stbaPortion: const Duration(hours: 2),
      );
      expect(withStba - duty.duration, (withStbh - duty.duration) * 2);
    });
  });
}
