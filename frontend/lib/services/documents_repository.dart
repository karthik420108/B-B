import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../models/models.dart';

/// Document upload, listing, detail and extraction review.
class DocumentsRepository {
  DocumentsRepository(this._api);

  final ApiClient _api;

  static const allowedExtensions = ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'tiff', 'bmp', 'txt'];

  static String mimeTypeFor(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    if (ext == 'pdf') return 'application/pdf';
    if (ext == 'png') return 'image/png';
    if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
    if (ext == 'webp') return 'image/webp';
    if (ext == 'tiff') return 'image/tiff';
    if (ext == 'bmp') return 'image/bmp';
    return 'text/plain';
  }

  /// Upload a file; returns the created document envelope (with extraction info).
  Future<Map<String, dynamic>> upload({
    required List<int> bytes,
    required String filename,
    String? category,
    String? providerName,
    String? eventDate,
  }) async {
    final envelope = await _api.upload(
      '/api/documents',
      bytes: bytes,
      filename: filename,
      contentType: mimeTypeFor(filename),
      fields: {
        'originalName': filename,
        if (category != null && category.isNotEmpty) 'category': category,
        if (providerName != null && providerName.isNotEmpty) 'providerName': providerName,
        if (eventDate != null && eventDate.isNotEmpty) 'eventDate': eventDate,
      },
    );
    return (envelope['data'] as Map<String, dynamic>?) ?? {};
  }

  /// Paginated document list. Returns items plus total (for paging).
  Future<({List<DocumentSummary> items, int total})> list({int page = 1, int limit = 30}) async {
    final envelope = await _api.getEnvelope('/api/documents', query: {'page': page, 'limit': limit});
    final List<dynamic> rawItems;
    final raw = envelope['data'];
    if (raw is List) {
      rawItems = raw;
    } else {
      rawItems = (raw as Map<String, dynamic>?)?['items'] as List<dynamic>? ?? const [];
    }
    final items = rawItems
        .map((e) => DocumentSummary.fromJson(e as Map<String, dynamic>))
        .toList();
    final pagination = (envelope['pagination'] as Map?) ?? const {};
    final total = ((pagination['total'] as num?) ?? items.length).toInt();
    return (items: items, total: total);
  }

  Future<DocumentDetail> get(String id, {bool includeText = false}) async {
    final data = await _api.getBody('/api/documents/$id', query: {'includeText': '$includeText'});
    return DocumentDetail.fromJson(data as Map<String, dynamic>? ?? const {});
  }

  Future<Map<String, dynamic>> updateMeta(String id, Map<String, dynamic> patch) async {
    final data = await _api.patchBody('/api/documents/$id', body: patch);
    return (data as Map<String, dynamic>?) ?? {};
  }

  Future<void> retryExtraction(String id) async {
    await _api.postBody('/api/documents/$id/extract', body: {'force': true});
  }

  /// Apply verification/corrections to a child record (`PATCH /api/records/:kind/:id/verify`).
  Future<dynamic> verifyRecord({
    required String kind,
    required String id,
    required String verification,
    Map<String, dynamic>? corrections,
  }) {
    return _api.patchBody(
      '/api/records/$kind/$id/verify',
      body: {'verification': verification, 'corrections': ?corrections},
    );
  }

  /// Downstream URL for streaming a document file (needs an auth header).
  String fileUrl(String id) => '/api/documents/$id/file';

  Future<String> downloadText(String id) async {
    try {
      final res = await _api.dio.get<dynamic>('/api/documents/$id/file',
          options: Options(responseType: ResponseType.bytes));
      final bytes = res.data;
      if (bytes is List<int>) return String.fromCharCodes(bytes);
      if (bytes is String) return bytes;
      return '';
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(statusCode: 0, code: 'DOWNLOAD', message: e.toString());
    }
  }
}