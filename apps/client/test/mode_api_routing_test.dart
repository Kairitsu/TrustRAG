import 'package:flutter_test/flutter_test.dart';
import 'package:client/core/api/api_client.dart';
import 'package:client/core/services/app_mode.dart';

void main() {
  group('ApiClient.resolveBaseUrl', () {
    test('server mode never returns localhost when backend is running', () {
      const serverUrl = 'https://my-server.example.com';
      final url = ApiClient.resolveBaseUrl(
        mode: AppMode.server,
        serverUrl: serverUrl,
        backendRunning: true,
        backendBaseUrl: 'http://127.0.0.1:8080',
      );
      expect(url, serverUrl);
      expect(url.contains('127.0.0.1'), isFalse);
    });

    test('server mode falls back to official URL when serverUrl empty', () {
      final url = ApiClient.resolveBaseUrl(
        mode: AppMode.server,
        serverUrl: '',
        backendRunning: true,
        backendBaseUrl: 'http://127.0.0.1:9999',
      );
      expect(url, 'https://api.trustrag.app');
    });

    test('local mode uses backend base URL when running', () {
      final url = ApiClient.resolveBaseUrl(
        mode: AppMode.local,
        backendRunning: true,
        backendBaseUrl: 'http://127.0.0.1:54321',
      );
      expect(url, 'http://127.0.0.1:54321');
    });

    test('unset desktop mode does not default to localhost:8080', () {
      final url = ApiClient.resolveBaseUrl(mode: AppMode.unset);
      expect(url, isNot('http://localhost:8080'));
      expect(url, isEmpty);
    });
  });
}