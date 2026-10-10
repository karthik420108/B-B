import '../core/network/api_client.dart';
import '../models/models.dart';

/// Patient-side share management: create, list, detail with history, revoke.
class ShareRepository {
  ShareRepository(this._api);

  final ApiClient _api;

  Future<ShareCreated> create(Map<String, dynamic> payload) async {
    final data = await _api.postBody('/api/shares', body: payload);
    return ShareCreated.fromJson(data as Map<String, dynamic>);
  }

  Future<List<ShareGrant>> list() async {
    final data = await _api.getBody('/api/shares');
    final items = data is List ? data : ((data as Map<String, dynamic>?)?['items'] ?? const []);
    return items.map((e) => ShareGrant.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ShareDetail> get(String id) async {
    final data = await _api.getBody('/api/shares/$id');
    return ShareDetail.fromJson(data as Map<String, dynamic>? ?? const {});
  }

  Future<Map<String, dynamic>> accessHistory(String id) async {
    final data = await _api.getBody('/api/shares/$id/access-history');
    return (data as Map<String, dynamic>?) ?? const {};
  }

  Future<ShareDetail> revoke(String id, {String reason = ''}) async {
    final data = await _api.postBody('/api/shares/$id/revoke', body: {'reason': reason});
    return ShareDetail.fromJson(data as Map<String, dynamic>? ?? const {});
  }
}