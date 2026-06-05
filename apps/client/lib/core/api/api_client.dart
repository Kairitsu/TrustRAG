import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_display_helper.dart';
import '../providers/dev_mode_provider.dart';
import '../services/backend_manager.dart';
import '../services/local_bootstrap.dart';

class ApiClient {
  late final Dio dio;
  final String baseUrl;
  static const _tokenKey = 'auth_token';
  static const _activeAccountKey = 'active_account_email';
  static const _accountListKey = 'account_list';
  static const _lastLoginEmailKey = 'last_login_email';

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

  static String _accountTokenKey(String email) => 'auth_token_$email';

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    final email = prefs.getString(_activeAccountKey);
    if (email != null && email.isNotEmpty) {
      await prefs.setString(_accountTokenKey(email), token);
    }
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  /// Active account for embedded token storage; internal local id is not listed.
  static Future<void> setActiveAccount(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeAccountKey, email);

    if (AccountDisplayHelper.isInternalLocalAccount(email)) {
      return;
    }

    final accounts = prefs.getStringList(_accountListKey) ?? [];
    if (!accounts.contains(email)) {
      accounts.add(email);
      await prefs.setStringList(_accountListKey, accounts);
    }
  }

  /// Internal local embedded identity only (not in saved server account list).
  static Future<void> setInternalLocalActiveAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeAccountKey, LocalBootstrap.localAccountId);
  }

  static Future<String?> getActiveAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeAccountKey);
  }

  static Future<List<String>> getSavedAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_accountListKey) ?? [];
    return raw
        .where((e) => !AccountDisplayHelper.isInternalLocalAccount(e))
        .toList();
  }

  static Future<void> purgeInternalLocalFromSavedAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = prefs.getStringList(_accountListKey) ?? [];
    final filtered = accounts
        .where((e) => !AccountDisplayHelper.isInternalLocalAccount(e))
        .toList();
    if (filtered.length != accounts.length) {
      await prefs.setStringList(_accountListKey, filtered);
    }
  }

  static Future<void> clearCurrentServerSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_activeAccountKey);
  }

  static Future<void> removeSavedServerAccount(String email) async {
    if (AccountDisplayHelper.isInternalLocalAccount(email)) return;
    await removeAccount(email);
  }

  static Future<void> setLastLoginEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastLoginEmailKey, email.trim().toLowerCase());
  }

  static Future<String?> getLastLoginEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastLoginEmailKey);
  }

  static Future<bool> hasTokenForAccount(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_accountTokenKey(email));
    return token != null && token.isNotEmpty;
  }

  /// Result of an account switch attempt.
  static const switchOk = 'ok';
  static const switchNeedLogin = 'need_login';
  static const switchFailed = 'failed';

  /// Switch to a previously saved account with rollback on failure.
  /// Returns [switchOk] if token was restored and backend started,
  /// [switchNeedLogin] if the account has no saved token (needs re-auth),
  /// or [switchFailed] if the backend restart failed (rolled back).
  static Future<String> switchToAccount(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final previousEmail = prefs.getString(_activeAccountKey);
    final previousToken = prefs.getString(_tokenKey);

    // Save current account token before switching
    if (previousEmail != null && previousEmail.isNotEmpty && previousToken != null) {
      await prefs.setString(_accountTokenKey(previousEmail), previousToken);
    }

    if (AccountDisplayHelper.isInternalLocalAccount(email)) {
      return switchFailed;
    }

    // Switch active account
    await prefs.setString(_activeAccountKey, email);
    final savedToken = prefs.getString(_accountTokenKey(email));
    if (savedToken != null && savedToken.isNotEmpty) {
      await prefs.setString(_tokenKey, savedToken);
    } else {
      await prefs.remove(_tokenKey);
    }

    // Restart backend for new account data directory
    if (BackendManager.shouldRunEmbedded) {
      try {
        await BackendManager().restart(accountId: email);
        await BackendManager().ready;
        if (BackendManager().hasFailed) {
          throw Exception(BackendManager().startupError ?? 'Backend start failed');
        }
      } catch (e) {
        debugPrint('[ApiClient] switchToAccount backend restart failed: $e');
        // Rollback to previous account
        await _rollbackAccount(prefs, previousEmail, previousToken);
        return switchFailed;
      }
    }

    return savedToken != null && savedToken.isNotEmpty ? switchOk : switchNeedLogin;
  }

  static Future<void> _rollbackAccount(
    SharedPreferences prefs,
    String? previousEmail,
    String? previousToken,
  ) async {
    if (previousEmail != null && previousEmail.isNotEmpty) {
      await prefs.setString(_activeAccountKey, previousEmail);
      if (previousToken != null) {
        await prefs.setString(_tokenKey, previousToken);
      }
      if (BackendManager.shouldRunEmbedded) {
        try {
          await BackendManager().restart(accountId: previousEmail);
          await BackendManager().ready;
        } catch (_) {
          debugPrint('[ApiClient] rollback backend restart also failed');
        }
      }
    }
  }

  static Future<void> removeAccount(String email) async {
    if (AccountDisplayHelper.isInternalLocalAccount(email)) return;
    final prefs = await SharedPreferences.getInstance();
    final accounts = prefs.getStringList(_accountListKey) ?? [];
    accounts.remove(email);
    await prefs.setStringList(_accountListKey, accounts);
    await prefs.remove(_accountTokenKey(email));

    final active = prefs.getString(_activeAccountKey);
    if (active == email) {
      await prefs.remove(_activeAccountKey);
    }
  }

  static Future<void> clearAllAccountData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_activeAccountKey);
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
