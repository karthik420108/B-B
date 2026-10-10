import 'package:flutter_test/flutter_test.dart';

import 'package:health_wallet/core/network/api_exception.dart';
import 'package:health_wallet/core/utils/formatters.dart';

void main() {
  group('formatDate / formatDateTime', () {
    test('null dates fall back to sensible labels', () {
      expect(formatDate(null), 'Date unknown');
      expect(formatDateTime(null), '—');
    });

    test('dates are rendered in a readable day format', () {
      final d = DateTime(2026, 3, 5);
      expect(formatDate(d), '5 Mar 2026');
    });
  });

  group('formatBytes', () {
    test('handles B, KB and MB', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
      expect(formatBigBytes(1024 * 1024 * 2), '2.0 MB');
      expect(formatBigBytes(500 * 1024), '500 KB');
    });
  });

  group('titleCase', () {
    test('splits on underscores, dashes and spaces', () {
      expect(titleCase('discharge_summary'), 'Discharge Summary');
      expect(titleCase('consultation-note'), 'Consultation Note');
      expect(titleCase('lab'), 'Lab');
      expect(titleCase(''), '');
    });
  });

  group('verificationLabel', () {
    test('maps statuses', () {
      expect(verificationLabel('verified'), 'Verified');
      expect(verificationLabel('rejected'), 'Rejected');
      expect(verificationLabel(null), 'Unverified (AI)');
      expect(verificationLabel('unverified'), 'Unverified (AI)');
    });
  });

  group('friendlyError', () {
    test('unwraps typed API errors and generic messages', () {
      final api = ApiException(statusCode: 400, code: 'VALIDATION', message: 'Missing field');
      expect(friendlyError(api), 'Missing field');

      final generic = StateError('boom');
      expect(friendlyError(generic), 'Bad state: boom');
    });

    test('adds an actionable hint to role-forbidden errors', () {
      final api = ApiException(
        statusCode: 403,
        code: 'FORBIDDEN',
        message: 'Your account role cannot access this resource.',
      );
      final msg = friendlyError(api);
      expect(msg, contains('Your account role cannot access this resource.'));
      expect(msg, contains('sign out and sign in with the correct account'));
    });
  });

  group('proposedRecordCount', () {
    test('sums the extraction stats the backend actually returns', () {
      // Real shape of `data.extraction` from POST /api/documents.
      final extraction = <String, dynamic>{
        'status': 'extracted',
        'stats': {'observations': 1, 'conditions': 2, 'allergies': 0, 'medications': 1, 'encounters': 1},
        'warnings': <dynamic>[],
        'reviewNotes': <dynamic>[],
        'textSource': 'pdf-text',
        'ocrConfidence': null,
      };
      expect(proposedRecordCount(extraction), 5);
    });

    test('never throws on the object shape that broke the upload screen', () {
      // Regression: this used to be cast to `List?` -> TypeError.
      expect(proposedRecordCount({'status': 'failed', 'error': 'nope'}), 0);
      expect(proposedRecordCount(null), 0);
      expect(proposedRecordCount({'status': 'skipped', 'reason': 'already extracted'}), 0);
      expect(proposedRecordCount(<dynamic>[{}, {}]), 2);
    });
  });

  group('extractionFailure', () {
    test('surfaces the reason only when extraction failed', () {
      expect(extractionFailure({'status': 'failed', 'error': 'OCR exploded'}), 'OCR exploded');
      expect(extractionFailure({'status': 'failed'}), 'Extraction failed.');
      expect(extractionFailure({'status': 'extracted'}), isNull);
      expect(extractionFailure(null), isNull);
    });
  });
}