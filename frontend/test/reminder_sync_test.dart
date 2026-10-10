import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_wallet/models/models.dart';
import 'package:health_wallet/providers/providers.dart';
import 'package:health_wallet/services/reminder_scheduler.dart';

/// Captures what the sync asks the platform to deliver.
class _FakeScheduler implements ReminderScheduler {
  final scheduled = <String>[];
  bool granted = false;

  @override
  bool get supportsScheduling => true;

  @override
  bool get permissionGranted => granted;

  @override
  Future<bool> requestPermission() async {
    granted = true;
    return true;
  }

  @override
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    scheduled.add(id);
  }

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<void> cancelAll() async => scheduled.clear();
}

DoseOccurrence _dose(String id, DateTime when, String status) =>
    DoseOccurrence(id: id, scheduleId: 's1', scheduledFor: when, status: status, scheduleName: 'Test');

void main() {
  test('the non-web scheduler is a safe no-op', () {
    // The test VM is not web, so the conditional import resolves to the stub.
    final scheduler = createReminderScheduler();
    expect(scheduler.supportsScheduling, isFalse);
    expect(scheduler.permissionGranted, isFalse);
  });

  group('ReminderSync', () {
    test('schedules only future, unrecorded doses', () async {
      final scheduler = _FakeScheduler();
      final container = ProviderContainer(
        overrides: [reminderSchedulerProvider.overrideWithValue(scheduler)],
      );
      addTearDown(container.dispose);

      final now = DateTime.now();
      await container.read(reminderSyncProvider).syncFromDoses([
        _dose('future', now.add(const Duration(hours: 2)), 'UPCOMING'),
        _dose('due', now.add(const Duration(minutes: 5)), 'DUE'),
        _dose('past', now.subtract(const Duration(hours: 2)), 'MISSED'),
        _dose('taken', now.add(const Duration(hours: 3)), 'TAKEN'),
      ]);

      expect(scheduler.scheduled, ['future', 'due']);
    });

    test('cancelAll runs first so stale reminders do not linger', () async {
      final scheduler = _FakeScheduler()..scheduled.add('stale');
      final container = ProviderContainer(
        overrides: [reminderSchedulerProvider.overrideWithValue(scheduler)],
      );
      addTearDown(container.dispose);

      await container
          .read(reminderSyncProvider)
          .syncFromDoses([_dose('fresh', DateTime.now().add(const Duration(hours: 1)), 'UPCOMING')]);

      expect(scheduler.scheduled, ['fresh']);
    });

    test('enable() requests permission on a supporting platform', () async {
      final scheduler = _FakeScheduler();
      final container = ProviderContainer(
        overrides: [reminderSchedulerProvider.overrideWithValue(scheduler)],
      );
      addTearDown(container.dispose);

      expect(await container.read(reminderSyncProvider).enable(), isTrue);
      expect(scheduler.granted, isTrue);
    });
  });
}
