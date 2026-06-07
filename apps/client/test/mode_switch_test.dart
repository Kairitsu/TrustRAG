import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/core/api/api_client.dart';
import 'package:client/core/services/desktop_auto_setup.dart';
import 'package:client/core/services/local_bootstrap.dart';
import 'package:client/core/services/mode_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('server → local session cleanup', () {
    test('clearServerRuntimePrefs keeps saved account tokens', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'active-token',
        'active_account_email': 'user@server.com',
        'last_workspace_id': 'ws-server',
        'account_list': ['user@server.com', 'other@server.com'],
        'auth_token_user@server.com': 'saved-token-1',
        'auth_token_other@server.com': 'saved-token-2',
      });

      await ModeNotifier.clearServerRuntimePrefs();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('active_account_email'), isNull);
      expect(prefs.getString('last_workspace_id'), isNull);
      expect(prefs.getString('auth_token_user@server.com'), 'saved-token-1');
      expect(prefs.getString('auth_token_other@server.com'), 'saved-token-2');
      expect(prefs.getStringList('account_list'), ['user@server.com', 'other@server.com']);
    });

    test('setLocalMode preserves per-account server tokens', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'active-token',
        'active_account_email': 'user@server.com',
        'account_list': ['user@server.com'],
        'auth_token_user@server.com': 'saved-token',
        'app_mode': 'server',
      });

      final notifier = ModeNotifier();
      await Future.delayed(const Duration(milliseconds: 50));
      await notifier.setLocalMode();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_mode'), 'local');
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('auth_token_user@server.com'), 'saved-token');
    });

    test('clearActiveServerSession only clears active session', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'active',
        'active_account_email': 'a@test.com',
        'last_workspace_id': 'ws-1',
        'auth_token_a@test.com': 'persisted',
      });

      await ApiClient.clearActiveServerSession();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('active_account_email'), isNull);
      expect(prefs.getString('last_workspace_id'), isNull);
      expect(prefs.getString('auth_token_a@test.com'), 'persisted');
    });
  });

  group('local identity constants', () {
    test('local account id is distinct from server emails', () {
      expect(LocalBootstrap.localAccountId, DesktopAutoSetup.defaultEmail);
      expect(LocalBootstrap.localAccountId, contains('local@'));
    });

    test('local workspace key uses local account id only', () {
      const key = 'last_workspace_id_${LocalBootstrap.localAccountId}';
      expect(key, contains('local@trustrag.desktop'));
      expect(key, isNot(contains('user@server.com')));
    });
  });
}