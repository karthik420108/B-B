import '../core/network/api_client.dart';
import '../models/models.dart';

/// Patient-owned medication reminder schedules and dose tracking.
///
/// All calls hit `/api/medications`, which is patient-only on the backend:
/// doctors never gain access here by viewing shared records.
class MedicationRepository {
  MedicationRepository(this._api);

  final ApiClient _api;

  static List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return const [];
  }

  // ---- Schedules ----------------------------------------------------------

  Future<List<MedicationSchedule>> listSchedules({String? status}) async {
    final data = await _api.getBody(
      '/api/medications',
      query: status == null ? null : {'status': status},
    );
    return _asList(data)
        .map((e) => MedicationSchedule.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MedicationSchedule> getSchedule(String id) async {
    final data = await _api.getBody('/api/medications/$id');
    return MedicationSchedule.fromJson(data as Map<String, dynamic>? ?? const {});
  }

  Future<MedicationSchedule> createSchedule(Map<String, dynamic> body) async {
    final data = await _api.postBody('/api/medications', body: body);
    return _scheduleFromEnvelope(data);
  }

  Future<MedicationSchedule> updateSchedule(String id, Map<String, dynamic> patch) async {
    final data = await _api.patchBody('/api/medications/$id', body: patch);
    return _scheduleFromEnvelope(data);
  }

  Future<MedicationSchedule> pauseSchedule(String id) async =>
      _scheduleFromEnvelope(await _api.postBody('/api/medications/$id/pause'));

  Future<MedicationSchedule> resumeSchedule(String id, {bool confirmReopen = false}) async =>
      _scheduleFromEnvelope(await _api.postBody(
        '/api/medications/$id/resume',
        body: {'confirmReopen': confirmReopen},
      ));

  Future<MedicationSchedule> discontinueSchedule(String id) async =>
      _scheduleFromEnvelope(await _api.postBody('/api/medications/$id/discontinue'));

  MedicationSchedule _scheduleFromEnvelope(dynamic data) {
    if (data is Map<String, dynamic>) {
      final schedule = data['schedule'];
      if (schedule is Map<String, dynamic>) return MedicationSchedule.fromJson(schedule);
      return MedicationSchedule.fromJson(data);
    }
    return MedicationSchedule.fromJson(const {});
  }

  // ---- Doses --------------------------------------------------------------

  /// Doses in an explicit UTC range (defaults to the device's local day).
  Future<List<DoseOccurrence>> dosesInRange({DateTime? from, DateTime? to}) async {
    final start = from ?? _startOfToday();
    final end = to ?? start.add(const Duration(days: 1));
    final data = await _api.getBody('/api/medications/doses', query: {
      'from': start.toUtc().toIso8601String(),
      'to': end.toUtc().toIso8601String(),
    });
    return _asList(data).map((e) => DoseOccurrence.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Today's doses, using the device's local calendar day.
  Future<List<DoseOccurrence>> todayDoses() => dosesInRange();

  Future<List<DoseOccurrence>> upcomingDoses({int limit = 30}) async {
    final data = await _api.getBody('/api/medications/doses/upcoming', query: {'limit': '$limit'});
    return _asList(data).map((e) => DoseOccurrence.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Record a dose as Taken or Skipped. Server enforces the tracking window and
  /// rejects contradictory transitions.
  Future<DoseOccurrence> recordDose(String doseId, String action, {String? note}) async {
    final data = await _api.postBody(
      '/api/medications/doses/$doseId/action',
      body: {'action': action, if (note != null && note.isNotEmpty) 'note': note},
    );
    final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    final dose = map['dose'];
    return DoseOccurrence.fromJson(dose is Map<String, dynamic> ? dose : map);
  }

  Future<DoseHistory> history({DateTime? from, DateTime? to, int page = 1, int limit = 50}) async {
    final data = await _api.getBody('/api/medications/history', query: {
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
      'page': '$page',
      'limit': '$limit',
    });
    return DoseHistory.fromJson(data as Map<String, dynamic>? ?? const {});
  }

  // ---- Prescription extraction -------------------------------------------

  /// Read candidate medications from a prescription document. Nothing is
  /// persisted until [confirmExtraction] is called.
  Future<PrescriptionExtraction> extractFromDocument(String documentId) async {
    final data = await _api.postBody('/api/medications/extract', body: {'documentId': documentId});
    return PrescriptionExtraction.fromJson(data as Map<String, dynamic>? ?? const {});
  }

  Future<MedicationSchedule> confirmExtraction({
    required String documentId,
    required Map<String, dynamic> medication,
    String? snippet,
    String? clientRequestId,
  }) async {
    final data = await _api.postBody('/api/medications/confirm', body: {
      'documentId': documentId,
      'confirmed': true,
      if (snippet != null && snippet.isNotEmpty) 'snippet': snippet,
      'clientRequestId': ?clientRequestId,
      'medication': medication,
    });
    return _scheduleFromEnvelope(data);
  }

  DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}
