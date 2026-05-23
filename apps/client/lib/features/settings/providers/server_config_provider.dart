import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kServerModeKey = 'server_mode';
const _kCustomServerUrlKey = 'custom_server_url';
const _kOfficialServerUrl = 'https://api.trustrag.app';

enum ServerMode { official, custom }

class ServerConfig {
  final ServerMode mode;
  final String customUrl;
  final ServerConnectionStatus connectionStatus;

  const ServerConfig({
    this.mode = ServerMode.official,
    this.customUrl = '',
    this.connectionStatus = ServerConnectionStatus.unknown,
  });

  String get effectiveUrl {
    if (mode == ServerMode.custom && customUrl.isNotEmpty) {
      return customUrl;
    }
    return _kOfficialServerUrl;
  }

  static const String officialUrl = _kOfficialServerUrl;

  ServerConfig copyWith({
    ServerMode? mode,
    String? customUrl,
    ServerConnectionStatus? connectionStatus,
  }) {
    return ServerConfig(
      mode: mode ?? this.mode,
      customUrl: customUrl ?? this.customUrl,
      connectionStatus: connectionStatus ?? this.connectionStatus,
    );
  }
}

enum ServerConnectionStatus {
  unknown,
  checking,
  connected,
  disconnected,
}

class ServerConfigNotifier extends StateNotifier<ServerConfig> {
  ServerConfigNotifier() : super(const ServerConfig()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_kServerModeKey) ?? 'official';
    final customUrl = prefs.getString(_kCustomServerUrlKey) ?? '';

    state = ServerConfig(
      mode: modeStr == 'custom' ? ServerMode.custom : ServerMode.official,
      customUrl: customUrl,
    );
  }

  Future<void> setMode(ServerMode mode) async {
    state = state.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerModeKey, mode == ServerMode.custom ? 'custom' : 'official');
  }

  Future<void> setCustomUrl(String url) async {
    state = state.copyWith(customUrl: url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCustomServerUrlKey, url);
  }

  Future<void> checkConnection() async {
    state = state.copyWith(connectionStatus: ServerConnectionStatus.checking);

    final url = state.effectiveUrl;
    try {
      final healthUrl = Uri.parse('$url/health');
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(healthUrl);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200 && body.contains('ok')) {
        state = state.copyWith(connectionStatus: ServerConnectionStatus.connected);
      } else {
        state = state.copyWith(connectionStatus: ServerConnectionStatus.disconnected);
      }
    } catch (e) {
      debugPrint('[ServerConfig] Connection check failed: $e');
      state = state.copyWith(connectionStatus: ServerConnectionStatus.disconnected);
    }
  }
}

final serverConfigProvider =
    StateNotifierProvider<ServerConfigNotifier, ServerConfig>((ref) {
  return ServerConfigNotifier();
});
