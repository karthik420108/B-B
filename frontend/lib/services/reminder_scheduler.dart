import 'reminder_scheduler_stub.dart'
    if (dart.library.js_interop) 'reminder_scheduler_web.dart' as impl;

/// Best-effort medication reminder delivery.
///
/// The wallet is a web-first client: the web implementation uses the browser
/// Notification API plus in-page timers. That means a reminder fires while the
/// app tab is open; it does **not** wake a closed browser or a locked phone.
/// OS-level scheduling (Android/iOS local notifications) is deliberately left
/// unimplemented because this project has no native platform folders — see the
/// implementation report. The interface is kept small so a native
/// implementation can be dropped in behind it.
abstract class ReminderScheduler {
  /// Whether real notifications can be delivered on this platform.
  bool get supportsScheduling;

  /// Whether the user has granted notification permission.
  bool get permissionGranted;

  /// Ask the platform for permission to show notifications.
  Future<bool> requestPermission();

  /// Deliver [title]/[body] at [when] (best effort).
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime when,
  });

  /// Cancel a previously scheduled reminder.
  Future<void> cancel(String id);

  /// Cancel all reminders this scheduler has queued.
  Future<void> cancelAll();
}

/// Platform-appropriate scheduler instance.
ReminderScheduler createReminderScheduler() => impl.createReminderScheduler();
