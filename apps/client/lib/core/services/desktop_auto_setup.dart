import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import 'backend_manager.dart';

class DesktopAutoSetup {
  static const _setupDoneKey = 'desktop_setup_done';
  static const defaultEmail = 'local@trustrag.desktop';
  static const defaultPassword = 'trustrag-local-2024';
  static const defaultName = 'Local User';

  static bool get shouldAutoSetup {
    if (kIsWeb) return false;
    return BackendManager.shouldRunEmbedded && BackendManager().isRunning;
  }

  /// Ensures the fixed local user exists and has a valid session token.
  static Future<void> ensureLocalIdentity(ApiClient api) async {
    if (!shouldAutoSetup) return;

    final token = await ApiClient.getToken();
    final activeAccount = await ApiClient.getActiveAccount();

    if (token != null) {
      try {
        await api.dio.get('/auth/me');
        if (activeAccount == null || activeAccount == defaultEmail) {
          return;
        }
        // Stale server-account token in local embedded DB — re-establish local user.
        await ApiClient.clearToken();
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          await ApiClient.clearToken();
        } else {
          return;
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final isDone = prefs.getBool(_setupDoneKey) ?? false;

    if (!isDone) {
      debugPrint('[AutoSetup] First run detected, creating default user...');
      await _registerDefaultUser(api);
      await prefs.setBool(_setupDoneKey, true);
    }

    await _loginDefaultUser(api);
  }

  /// Legacy entry used by auth check; delegates to [ensureLocalIdentity].
  static Future<void> ensureSetup(ApiClient api) async {
    await ensureLocalIdentity(api);
  }

  static Future<void> _registerDefaultUser(ApiClient api) async {
    try {
      await api.dio.post('/auth/register', data: {
        'display_name': defaultName,
        'email': defaultEmail,
        'password': defaultPassword,
      });
      debugPrint('[AutoSetup] Default user created');
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        debugPrint('[AutoSetup] Default user already exists');
      } else {
        debugPrint('[AutoSetup] Registration failed: ${e.message}');
      }
    }
  }

  static Future<void> _loginDefaultUser(ApiClient api) async {
    try {
      final resp = await api.dio.post('/auth/login', data: {
        'email': defaultEmail,
        'password': defaultPassword,
      });
      final token = (resp.data['token'] ?? resp.data['access_token']) as String;
      await ApiClient.setActiveAccount(defaultEmail);
      await ApiClient.saveToken(token);
      debugPrint('[AutoSetup] Auto-login successful');
    } on DioException catch (e) {
      debugPrint('[AutoSetup] Auto-login failed: ${e.message}');
    }
  }
}