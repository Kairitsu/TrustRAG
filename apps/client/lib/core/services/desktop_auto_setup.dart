import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import 'backend_manager.dart';

class DesktopAutoSetup {
  static const _setupDoneKey = 'desktop_setup_done';
  static const _defaultEmail = 'local@trustrag.desktop';
  static const _defaultPassword = 'trustrag-local-2024';
  static const _defaultName = 'Local User';

  static bool get shouldAutoSetup {
    if (kIsWeb) return false;
    return BackendManager.shouldRunEmbedded && BackendManager().isRunning;
  }

  static Future<void> ensureSetup(ApiClient api) async {
    if (!shouldAutoSetup) return;

    final prefs = await SharedPreferences.getInstance();
    final token = await ApiClient.getToken();

    if (token != null) {
      try {
        await api.dio.get('/auth/me');
        return;
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          await ApiClient.clearToken();
        } else {
          // Network error — keep token and skip re-login
          return;
        }
      }
    }

    final isDone = prefs.getBool(_setupDoneKey) ?? false;

    if (!isDone) {
      debugPrint('[AutoSetup] First run detected, creating default user...');
      await _registerDefaultUser(api);
      prefs.setBool(_setupDoneKey, true);
    }

    await _loginDefaultUser(api);
  }

  static Future<void> _registerDefaultUser(ApiClient api) async {
    try {
      await api.dio.post('/auth/register', data: {
        'display_name': _defaultName,
        'email': _defaultEmail,
        'password': _defaultPassword,
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
        'email': _defaultEmail,
        'password': _defaultPassword,
      });
      final token = (resp.data['token'] ?? resp.data['access_token']) as String;
      await ApiClient.saveToken(token);
      await ApiClient.setActiveAccount(_defaultEmail);
      debugPrint('[AutoSetup] Auto-login successful');
    } on DioException catch (e) {
      debugPrint('[AutoSetup] Auto-login failed: ${e.message}');
    }
  }
}
