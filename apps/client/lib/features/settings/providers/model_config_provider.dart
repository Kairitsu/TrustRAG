import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';

class ModelConfig {
  final String id;
  final String name;
  final String provider;
  final String modelName;
  final String apiBaseUrl;
  final String endpointMode;
  final bool hasApiKey;
  final bool isDefault;

  ModelConfig({
    required this.id,
    required this.name,
    required this.provider,
    required this.modelName,
    required this.apiBaseUrl,
    required this.endpointMode,
    required this.hasApiKey,
    required this.isDefault,
  });

  factory ModelConfig.fromJson(Map<String, dynamic> json) {
    return ModelConfig(
      id: json['id'],
      name: json['name'] ?? '',
      provider: json['provider'],
      modelName: json['model_name'],
      apiBaseUrl: json['api_base_url'] ?? '',
      endpointMode: json['endpoint_mode'] ?? 'base_url',
      hasApiKey: json['has_api_key'] ?? false,
      isDefault: json['is_default'] ?? false,
    );
  }
}

class ModelConfigNotifier
    extends StateNotifier<AsyncValue<List<ModelConfig>>> {
  final Ref ref;

  ModelConfigNotifier(this.ref) : super(const AsyncValue.data([]));

  Future<void> loadConfigs() async {
    state = const AsyncValue.loading();
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/model-configs');
      final list = (resp.data as List)
          .map((j) => ModelConfig.fromJson(j))
          .toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<bool> createConfig(Map<String, dynamic> data) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('/model-configs', data: data);
      await loadConfigs();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateConfig(String id, Map<String, dynamic> data) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.put('/model-configs/$id', data: data);
      await loadConfigs();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteConfig(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.delete('/model-configs/$id');
      state = AsyncValue.data(
        (state.value ?? []).where((c) => c.id != id).toList(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> testConnection(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post('/model-configs/$id/test');
      return resp.data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> testConnectionDetailed(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post('/model-configs/$id/test');
      return Map<String, dynamic>.from(resp.data);
    } catch (e) {
      return {'success': false, 'message': '请求失败: $e'};
    }
  }
}

final modelConfigProvider = StateNotifierProvider<ModelConfigNotifier,
    AsyncValue<List<ModelConfig>>>((ref) {
  return ModelConfigNotifier(ref);
});
