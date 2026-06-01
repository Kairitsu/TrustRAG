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
    final activeAccount = await ApiClient.getActiveAccount();
    final token = await ApiClient.getToken();

    // If user has an active non-local account with a token, respect it
    if (token != null && activeAccount != null && activeAccount != _defaultEmail) {
      try {
        await api.dio.get('/auth/me');
        debugPrint('[AutoSetup] User has active session ($activeAccount), skipping auto-login');
        return;
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          await ApiClient.clearToken();
        } else {
          return;
        }
      }
    }

    // If active account is local and token is valid, skip
    if (token != null && (activeAccount == null || activeAccount == _defaultEmail)) {
      try {
        await api.dio.get('/auth/me');
        return;
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          await ApiClient.clearToken();
        } else {
          return;
        }
      }
    }

    // No valid session — only auto-login to local if no other account is active
    if (activeAccount != null && activeAccount != _defaultEmail) {
      debugPrint('[AutoSetup] Previous account ($activeAccount) token expired, not forcing local login');
      return;
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
      final previousAccount = await ApiClient.getActiveAccount();
      final resp = await api.dio.post('/auth/login', data: {
        'email': _defaultEmail,
        'password': _defaultPassword,
      });
      final token = (resp.data['token'] ?? resp.data['access_token']) as String;
      await ApiClient.setActiveAccount(_defaultEmail);
      await ApiClient.saveToken(token);

      if (BackendManager.shouldRunEmbedded &&
          previousAccount != null &&
          previousAccount != _defaultEmail &&
          BackendManager().isRunning) {
        await BackendManager().restart(accountId: _defaultEmail);
        await BackendManager().ready;
      }

      debugPrint('[AutoSetup] Auto-login successful');
    } on DioException catch (e) {
      debugPrint('[AutoSetup] Auto-login failed: ${e.message}');
    }
  }
}
