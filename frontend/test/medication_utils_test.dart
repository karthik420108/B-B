import 'package:flutter_test/flutter_test.dart';

import 'package:health_wallet/core/utils/medication_utils.dart';

void main() {
  group('time validation + formatting', () {
    test('accepts 24-hour times and rejects bad ones', () {
      expect(isValidTime('00:00'), isTrue);
      expect(isValidTime('08:30'), isTrue);
      expect(isValidTime('23:59'), isTrue);
      expect(isValidTime('24:00'), isFalse);
      expect(isValidTime('8:30'), isFalse);
      expect(isValidTime('08:60'), isFalse);
      expect(isValidTime('abc'), isFalse);
    });

    test('formats 12-hour labels', () {
      expect(formatTime12h('08:00'), '8:00 AM');
      expect(formatTime12h('13:05'), '1:05 PM');
      expect(formatTime12h('00:00'), '12:00 AM');
      expect(formatTime12h('12:00'), '12:00 PM');
      expect(clockLabel(DateTime(2026, 1, 1, 20, 30)), '8:30 PM');
    });

    test('sorts reminder times when building a label', () {
      expect(scheduleTimesLabel(['20:00', '08:00']), '8:00 AM, 8:00 PM');
      expect(scheduleTimesLabel([]), 'No reminder times');
    });
  });

  group('frequency helpers', () {
    test('maps labels to required time counts', () {
      expect(frequencyRequiredTimes('once_daily'), 1);
      expect(frequencyRequiredTimes('twice_daily'), 2);
      expect(frequencyRequiredTimes('three_times_daily'), 3);
      expect(frequencyRequiredTimes('custom'), isNull);
    });

    test('labels frequencies', () {
      expect(frequencyLabel('twice_daily'), 'Twice daily');
      expect(frequencyLabel('custom'), 'Custom schedule');
    });
  });

  group('weekday labels', () {
    test('describes common sets', () {
      expect(weekdaysLabel([]), 'Every day');
      expect(weekdaysLabel([1, 2, 3, 4, 5]), 'Weekdays');
      expect(weekdaysLabel([0, 6]), 'Weekends');
      expect(weekdaysLabel([1, 3]), 'Mon, Wed');
    });
  });

  group('relativeDoseLabel', () {
    test('describes upcoming and overdue doses', () {
      final now = DateTime(2026, 1, 1, 12, 0);
      expect(relativeDoseLabel(DateTime(2026, 1, 1, 14, 15), now: now), 'in 2h 15m');
      expect(relativeDoseLabel(DateTime(2026, 1, 1, 11, 30), now: now), '30m overdue');
      expect(relativeDoseLabel(DateTime(2026, 1, 1, 12, 0), now: now), 'due now');
    });
  });

  group('validateScheduleDraft', () {
    final start = DateTime(2026, 1, 1);

    test('accepts a valid once-daily draft', () {
      expect(
        validateScheduleDraft(name: 'Metformin', times: ['08:00'], frequency: 'once_daily', startDate: start, endDate: null),
        isNull,
      );
    });

    test('flags the first problem it finds', () {
      expect(
        validateScheduleDraft(name: '  ', times: ['08:00'], frequency: 'once_daily', startDate: start, endDate: null),
        contains('name'),
      );
      expect(
        validateScheduleDraft(name: 'A', times: [], frequency: 'once_daily', startDate: start, endDate: null),
        contains('at least one'),
      );
      expect(
        validateScheduleDraft(name: 'A', times: ['08:00', '08:00'], frequency: 'custom', startDate: start, endDate: null),
        contains('unique'),
      );
      expect(
        validateScheduleDraft(name: 'A', times: ['08:00'], frequency: 'twice_daily', startDate: start, endDate: null),
        contains('exactly 2'),
      );
      expect(
        validateScheduleDraft(
          name: 'A',
          times: ['08:00', '20:00'],
          frequency: 'twice_daily',
          startDate: DateTime(2026, 2, 1),
          endDate: DateTime(2026, 1, 1),
        ),
        contains('End date'),
      );
    });
  });

  test('status labels and icons are stable', () {
    expect(doseStatusLabel('TAKEN'), 'Taken');
    expect(doseStatusLabel('MISSED'), 'Missed');
    expect(scheduleStatusLabel('PAUSED'), 'Paused');
  });
}
