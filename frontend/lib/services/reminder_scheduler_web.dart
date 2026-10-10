import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'reminder_scheduler.dart';

/// Web implementation of [ReminderScheduler].
///
/// Uses the browser Notification API for delivery and an in-page [Timer] for
/// timing. This is honest about its limits: timers only run while the page is
/// alive, so a reminder set for six hours from now fires only if the tab stays
/// open. True background delivery would need a service worker plus a push
/// subscription, which is out of scope for this project.
class _WebReminderScheduler implements ReminderScheduler {
  final Map<String, Timer> _timers = {};
  bool _permission = false;
  bool _permissionChecked = false;

  @override
  bool get supportsScheduling => true;

  @override
  bool get permissionGranted {
    if (!_permissionChecked) _refreshPermission();
    return _permission;
  }

  void _refreshPermission() {
    try {
      _permission = web.Notification.permission == 'granted';
    } catch (_) {
      _permission = false;
    }
    _permissionChecked = true;
  }

  @override
  Future<bool> requestPermission() async {
    _refreshPermission();
    if (_permission) return true;
    try {
      final JSString result = await web.Notification.requestPermission().toDart;
      _permission = result.toDart == 'granted';
    } catch (_) {
      _permission = false;
    }
    _permissionChecked = true;
    return _permission;
  }

  @override
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    _timers.remove(id)?.cancel();
    final delay = when.difference(DateTime.now());
    if (delay.isNegative) return;
    _timers[id] = Timer(delay, () {
      _timers.remove(id);
      _show(title: title, body: body, tag: id);
    });
  }

  void _show({required String title, required String body, required String tag}) {
    if (!permissionGranted) return;
    try {
      web.Notification(
        title,
        web.NotificationOptions(body: body, tag: tag, requireInteraction: true),
      );
    } catch (_) {
      // Notification could not be shown (e.g. permission revoked); ignore.
    }
  }

  @override
  Future<void> cancel(String id) async {
    _timers.remove(id)?.cancel();
  }

  @override
  Future<void> cancelAll() async {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}

ReminderScheduler createReminderScheduler() => _WebReminderScheduler();
