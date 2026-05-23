import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/dev_mode_provider.dart';
import '../services/backend_manager.dart';

class ApiClient {
  late final Dio dio;
  final String baseUrl;
  static const _tokenKey = 'auth_token';

  ApiClient({String? baseUrl})
      : baseUrl = baseUrl ?? _resolveBaseUrl() {
    dio = Dio(BaseOptions(
      baseUrl: this.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString(_tokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_tokenKey);
        }
        handler.next(error);
      },
    ));

    dio.interceptors.add(_DebugLogInterceptor());

    final cacheStore = MemCacheStore(maxSize: 50, maxEntrySize: 524288);
    final cacheOptions = CacheOptions(
      store: cacheStore,
      policy: CachePolicy.request,
      maxStale: const Duration(minutes: 5),
    );
    dio.interceptors.add(DioCacheInterceptor(options: cacheOptions));
  }

  static String? _savedServerUrl;

  static Future<void> loadSavedServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('server_mode') ?? 'official';
    if (mode == 'custom') {
      _savedServerUrl = prefs.getString('custom_server_url');
    }
  }

  static String _resolveBaseUrl() {
    if (BackendManager.shouldRunEmbedded) {
      if (BackendManager().isRunning || BackendManager().startAttempted) {
        return BackendManager().baseUrl;
      }
    }

    const envUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: '',
    );
    if (envUrl.isNotEmpty) return envUrl;

    if (_savedServerUrl != null && _savedServerUrl!.isNotEmpty) {
      return _savedServerUrl!;
    }

    if (kIsWeb) {
      return const String.fromEnvironment('API_BASE_URL', defaultValue: '/api');
    }

    return 'http://localhost:8080';
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}

class _DebugLogInterceptor extends Interceptor {
  final _log = DebugLogBuffer();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _log.add('API >> ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _log.add(
        'API << ${response.statusCode} ${response.requestOptions.method} ${response.requestOptions.path}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final code = err.response?.statusCode ?? 0;
    _log.add(
        'API ERROR [$code] ${err.requestOptions.method} ${err.requestOptions.path}: ${err.message}');
    handler.next(err);
  }
}
