import '../core/network/api_client.dart';
import '../models/models.dart';

/// Doctor-access layer: doctor directory, authorized shares, token claim/bundle.
class DoctorRepository {
  DoctorRepository(this._api);

  final ApiClient _api;

  Future<List<Map<String, dynamic>>> directory() async {
    final data = await _api.getBody('/api/doctor/directory');
    final items = data is List ? data : const [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Shares that authorize this doctor (with per-request server checks).
  Future<List<Map<String, dynamic>>> myShares() async {
    final data = await _api.getBody('/api/doctor/shares');
    final items = data is List ? data : ((data as Map<String, dynamic>?)?['items'] ?? const []);
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Inspect a token without consuming an access (used before claiming).
  Future<Map<String, dynamic>> inspect(String token) async {
    final data = await _api.getBody('/api/share/$token/inspect');
    return (data as Map<String, dynamic>?) ?? const {};
  }

  /// Claim a token: binds the link share to this doctor and returns the bundle.
  Future<DoctorBundle> claim(String token) async {
    final data = await _api.postBody('/api/share/$token/claim');
    return DoctorBundle.fromJson(data as Map<String, dynamic>? ?? const {});
  }

  /// Fetch an already-authorized bundle (re-validated server side each time).
  Future<DoctorBundle> bundle(String token) async {
    final data = await _api.getBody('/api/share/$token/bundle');
    return DoctorBundle.fromJson(data as Map<String, dynamic>? ?? const {});
  }

  String documentFileUrl(String token, String docId) => '/api/share/$token/documents/$docId/file';
}