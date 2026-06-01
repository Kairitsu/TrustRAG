import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/core/api/api_client.dart';

void main() {
  group('ApiClient account management', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('setActiveAccount stores email and adds to account list', () async {
      await ApiClient.setActiveAccount('user@example.com');
      final active = await ApiClient.getActiveAccount();
      expect(active, 'user@example.com');

      final accounts = await ApiClient.getSavedAccounts();
      expect(accounts, contains('user@example.com'));
    });

    test('setActiveAccount before saveToken binds token correctly', () async {
      await ApiClient.setActiveAccount('user@example.com');
      await ApiClient.saveToken('test-token-123');

      final hasToken = await ApiClient.hasTokenForAccount('user@example.com');
      expect(hasToken, true);
    });

    test('hasTokenForAccount returns false for unknown account', () async {
      final hasToken = await ApiClient.hasTokenForAccount('nobody@example.com');
      expect(hasToken, false);
    });

    test('saveToken without active account still saves global token', () async {
      await ApiClient.saveToken('global-token');
      final token = await ApiClient.getToken();
      expect(token, 'global-token');
    });

    test('removeAccount clears token and removes from list', () async {
      await ApiClient.setActiveAccount('user@example.com');
      await ApiClient.saveToken('token-abc');

      await ApiClient.removeAccount('user@example.com');

      final accounts = await ApiClient.getSavedAccounts();
      expect(accounts, isNot(contains('user@example.com')));

      final hasToken = await ApiClient.hasTokenForAccount('user@example.com');
      expect(hasToken, false);
    });

    test('clearAllAccountData removes token and active account', () async {
      await ApiClient.setActiveAccount('user@example.com');
      await ApiClient.saveToken('token-abc');

      await ApiClient.clearAllAccountData();

      final active = await ApiClient.getActiveAccount();
      expect(active, isNull);
      final token = await ApiClient.getToken();
      expect(token, isNull);
    });

    test('multiple accounts can be tracked independently', () async {
      await ApiClient.setActiveAccount('a@test.com');
      await ApiClient.saveToken('token-a');

      await ApiClient.setActiveAccount('b@test.com');
      await ApiClient.saveToken('token-b');

      final accounts = await ApiClient.getSavedAccounts();
      expect(accounts.length, 2);
      expect(accounts, containsAll(['a@test.com', 'b@test.com']));

      expect(await ApiClient.hasTokenForAccount('a@test.com'), true);
      expect(await ApiClient.hasTokenForAccount('b@test.com'), true);
    });

    test('switchToAccount constants are distinct', () {
      expect(ApiClient.switchOk, isNot(equals(ApiClient.switchNeedLogin)));
      expect(ApiClient.switchOk, isNot(equals(ApiClient.switchFailed)));
      expect(ApiClient.switchNeedLogin, isNot(equals(ApiClient.switchFailed)));
    });
  });
}
