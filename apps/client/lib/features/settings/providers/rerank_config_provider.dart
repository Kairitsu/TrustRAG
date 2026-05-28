import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';

class RerankConfig {
  final String id;
  final String name;
  final String provider;
  final String apiBaseUrl;
  final bool hasApiKey;
  final String modelName;
  final int topN;
  final int initialRecallK;
  final bool fallbackEnabled;
  final int timeoutSecs;
  final bool isDefault;

  RerankConfig({
    required this.id,
    required this.name,
    required this.provider,
    required this.apiBaseUrl,
    required this.hasApiKey,
    required this.modelName,
    required this.topN,
    required this.initialRecallK,
    required this.fallbackEnabled,
    required this.timeoutSecs,
    required this.isDefault,
  });

  factory RerankConfig.fromJson(Map<String, dynamic> json) {
    return RerankConfig(
      id: json['id'],
      name: json['name'] ?? '',
      provider: json['provider'] ?? '',
      apiBaseUrl: json['api_base_url'] ?? '',
      hasApiKey: json['has_api_key'] ?? false,
      modelName: json['model_name'] ?? '',
      topN: json['top_n'] ?? 5,
      initialRecallK: json['initial_recall_k'] ?? 30,
      fallbackEnabled: json['fallback_enabled'] ?? true,
      timeoutSecs: json['timeout_secs'] ?? 30,
      isDefault: json['is_default'] ?? false,
    );
  }
}

class RerankConfigNotifier
    extends StateNotifier<AsyncValue<List<RerankConfig>>> {
  final Ref ref;

  RerankConfigNotifier(this.ref) : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/rerank-configs');
      final list = (resp.data as List)
          .map((j) => RerankConfig.fromJson(j))
          .toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<bool> create(Map<String, dynamic> data) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('/rerank-configs', data: data);
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> update(String id, Map<String, dynamic> data) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.put('/rerank-configs/$id', data: data);
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> delete(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.delete('/rerank-configs/$id');
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> testConnection(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post('/rerank-configs/$id/test');
      return Map<String, dynamic>.from(resp.data);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  Future<bool> setDefault(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.put('/rerank-configs/$id/default');
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final rerankConfigProvider = StateNotifierProvider<RerankConfigNotifier,
    AsyncValue<List<RerankConfig>>>((ref) {
  return RerankConfigNotifier(ref);
});
