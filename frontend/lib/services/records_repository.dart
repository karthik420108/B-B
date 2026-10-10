import '../core/network/api_client.dart';
import '../models/models.dart';

/// Clinical records: timeline, lists, duplicates, medication safety, charts.
class RecordsRepository {
  RecordsRepository(this._api);

  final ApiClient _api;

  static List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      if (data['items'] is List) return data['items'] as List;
      if (data['findings'] is List) return data['findings'] as List;
    }
    return const [];
  }

  Future<List<Observation>> observations() async {
    final data = await _api.getBody('/api/records/observations');
    return _asList(data).map((e) => Observation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Medication>> medications() async {
    final data = await _api.getBody('/api/records/medications');
    return _asList(data).map((e) => Medication.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Allergy>> allergies() async {
    final data = await _api.getBody('/api/records/allergies');
    return _asList(data).map((e) => Allergy.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ConditionRecord>> conditions() async {
    final data = await _api.getBody('/api/records/conditions');
    return _asList(data).map((e) => ConditionRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<EncounterRecord>> encounters() async {
    final data = await _api.getBody('/api/records/encounters');
    return _asList(data).map((e) => EncounterRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<({List<DuplicateFinding> findings, int total})> duplicateTests({int windowDays = 180}) async {
    final data = await _api.getBody(
      '/api/records/duplicates/tests',
      query: {'windowDays': '$windowDays'},
    );
    final map = data as Map<String, dynamic>? ?? const {};
    final findings = _asList(map['findings'] ?? data)
        .map((e) => DuplicateFinding.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = ((map['total'] as num?) ?? findings.length).toInt();
    return (findings: findings, total: total);
  }

  Future<List<DuplicateFinding>> duplicateDocuments() async {
    final data = await _api.getBody('/api/records/duplicates/documents');
    final groups = _asList((data as Map<String, dynamic>?)?['groups'] ?? data);
    return groups
        .map((e) => DuplicateFinding.fromJson(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList();
  }

  Future<MedicationSafetyReport> medicationSafety() async {
    final data = await _api.getBody('/api/records/medications/safety');
    return MedicationSafetyReport.fromJson(data as Map<String, dynamic>? ?? const {});
  }

  /// Chart series for one test (or all when [testName] is null).
  Future<Map<String, dynamic>> charts({String? testName}) async {
    final data = await _api.getBody(
      '/api/records/charts',
      query: testName == null ? null : {'testName': testName},
    );
    return (data as Map<String, dynamic>?) ?? const {};
  }

  Future<Map<String, dynamic>> search(String query) async {
    final data = await _api.getBody('/api/records/search', query: {'q': query});
    return (data as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> addManualRecord(String kind, Map<String, dynamic> data) async {
    final res = await _api.postBody('/api/records/manual', body: {'kind': kind, 'data': data});
    return (res as Map<String, dynamic>?) ?? {};
  }
}