import 'package:flutter_test/flutter_test.dart';

import 'package:health_wallet/core/network/api_client.dart';
import 'package:health_wallet/core/storage/token_storage.dart';
import 'package:health_wallet/services/medication_repository.dart';

/// Records the calls the repository makes and returns canned responses.
class _FakeApi extends ApiClient {
  _FakeApi() : super(TokenStorage());

  final calls = <({String method, String path, Map<String, dynamic>? query, Map<String, dynamic>? body})>[];
  dynamic getResponse;
  dynamic postResponse;

  @override
  Future<dynamic> getBody(String path, {Map<String, dynamic>? query}) async {
    calls.add((method: 'GET', path: path, query: query, body: null));
    return getResponse;
  }

  @override
  Future<dynamic> postBody(String path, {Map<String, dynamic>? body}) async {
    calls.add((method: 'POST', path: path, query: null, body: body));
    return postResponse;
  }
}

void main() {
  group('MedicationRepository', () {
    test('parses the schedule list envelope', () async {
      final api = _FakeApi()
        ..getResponse = {
          'items': [
            {'id': 's1', 'name': 'Metformin', 'status': 'ACTIVE', 'reminderTimes': ['08:00']},
          ],
          'total': 1,
        };
      final repo = MedicationRepository(api);

      final schedules = await repo.listSchedules();

      expect(schedules, hasLength(1));
      expect(schedules.first.name, 'Metformin');
      expect(api.calls.single.path, '/api/medications');
    });

    test('maps {schedule: {...}} from the create envelope', () async {
      final api = _FakeApi()
        ..postResponse = {
          'schedule': {'id': 's2', 'name': 'Amlodipine'},
          'dosesCreated': 30,
        };
      final repo = MedicationRepository(api);

      final schedule = await repo.createSchedule({'name': 'Amlodipine'});

      expect(schedule.id, 's2');
      expect(api.calls.single.method, 'POST');
      expect(api.calls.single.path, '/api/medications');
    });

    test('recordDose reads the dose from the action envelope', () async {
      final api = _FakeApi()
        ..postResponse = {
          'dose': {'id': 'dose1', 'scheduleId': 's1', 'status': 'TAKEN'},
        };
      final repo = MedicationRepository(api);

      final dose = await repo.recordDose('dose1', 'TAKEN');

      expect(dose.status, 'TAKEN');
      expect(dose.isTaken, isTrue);
      expect(api.calls.single.path, '/api/medications/doses/dose1/action');
      expect(api.calls.single.body, {'action': 'TAKEN'});
    });

    test('dosesInRange converts the local day to a UTC query range', () async {
      final api = _FakeApi()..getResponse = {'items': []};
      final repo = MedicationRepository(api);

      await repo.dosesInRange(
        from: DateTime(2026, 3, 1, 0, 0),
        to: DateTime(2026, 3, 2, 0, 0),
      );

      final call = api.calls.single;
      expect(call.path, '/api/medications/doses');
      expect(call.query!['from'], contains('T'));
      expect(call.query!['from'], endsWith('Z'));
      expect(call.query!['to'], endsWith('Z'));
    });

    test('history surfaces the disclaimer', () async {
      final api = _FakeApi()
        ..getResponse = {
          'items': [],
          'total': 0,
          'disclaimer': 'A Missed entry is not proof.',
        };
      final repo = MedicationRepository(api);

      final history = await repo.history();

      expect(history.disclaimer, contains('not proof'));
    });
  });
}
