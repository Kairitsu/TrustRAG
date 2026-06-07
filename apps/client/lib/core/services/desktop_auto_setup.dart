import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import 'backend_manager.dart';
import 'diagnostic_logger.dart';

class DesktopAutoSetup {
  static const _setupDoneKey = 'desktop_setup_done';
  static const defaultEmail = 'local@trustrag.desktop';
  static const defaultPassword = 'trustrag-local-2024';
  static const defaultName = 'Local User';

  static String? lastError;

  static bool get shouldAutoSetup {
    if (kIsWeb) return false;
    return BackendManager.shouldRunEmbedded && BackendManager().isRunning;
  }

  /// Ensures the fixed local user exists and has a valid session token.
  /// Returns true when a local session token is available.
  static Future<bool> ensureLocalIdentity(ApiClient api) async {
    lastError = null;
    if (!shouldAutoSetup) {
      lastError = '本地后端未运行';
      return false;
    }

    final token = await ApiClient.getToken();
    final activeAccount = await ApiClient.getActiveAccount();

    await DiagnosticLogger.info(
      'IDENTITY check hasToken=${token != null} activeAccount=$activeAccount',
    );

    if (token != null) {
      try {
        final me = await api.dio.get('/auth/me');
        final email = me.data is Map ? (me.data as Map)['email']?.toString() : null;
        if (email == defaultEmail ||
            activeAccount == null ||
            activeAccount == defaultEmail) {
          if (activeAccount != defaultEmail) {
            await ApiClient.setInternalLocalActiveAccount();
          }
          await DiagnosticLogger.info('IDENTITY reused existing local session');
          return true;
        }
        await DiagnosticLogger.warn(
          'IDENTITY stale server account token ($activeAccount), clearing',
        );
        await ApiClient.clearToken();
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          await ApiClient.clearToken();
        } else {
          lastError = _dioMessage(e);
          await DiagnosticLogger.error('IDENTITY /auth/me failed: $lastError');
          return false;
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final isDone = prefs.getBool(_setupDoneKey) ?? false;

    await DiagnosticLogger.info('IDENTITY setupDone=$isDone');

    if (!isDone) {
      debugPrint('[AutoSetup] First run detected, creating default user...');
      final registered = await _registerDefaultUser(api);
      if (!registered) return false;
      await prefs.setBool(_setupDoneKey, true);
    }

    return _loginDefaultUser(api);
  }

  /// Legacy entry used by auth check; delegates to [ensureLocalIdentity].
  static Future<void> ensureSetup(ApiClient api) async {
    await ensureLocalIdentity(api);
  }

  static Future<bool> _registerDefaultUser(ApiClient api) async {
    try {
      await api.dio.post('/auth/register', data: {
        'display_name': defaultName,
        'email': defaultEmail,
        'password': defaultPassword,
      });
      debugPrint('[AutoSetup] Default user created');
      await DiagnosticLogger.info('IDENTITY registered local user');
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        debugPrint('[AutoSetup] Default user already exists');
        await DiagnosticLogger.info('IDENTITY local user already exists');
        return true;
      }
      lastError = _dioMessage(e);
      debugPrint('[AutoSetup] Registration failed: ${e.message}');
      await DiagnosticLogger.error('IDENTITY register failed: $lastError');
      return false;
    }
  }

  static Future<bool> _loginDefaultUser(ApiClient api) async {
    try {
      final resp = await api.dio.post('/auth/login', data: {
        'email': defaultEmail,
        'password': defaultPassword,
      });
      final token = (resp.data['token'] ?? resp.data['access_token']) as String;
      await ApiClient.setInternalLocalActiveAccount();
      await ApiClient.saveToken(token);
      debugPrint('[AutoSetup] Auto-login successful');
      await DiagnosticLogger.info('IDENTITY local session created');
      return true;
    } on DioException catch (e) {
      lastError = _dioMessage(e);
      debugPrint('[AutoSetup] Auto-login failed: ${e.message}');
      await DiagnosticLogger.error('IDENTITY login failed: $lastError');
      return false;
    }
  }

  static String _dioMessage(DioException e) {
    final code = e.response?.statusCode;
    final body = e.response?.data;
    if (code != null) {
      return 'HTTP $code ${body ?? e.message ?? ''}'.trim();
    }
    return e.message ?? e.type.name;
  }
}