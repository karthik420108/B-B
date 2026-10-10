import 'package:flutter_test/flutter_test.dart';

import 'package:health_wallet/models/models.dart';

void main() {
  group('DocumentSummary', () {
    test('parses the backend JSON shape with defaults', () {
      final doc = DocumentSummary.fromJson({
        'id': 'd1',
        'originalName': 'blood_panel.pdf',
        'category': 'laboratory',
        'mimeType': 'application/pdf',
        'size': 2048,
        'extractionStatus': 'extracted',
        'providerName': 'City Labs',
        'pageCount': 2,
        'eventDate': '2026-01-15T00:00:00.000Z',
      });
      expect(doc.id, 'd1');
      expect(doc.originalName, 'blood_panel.pdf');
      expect(doc.category, 'laboratory');
      expect(doc.size, 2048);
      expect(doc.pageCount, 2);
      expect(doc.eventDate, DateTime.parse('2026-01-15T00:00:00.000Z').toLocal());
    });

    test('falls back gracefully for missing fields', () {
      final doc = DocumentSummary.fromJson({'id': 'd2'});
      expect(doc.category, 'other');
      expect(doc.extractionStatus, 'pending');
      expect(doc.eventDate, isNull);
      expect(doc.tags, isEmpty);
    });
  });

  group('Observation', () {
    test('uses numeric value and unit for display', () {
      final obs = Observation.fromJson({
        'id': 'o1',
        'testName': 'HbA1c',
        'verification': 'verified',
        'value': 7.2,
        'unit': '%',
        'referenceRange': '4.0 - 5.6',
      });
      expect(obs.value, 7.2);
      expect(obs.hasValue, isTrue);
      expect(obs.displayValue, '7.2 %');
      expect(obs.isVerified, isTrue);
    });

    test('falls back to a string value when numeric is absent', () {
      final obs = Observation.fromJson({
        'id': 'o2',
        'testName': 'Notes',
        'valueString': 'Negative',
      });
      expect(obs.value.isFinite, isFalse);
      expect(obs.displayValue, 'Negative');
      expect(obs.verification, 'unverified');
    });
  });

  group('Medication', () {
    test('detects active status', () {
      final active = Medication.fromJson({'id': 'm1', 'name': 'Metformin', 'status': 'active'});
      final past = Medication.fromJson({'id': 'm2', 'name': 'Amoxicillin', 'status': 'completed'});
      expect(active.isActive, isTrue);
      expect(past.isActive, isFalse);
      expect(active.verification, 'unverified');
    });
  });

  group('MedicationSafetyReport', () {
    test('parses interactions and duplicates', () {
      final report = MedicationSafetyReport.fromJson({
        'checkerAvailable': true,
        'interactions': [
          {
            'title': 'Warfarin + Ibuprofen',
            'severity': 'major',
            'effect': 'Increased bleeding risk',
            'recommendation': 'Avoid combination; review with prescriber.',
            'medications': ['Warfarin', 'Ibuprofen'],
          }
        ],
        'duplicates': [
          {
            'normalizedTestName': 'Metformin',
            'reason': 'Same active ingredient prescribed twice',
            'recommendation': 'Consolidate to a single prescription.',
          }
        ],
      });
      expect(report.checkerAvailable, isTrue);
      expect(report.interactions, hasLength(1));
      expect(report.interactions.first.severity, 'major');
      expect(report.duplicates, hasLength(1));
    });

    test('defaults to an available checker with no alerts', () {
      final report = MedicationSafetyReport.fromJson({});
      expect(report.checkerAvailable, isTrue);
      expect(report.interactions, isEmpty);
      expect(report.duplicates, isEmpty);
    });
  });

  group('ShareGrant', () {
    test('parses token preview and access count', () {
      final grant = ShareGrant.fromJson({
        'id': 's1',
        'status': 'active',
        'label': 'Cardiology review',
        'doctorName': 'Dr. Ada',
        'accessCount': 3,
        'tokenPreview': 'HW-ab12…',
        'isActive': true,
        'documentCount': 4,
      });
      expect(grant.status, 'active');
      expect(grant.accessCount, 3);
      expect(grant.isActive, isTrue);
      expect(grant.documentCount, 4);
    });
  });

  group('TimelineItem', () {
    test('marks undated items explicitly', () {
      final item = TimelineItem.fromJson({
        'kind': 'observation',
        'id': 'o9',
        'title': 'HbA1c',
        'dateUnknown': true,
      });
      expect(item.date, isNull);
      expect(item.dateUnknown, isTrue);
      expect(item.kind, 'observation');
    });
  });
}