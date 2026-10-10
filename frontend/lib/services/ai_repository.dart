import '../core/network/api_client.dart';
import '../models/models.dart';

/// RAG assistant: grounded Q&A and source-linked medical summary.
class AiRepository {
  AiRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> providerInfo() async {
    final data = await _api.getBody('/api/ai/provider');
    return (data as Map<String, dynamic>?) ?? const {};
  }

  Future<AiAnswer> ask(String question, {int topK = 8}) async {
    final data = await _api.postBody('/api/ai/ask', body: {'question': question.trim(), 'topK': topK});
    return AiAnswer.fromJson(data as Map<String, dynamic>? ?? const {});
  }

  Future<MedicalSummary> summary() async {
    final data = await _api.postBody('/api/ai/summary');
    return MedicalSummary.fromJson(data as Map<String, dynamic>? ?? const {});
  }
}