import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../network/api_exception.dart';

/// Shared formatting helpers.
String formatDate(DateTime? date) {
  if (date == null) return 'Date unknown';
  return DateFormat('d MMM yyyy').format(date);
}

String formatDateTime(DateTime? date) {
  if (date == null) return '—';
  return DateFormat('d MMM yyyy, HH:mm').format(date);
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatBigBytes(num bytes) {
  final b = bytes.toInt();
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Title-case a label like "discharge_summary" -> "Discharge summary".
String titleCase(String input) {
  if (input.isEmpty) return input;
  return input
      .split(RegExp(r'[_\- ]+'))
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

IconData categoryIcon(String category) {
  switch (category) {
    case 'laboratory':
      return Icons.science_outlined;
    case 'prescription':
      return Icons.medication_outlined;
    case 'imaging':
      return Icons.image_search_outlined;
    case 'discharge_summary':
      return Icons.local_hospital_outlined;
    case 'consultation_note':
      return Icons.forum_outlined;
    case 'vaccination':
      return Icons.vaccines_outlined;
    default:
      return Icons.description_outlined;
  }
}

IconData kindIcon(String kind) {
  switch (kind) {
    case 'observation':
      return Icons.science_outlined;
    case 'medication':
      return Icons.medication_outlined;
    case 'condition':
      return Icons.health_and_safety_outlined;
    case 'allergy':
      return Icons.report_problem_outlined;
    case 'encounter':
      return Icons.event_note_outlined;
    case 'document':
      return Icons.description_outlined;
    default:
      return Icons.record_voice_over_outlined;
  }
}

Color verificationColor(BuildContext context, String? verification) {
  switch (verification) {
    case 'verified':
      return Theme.of(context).colorScheme.primary;
    case 'rejected':
      return Theme.of(context).colorScheme.error;
    default:
      return Theme.of(context).colorScheme.tertiary;
  }
}

String verificationLabel(String? verification) {
  switch (verification) {
    case 'verified':
      return 'Verified';
    case 'rejected':
      return 'Rejected';
    default:
      return 'Unverified (AI)';
  }
}

/// Human-readable message for a thrown backend error.
String friendlyError(Object error) {
  if (error is ApiException) return error.message;
  if (error is NetworkException) return error.message;
  return error.toString().replaceFirst('Exception: ', '');
}

/// How many structured records an inline extraction proposed.
///
/// `POST /api/documents` returns `extraction` as an **object**
/// (`{status, stats: {observations, conditions, ...}, warnings}`) or `null`,
/// never a list. Casting it to `List?` throws
/// `type '_JsonMap' is not a subtype of type 'List<dynamic>?'`.
int proposedRecordCount(dynamic extraction) {
  if (extraction is List) return extraction.length;
  final stats = extraction is Map ? extraction['stats'] : null;
  if (stats is Map) {
    return stats.values.whereType<num>().fold<int>(0, (sum, v) => sum + v.toInt());
  }
  return 0;
}

/// Failure message carried by an inline extraction result, if it failed.
String? extractionFailure(dynamic extraction) {
  if (extraction is! Map || extraction['status'] != 'failed') return null;
  return extraction['error']?.toString() ?? 'Extraction failed.';
}