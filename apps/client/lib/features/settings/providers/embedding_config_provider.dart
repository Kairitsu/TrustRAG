import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';

class EmbeddingConfig {
  final String id;
  final String name;
  final String provider;
  final String? apiBaseUrl;
  final bool hasApiKey;
  final String modelName;
  final int dimensions;
  final int batchSize;
  final bool isDefault;

  EmbeddingConfig({
    required this.id,
    required this.name,
    required this.provider,
    this.apiBaseUrl,
    required this.hasApiKey,
    required this.modelName,
    required this.dimensions,
    required this.batchSize,
    required this.isDefault,
  });

  factory EmbeddingConfig.fromJson(Map<String, dynamic> json) {
    return EmbeddingConfig(
      id: json['id'],
      name: json['name'] ?? '',
      provider: json['provider'] ?? '',
      apiBaseUrl: json['api_base_url'],
      hasApiKey: json['has_api_key'] ?? false,
      modelName: json['model_name'] ?? '',
      dimensions: json['dimensions'] ?? 1536,
      batchSize: json['batch_size'] ?? 10,
      isDefault: json['is_default'] ?? false,
    );
  }
}

class EmbeddingConfigNotifier
    extends StateNotifier<AsyncValue<List<EmbeddingConfig>>> {
  final Ref ref;

  EmbeddingConfigNotifier(this.ref) : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/embedding-configs');
      final list = (resp.data as List)
          .map((j) => EmbeddingConfig.fromJson(j))
          .toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<bool> create(Map<String, dynamic> data) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('/embedding-configs', data: data);
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> update(String id, Map<String, dynamic> data) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.put('/embedding-configs/$id', data: data);
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> delete(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.delete('/embedding-configs/$id');
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> testConnection(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post('/embedding-configs/$id/test');
      return Map<String, dynamic>.from(resp.data);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }
}

final embeddingConfigProvider = StateNotifierProvider<EmbeddingConfigNotifier,
    AsyncValue<List<EmbeddingConfig>>>((ref) {
  return EmbeddingConfigNotifier(ref);
});
