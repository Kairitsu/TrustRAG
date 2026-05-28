import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/core/api/api_client.dart';
import 'package:client/features/dashboard/providers/workspace_provider.dart';

void main() {
  group('Per-account token storage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saveToken stores to both global and account-specific key', () async {
      await ApiClient.setActiveAccount('alice@test.com');
      await ApiClient.saveToken('token-alice');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'token-alice');
      expect(prefs.getString('auth_token_alice@test.com'), 'token-alice');
    });

    test('switchToAccount preserves current token and restores target', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'token-alice',
        'active_account_email': 'alice@test.com',
        'auth_token_alice@test.com': 'token-alice',
        'auth_token_bob@test.com': 'token-bob',
        'account_list': ['alice@test.com', 'bob@test.com'],
      });

      final restored = await ApiClient.switchToAccount('bob@test.com');
      expect(restored, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'token-bob');
      expect(prefs.getString('active_account_email'), 'bob@test.com');
      expect(prefs.getString('auth_token_alice@test.com'), 'token-alice');
    });

    test('switchToAccount returns false when no saved token', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'token-alice',
        'active_account_email': 'alice@test.com',
        'auth_token_alice@test.com': 'token-alice',
        'account_list': ['alice@test.com', 'new@test.com'],
      });

      final restored = await ApiClient.switchToAccount('new@test.com');
      expect(restored, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('active_account_email'), 'new@test.com');
    });

    test('removeAccount clears account-specific token', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token_alice@test.com': 'token-alice',
        'active_account_email': 'alice@test.com',
        'account_list': ['alice@test.com'],
      });

      await ApiClient.removeAccount('alice@test.com');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token_alice@test.com'), isNull);
      expect(prefs.getStringList('account_list'), isEmpty);
      expect(prefs.getString('active_account_email'), isNull);
    });

    test('getSavedAccounts returns all registered accounts', () async {
      SharedPreferences.setMockInitialValues({
        'account_list': ['a@test.com', 'b@test.com', 'c@test.com'],
      });

      final accounts = await ApiClient.getSavedAccounts();
      expect(accounts.length, 3);
      expect(accounts, contains('a@test.com'));
      expect(accounts, contains('b@test.com'));
    });

    test('setActiveAccount adds to account list if new', () async {
      SharedPreferences.setMockInitialValues({
        'account_list': ['existing@test.com'],
      });

      await ApiClient.setActiveAccount('new@test.com');

      final prefs = await SharedPreferences.getInstance();
      final accounts = prefs.getStringList('account_list')!;
      expect(accounts.length, 2);
      expect(accounts, contains('new@test.com'));
    });

    test('setActiveAccount does not duplicate existing account', () async {
      SharedPreferences.setMockInitialValues({
        'account_list': ['existing@test.com'],
      });

      await ApiClient.setActiveAccount('existing@test.com');

      final prefs = await SharedPreferences.getInstance();
      final accounts = prefs.getStringList('account_list')!;
      expect(accounts.length, 1);
    });
  });

  group('Per-account workspace persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saveLastWorkspaceId writes to account-specific key', () async {
      SharedPreferences.setMockInitialValues({
        'active_account_email': 'alice@test.com',
      });

      await saveLastWorkspaceId('ws-alice-1');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_workspace_id_alice@test.com'), 'ws-alice-1');
      expect(prefs.getString('last_workspace_id'), 'ws-alice-1');
    });

    test('different accounts have independent workspace selections', () async {
      SharedPreferences.setMockInitialValues({
        'active_account_email': 'alice@test.com',
      });

      await saveLastWorkspaceId('ws-alice-1');

      SharedPreferences.setMockInitialValues({
        'active_account_email': 'bob@test.com',
        'last_workspace_id_alice@test.com': 'ws-alice-1',
        'last_workspace_id': 'ws-alice-1',
      });

      await saveLastWorkspaceId('ws-bob-2');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_workspace_id_alice@test.com'), 'ws-alice-1');
      expect(prefs.getString('last_workspace_id_bob@test.com'), 'ws-bob-2');
    });

    test('saveLastWorkspaceId works without active account (fallback)', () async {
      SharedPreferences.setMockInitialValues({});

      await saveLastWorkspaceId('ws-default');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_workspace_id'), 'ws-default');
    });
  });

  group('Workspace model', () {
    test('Workspace.fromJson handles team type', () {
      final json = {
        'id': 'ws-team-1',
        'name': 'Team WS',
        'description': 'A team workspace',
        'document_count': 10,
        'type': 'team',
        'invite_code': 'ABC12345',
        'created_at': '2026-05-28T00:00:00Z',
      };
      final ws = Workspace.fromJson(json);
      expect(ws.isTeam, isTrue);
      expect(ws.isPersonal, isFalse);
      expect(ws.inviteCode, 'ABC12345');
    });

    test('Workspace.fromJson defaults to personal type', () {
      final json = {
        'id': 'ws-personal-1',
        'name': 'Personal WS',
        'created_at': '2026-05-28T00:00:00Z',
      };
      final ws = Workspace.fromJson(json);
      expect(ws.isPersonal, isTrue);
      expect(ws.isTeam, isFalse);
      expect(ws.documentCount, 0);
    });
  });
}
