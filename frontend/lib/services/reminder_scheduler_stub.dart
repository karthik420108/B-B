import 'reminder_scheduler.dart';

/// Non-web fallback: no notification channel is available, so scheduling is a
/// safe no-op. The UI reads [supportsScheduling] to explain this to the user.
class _NoopReminderScheduler implements ReminderScheduler {
  @override
  bool get supportsScheduling => false;

  @override
  bool get permissionGranted => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime when,
  }) async {}

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<void> cancelAll() async {}
}

ReminderScheduler createReminderScheduler() => _NoopReminderScheduler();
