import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import 'app_mode.dart';
import 'backend_manager.dart';
import 'local_bootstrap.dart';

export 'app_mode.dart';

class ModeState {
  final AppMode mode;
  final String? serverUrl;
  final bool isLoading;

  const ModeState({
    this.mode = AppMode.unset,
    this.serverUrl,
    this.isLoading = true,
  });

  ModeState copyWith({AppMode? mode, String? serverUrl, bool? isLoading}) {
    return ModeState(
      mode: mode ?? this.mode,
      serverUrl: serverUrl ?? this.serverUrl,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ModeNotifier extends StateNotifier<ModeState> {
  static const _modeKey = 'app_mode';
  static const _serverUrlKey = 'custom_server_url';

  ModeNotifier() : super(const ModeState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_modeKey);
    final serverUrl = prefs.getString(_serverUrlKey);

    AppMode mode;
    if (modeStr == 'local') {
      mode = AppMode.local;
    } else if (modeStr == 'server') {
      mode = AppMode.server;
    } else {
      final legacyMode = prefs.getString('server_mode');
      if (legacyMode == 'custom' && serverUrl != null && serverUrl.isNotEmpty) {
        mode = AppMode.server;
        await prefs.setString(_modeKey, 'server');
      } else if (!kIsWeb && BackendManager.shouldRunEmbedded) {
        mode = AppMode.unset;
      } else {
        mode = AppMode.server;
        await prefs.setString(_modeKey, 'server');
      }
    }

    state = ModeState(mode: mode, serverUrl: serverUrl, isLoading: false);
  }

  static Future<void> _stopEmbeddedBackend() async {
    if (!BackendManager.shouldRunEmbedded) return;
    await BackendManager().stop();
    BackendManager().resetLifecycle();
  }

  static Future<void> _clearServerSessionPrefs(SharedPreferences prefs) async {
    await prefs.remove('auth_token');
    await prefs.remove('active_account_email');
    await prefs.remove('last_workspace_id');
    final accounts = prefs.getStringList('account_list') ?? [];
    for (final email in accounts) {
      await prefs.remove('auth_token_$email');
    }
  }

  static Future<void> _clearLocalSessionPrefs(SharedPreferences prefs) async {
    await prefs.remove('auth_token');
    await prefs.remove('active_account_email');
    await prefs.remove('desktop_setup_done');
    await prefs.remove('last_workspace_id');
    await prefs.remove('last_workspace_id_${LocalBootstrap.localAccountId}');
    await prefs.remove('auth_token_${LocalBootstrap.localAccountId}');
    await ApiClient.purgeInternalLocalFromSavedAccounts();
  }

  Future<void> setLocalMode() async {
    await _stopEmbeddedBackend();
    final prefs = await SharedPreferences.getInstance();
    await _clearServerSessionPrefs(prefs);
    await prefs.setString(_modeKey, 'local');
    await prefs.setString('server_mode', 'local');
    state = state.copyWith(mode: AppMode.local, isLoading: false);
  }

  Future<void> setServerMode(String serverUrl) async {
    await _stopEmbeddedBackend();
    final prefs = await SharedPreferences.getInstance();
    await _clearLocalSessionPrefs(prefs);
    await prefs.setString(_modeKey, 'server');
    await prefs.setString(_serverUrlKey, serverUrl);
    await prefs.setString('server_mode', 'custom');
    await prefs.setString('custom_server_url', serverUrl);
    state = ModeState(mode: AppMode.server, serverUrl: serverUrl, isLoading: false);
  }

  Future<void> resetMode() async {
    await _stopEmbeddedBackend();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_modeKey);
    await prefs.remove('server_mode');
    await prefs.remove(_serverUrlKey);
    await prefs.remove('custom_server_url');
    await prefs.remove('auth_token');
    await prefs.remove('active_account_email');
    await prefs.remove('last_workspace_id');
    await prefs.remove('last_workspace_id_${LocalBootstrap.localAccountId}');
    await prefs.remove('desktop_setup_done');
    state = const ModeState(mode: AppMode.unset, isLoading: false);
  }
}

final modeProvider = StateNotifierProvider<ModeNotifier, ModeState>((ref) {
  return ModeNotifier();
});