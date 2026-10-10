import 'package:flutter/material.dart';

/// Pure, side-effect-free helpers for the medication reminders feature.
///
/// These are kept free of Flutter widgets (except colour lookup) so they can be
/// unit-tested directly and reused across screens.

const List<String> medicationFrequencies = [
  'once_daily',
  'twice_daily',
  'three_times_daily',
  'custom',
];

/// Number of reminder times a labelled frequency requires. `null` = free-form.
int? frequencyRequiredTimes(String frequency) {
  switch (frequency) {
    case 'once_daily':
      return 1;
    case 'twice_daily':
      return 2;
    case 'three_times_daily':
      return 3;
    default:
      return null;
  }
}

String frequencyLabel(String? frequency) {
  switch (frequency) {
    case 'once_daily':
      return 'Once daily';
    case 'twice_daily':
      return 'Twice daily';
    case 'three_times_daily':
      return 'Three times daily';
    case 'custom':
    default:
      return 'Custom schedule';
  }
}

/// Validate a 24-hour `HH:mm` string.
bool isValidTime(String value) {
  final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value.trim());
  return match != null;
}

/// Convert `HH:mm` to a 12-hour label such as `8:00 AM`.
String formatTime12h(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return hhmm;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return hhmm;
  final period = hour >= 12 ? 'PM' : 'AM';
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12:${minute.toString().padLeft(2, '0')} $period';
}

String scheduleTimesLabel(List<String> times) {
  if (times.isEmpty) return 'No reminder times';
  final sorted = [...times]..sort();
  return sorted.map(formatTime12h).join(', ');
}

/// 12-hour clock label for a concrete instant (e.g. `8:00 AM`).
String clockLabel(DateTime dt) {
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  return '$h12:${dt.minute.toString().padLeft(2, '0')} $period';
}

const List<String> _weekdayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// Human label for a weekday set. Empty = every day.
String weekdaysLabel(List<int> weekdays) {
  if (weekdays.isEmpty || weekdays.length == 7) return 'Every day';
  final sorted = [...weekdays]..sort();
  if (sorted.length == 5 && sorted.join(',') == '1,2,3,4,5') return 'Weekdays';
  if (sorted.length == 2 && sorted.join(',') == '0,6') return 'Weekends';
  return sorted.map((d) => (d >= 0 && d < 7) ? _weekdayShort[d] : '?').join(', ');
}

String doseStatusLabel(String status) {
  switch (status) {
    case 'TAKEN':
      return 'Taken';
    case 'SKIPPED':
      return 'Skipped';
    case 'MISSED':
      return 'Missed';
    case 'DUE':
      return 'Due now';
    case 'UPCOMING':
    default:
      return 'Upcoming';
  }
}

IconData doseStatusIcon(String status) {
  switch (status) {
    case 'TAKEN':
      return Icons.check_circle;
    case 'SKIPPED':
      return Icons.cancel_outlined;
    case 'MISSED':
      return Icons.error_outline;
    case 'DUE':
      return Icons.notifications_active_outlined;
    default:
      return Icons.schedule;
  }
}

Color doseStatusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case 'TAKEN':
      return scheme.primary;
    case 'SKIPPED':
      return scheme.tertiary;
    case 'MISSED':
      return scheme.error;
    case 'DUE':
      return Colors.orange.shade800;
    default:
      return scheme.outline;
  }
}

Color scheduleStatusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case 'ACTIVE':
      return scheme.primary;
    case 'PAUSED':
      return Colors.orange.shade800;
    case 'DISCONTINUED':
      return scheme.error;
    default:
      return scheme.outline;
  }
}

String scheduleStatusLabel(String status) {
  switch (status) {
    case 'ACTIVE':
      return 'Active';
    case 'PAUSED':
      return 'Paused';
    case 'COMPLETED':
      return 'Completed';
    case 'DISCONTINUED':
      return 'Stopped';
    default:
      return status;
  }
}

/// Concise relative label for a dose time, e.g. "in 2h 15m", "due now",
/// "12m overdue".
String relativeDoseLabel(DateTime? scheduledFor, {DateTime? now}) {
  if (scheduledFor == null) return '';
  final reference = now ?? DateTime.now();
  final diff = scheduledFor.difference(reference);
  final overdue = diff.isNegative;
  final abs = diff.abs();
  if (abs.inMinutes < 1) return 'due now';
  final hours = abs.inHours;
  final minutes = abs.inMinutes % 60;
  final buffer = StringBuffer();
  if (hours > 0) buffer.write('${hours}h ');
  buffer.write('${minutes}m');
  final text = buffer.toString().trim();
  return overdue ? '$text overdue' : 'in $text';
}

/// Parse a `YYYY-MM-DD` string into a local [DateTime]; falls back to now.
DateTime parseIsoDate(String value, {DateTime? fallback}) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value.trim());
  if (match != null) {
    return DateTime(int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
  }
  return fallback ?? DateTime.now();
}

String toIsoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Validate a manual medication entry. Returns an error message, or null when
/// the input is valid.
String? validateScheduleDraft({
  required String name,
  required List<String> times,
  required String frequency,
  required DateTime? startDate,
  required DateTime? endDate,
}) {
  if (name.trim().isEmpty) return 'Medicine name is required.';
  if (times.isEmpty) return 'Add at least one reminder time.';
  if (times.length > 8) return 'A schedule can have at most 8 reminder times per day.';
  for (final t in times) {
    if (!isValidTime(t)) return '“$t” is not a valid time. Use 24-hour HH:mm.';
  }
  if (times.toSet().length != times.length) return 'Reminder times must be unique.';
  final required = frequencyRequiredTimes(frequency);
  if (required != null && times.length != required) {
    return '${frequencyLabel(frequency)} needs exactly $required reminder time${required == 1 ? '' : 's'}.';
  }
  if (startDate == null) return 'A start date is required.';
  if (endDate != null && endDate.isBefore(startDate)) {
    return 'End date must be on or after the start date.';
  }
  return null;
}
