import 'package:dio/dio.dart';
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
    return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
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
  Future<DoctorBundle> bundle(String tokenOrId) async {
    final isObjectId = RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(tokenOrId);
    if (isObjectId) {
      return getShare(tokenOrId);
    }
    final data = await _api.getBody('/api/share/$tokenOrId/bundle');
    return DoctorBundle.fromJson(data as Map<String, dynamic>? ?? const {});
  }

  /// Fetch an authorized bundle by its ShareGrant database ID.
  Future<DoctorBundle> getShare(String shareId) async {
    final data = await _api.getBody('/api/doctor/shares/$shareId');
    return DoctorBundle.fromJson(data as Map<String, dynamic>? ?? const {});
  }

  /// Ask Doctor AI questions grounded only in the authorized records.
  ///
  /// [documentIds] optionally focuses the answer on specific in-scope files;
  /// the server rejects any file outside the active grant. [resetConversation]
  /// clears the stored thread for this share before answering.
  Future<AiAnswer> askDoctorAi(
    String shareIdOrToken,
    String question, {
    int topK = 8,
    List<String>? documentIds,
    bool resetConversation = false,
  }) async {
    final endpoint = _aiAskEndpoint(shareIdOrToken);
    final data = await _api.postBody(endpoint, body: {
      'question': question.trim(),
      'topK': topK,
      if (documentIds != null && documentIds.isNotEmpty) 'documentIds': documentIds,
      if (resetConversation) 'resetConversation': true,
    });
    return AiAnswer.fromJson(data as Map<String, dynamic>? ?? const {});
  }

  /// Persisted doctor AI conversation for this share (server re-checks access).
  Future<List<ConversationMessage>> doctorConversation(String shareIdOrToken) async {
    final data = await _api.getBody('${_aiAskEndpoint(shareIdOrToken).replaceAll('/ask', '')}/conversation');
    final messages = (data as Map<String, dynamic>?)?['messages'];
    return (messages as List?)
            ?.map((e) => ConversationMessage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        const [];
  }

  /// Clear this doctor's conversation thread for the share.
  Future<void> clearDoctorConversation(String shareIdOrToken) async {
    final url = _aiAskEndpoint(shareIdOrToken).replaceAll('/ask', '/conversation');
    await _api.deleteBody(url);
  }

  String _aiAskEndpoint(String shareIdOrToken) {
    final isObjectId = RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(shareIdOrToken);
    return isObjectId
        ? '/api/doctor/shares/$shareIdOrToken/ai/ask'
        : '/api/share/$shareIdOrToken/ai/ask';
  }

  String documentFileUrl(String shareIdOrToken, String docId) {
    final isObjectId = RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(shareIdOrToken);
    return isObjectId
        ? '/api/doctor/shares/$shareIdOrToken/documents/$docId/file'
        : '/api/share/$shareIdOrToken/documents/$docId/file';
  }

  /// Download file bytes for an authorized document.
  Future<List<int>> downloadDocumentBytes(String shareIdOrToken, String docId) async {
    final url = documentFileUrl(shareIdOrToken, docId);
    final res = await _api.dio.get<List<dynamic>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final raw = res.data;
    if (raw is List<int>) return raw;
    if (raw is List) return raw.cast<int>();
    return const [];
  }

  /// Retrieve the authenticated doctor's QR identification payload.
  Future<Map<String, dynamic>> myDoctorQr() async {
    final data = await _api.getBody('/api/doctor/me/qr');
    return (data as Map<String, dynamic>?) ?? const {};
  }
}