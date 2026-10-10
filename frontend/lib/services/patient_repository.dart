import '../core/network/api_client.dart';
import '../models/models.dart';

/// Patient profile, emergency card, appointments and settings data.
class PatientRepository {
  PatientRepository(this._api);

  final ApiClient _api;

  Future<PatientProfile> getProfile() async {
    final data = await _api.getBody('/api/patient/profile');
    return PatientProfile.fromJson(data as Map<String, dynamic>? ?? const {});
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> patch) async {
    final data = await _api.patchBody('/api/patient/profile', body: patch);
    return (data as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> getEmergencyCard() async {
    final data = await _api.getBody('/api/patient/emergency-card');
    return (data as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> updateEmergencyCard(Map<String, dynamic> patch) async {
    final data = await _api.putAsBody('/api/patient/emergency-card', body: patch);
    return (data as Map<String, dynamic>?) ?? {};
  }

  Future<DashboardData> getDashboard() async {
    final data = await _api.getBody('/api/patient/dashboard');
    return DashboardData.fromJson(data as Map<String, dynamic>? ?? const {});
  }

  Future<List<Appointment>> getAppointments() async {
    final data = await _api.getBody('/api/appointments');
    return _toList(data).map((e) => Appointment.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Appointment> createAppointment(Map<String, dynamic> payload) async {
    final data = await _api.postBody('/api/appointments', body: payload);
    return Appointment.fromJson(data as Map<String, dynamic>);
  }

  Future<List<AppNotification>> getNotifications({bool unreadOnly = false}) async {
    final query = unreadOnly ? {'unread': 'true'} : null;
    final data = await _api.getBody('/api/notifications', query: query);
    return _toList(data).map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<int> getUnreadCount() async {
    final data = await _api.getBody('/api/notifications/unread-count');
    return ((data as Map<String, dynamic>? ?? const {})['count'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, dynamic>?> markNotificationRead(String id) async {
    final data = await _api.postBody('/api/notifications/$id/read');
    return data as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>?> markAllRead() async {
    final data = await _api.postBody('/api/notifications/read-all');
    return data as Map<String, dynamic>?;
  }

  /// Simple list-coercion for endpoints that return arrays directly.
  static List<dynamic> _toList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return const [];
  }
}