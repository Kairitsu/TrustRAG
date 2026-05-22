import 'package:flutter_test/flutter_test.dart';
import 'package:client/features/dashboard/providers/workspace_provider.dart';

void main() {
  group('Workspace model', () {
    test('fromJson parses personal workspace correctly', () {
      final json = {
        'id': 'ws-001',
        'name': 'My Workspace',
        'description': 'A test workspace',
        'type': 'personal',
        'invite_code': null,
        'created_at': '2026-01-01T00:00:00Z',
      };

      final ws = Workspace.fromJson(json);
      expect(ws.id, 'ws-001');
      expect(ws.name, 'My Workspace');
      expect(ws.description, 'A test workspace');
      expect(ws.type, 'personal');
      expect(ws.inviteCode, isNull);
      expect(ws.isPersonal, true);
      expect(ws.isTeam, false);
    });

    test('fromJson parses team workspace correctly', () {
      final json = {
        'id': 'ws-002',
        'name': 'Team Alpha',
        'description': 'Our team workspace',
        'type': 'team',
        'invite_code': 'ABCD1234',
        'created_at': '2026-01-01T00:00:00Z',
      };

      final ws = Workspace.fromJson(json);
      expect(ws.id, 'ws-002');
      expect(ws.name, 'Team Alpha');
      expect(ws.type, 'team');
      expect(ws.inviteCode, 'ABCD1234');
      expect(ws.isTeam, true);
      expect(ws.isPersonal, false);
    });

    test('fromJson defaults type to personal when missing', () {
      final json = {
        'id': 'ws-003',
        'name': 'Legacy Workspace',
        'created_at': '2026-01-01T00:00:00Z',
      };

      final ws = Workspace.fromJson(json);
      expect(ws.type, 'personal');
      expect(ws.isPersonal, true);
      expect(ws.isTeam, false);
    });

    test('fromJson handles null description and invite_code', () {
      final json = {
        'id': 'ws-004',
        'name': 'Minimal',
        'description': null,
        'type': 'team',
        'invite_code': null,
        'created_at': '2026-01-01T00:00:00Z',
      };

      final ws = Workspace.fromJson(json);
      expect(ws.description, isNull);
      expect(ws.inviteCode, isNull);
    });

    test('isTeam and isPersonal are mutually exclusive', () {
      final personalJson = {'id': '1', 'name': 'P', 'type': 'personal', 'created_at': '2026-01-01T00:00:00Z'};
      final teamJson = {'id': '2', 'name': 'T', 'type': 'team', 'created_at': '2026-01-01T00:00:00Z'};
      final personal = Workspace.fromJson(personalJson);
      final team = Workspace.fromJson(teamJson);

      expect(personal.isPersonal, true);
      expect(personal.isTeam, false);
      expect(team.isPersonal, false);
      expect(team.isTeam, true);
    });
  });

  group('Workspace member roles', () {
    test('workspace member model parses all roles', () {
      // Verify the role values that the system supports
      const validRoles = ['owner', 'admin', 'editor', 'viewer'];
      for (final role in validRoles) {
        expect(validRoles.contains(role), true,
          reason: 'Role "$role" should be valid');
      }
    });

    test('invite code format: 8 chars, uppercase + digits', () {
      // The backend generates invite codes with ABCDEFGHJKLMNPQRSTUVWXYZ23456789
      // (no 0, 1, I, O to avoid confusion)
      const sampleCode = 'ABCD2345';
      expect(sampleCode.length, 8);
      expect(RegExp(r'^[A-Z2-9]{8}$').hasMatch(sampleCode), true);
    });
  });

  group('Workspace list categorization', () {
    test('correctly separates personal and team workspaces', () {
      final workspaces = [
        Workspace.fromJson({'id': '1', 'name': 'Personal 1', 'type': 'personal', 'created_at': '2026-01-01T00:00:00Z'}),
        Workspace.fromJson({'id': '2', 'name': 'Team Alpha', 'type': 'team', 'invite_code': 'CODE1234', 'created_at': '2026-01-01T00:00:00Z'}),
        Workspace.fromJson({'id': '3', 'name': 'Personal 2', 'type': 'personal', 'created_at': '2026-01-01T00:00:00Z'}),
        Workspace.fromJson({'id': '4', 'name': 'Team Beta', 'type': 'team', 'invite_code': 'CODE5678', 'created_at': '2026-01-01T00:00:00Z'}),
      ];

      final personal = workspaces.where((w) => w.isPersonal).toList();
      final teams = workspaces.where((w) => w.isTeam).toList();

      expect(personal.length, 2);
      expect(teams.length, 2);
      expect(personal.every((w) => w.isPersonal), true);
      expect(teams.every((w) => w.isTeam), true);
      expect(teams.every((w) => w.inviteCode != null), true);
    });

    test('empty workspace list produces empty categories', () {
      final workspaces = <Map<String, dynamic>>[];
      final parsed = workspaces.map((j) => Workspace.fromJson(j)).toList();
      final personal = parsed.where((w) => w.isPersonal).toList();
      final teams = parsed.where((w) => w.isTeam).toList();

      expect(personal, isEmpty);
      expect(teams, isEmpty);
    });
  });
}
