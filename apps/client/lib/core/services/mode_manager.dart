import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_manager.dart';

enum AppMode { unset, local, server }

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
      // Migration: if user already configured a custom server, infer server mode
      final legacyMode = prefs.getString('server_mode');
      if (legacyMode == 'custom' && serverUrl != null && serverUrl.isNotEmpty) {
        mode = AppMode.server;
        await prefs.setString(_modeKey, 'server');
      } else if (!kIsWeb && BackendManager.shouldRunEmbedded) {
        mode = AppMode.unset;
      } else {
        // Web or non-embedded platform defaults to server mode
        mode = AppMode.server;
        await prefs.setString(_modeKey, 'server');
      }
    }

    state = ModeState(mode: mode, serverUrl: serverUrl, isLoading: false);
  }

  Future<void> setLocalMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, 'local');
    await prefs.setString('server_mode', 'local');
    state = state.copyWith(mode: AppMode.local, isLoading: false);
  }

  Future<void> setServerMode(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, 'server');
    await prefs.setString(_serverUrlKey, serverUrl);
    await prefs.setString('server_mode', 'custom');
    await prefs.setString('custom_server_url', serverUrl);
    state = ModeState(mode: AppMode.server, serverUrl: serverUrl, isLoading: false);
  }

  Future<void> resetMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_modeKey);
    await prefs.remove('server_mode');
    state = const ModeState(mode: AppMode.unset, isLoading: false);
  }
}

final modeProvider = StateNotifierProvider<ModeNotifier, ModeState>((ref) {
  return ModeNotifier();
});
