import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/core/services/local_bootstrap.dart';
import 'package:client/core/services/mode_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModeNotifier cleanup', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'stale-token',
        'active_account_email': LocalBootstrap.localAccountId,
        'desktop_setup_done': true,
        'last_workspace_id': 'ws-1',
        'last_workspace_id_${LocalBootstrap.localAccountId}': 'ws-local',
        'custom_server_url': 'https://old.server.test',
        'app_mode': 'local',
      });
    });

    test('setServerMode clears local session keys', () async {
      final notifier = ModeNotifier();
      await Future.delayed(const Duration(milliseconds: 50));

      await notifier.setServerMode('https://new.server.test');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_mode'), 'server');
      expect(prefs.getString('custom_server_url'), 'https://new.server.test');
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('active_account_email'), isNull);
      expect(prefs.getBool('desktop_setup_done'), isNull);
      expect(prefs.getString('last_workspace_id_${LocalBootstrap.localAccountId}'),
          isNull);
    });

    test('resetMode clears tokens and mode', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'token',
        'active_account_email': 'user@test.com',
        'app_mode': 'server',
        'custom_server_url': 'https://x.test',
      });

      final notifier = ModeNotifier();
      await Future.delayed(const Duration(milliseconds: 50));
      await notifier.resetMode();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_mode'), isNull);
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('active_account_email'), isNull);
      expect(prefs.getString('custom_server_url'), isNull);
      expect(notifier.state.mode, AppMode.unset);
    });
  });
}