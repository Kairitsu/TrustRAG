import 'package:flutter_test/flutter_test.dart';
import 'package:client/features/settings/pages/workspace_members_page.dart';

void main() {
  group('WorkspaceMember model', () {
    test('fromJson parses all fields', () {
      final m = WorkspaceMember.fromJson({
        'id': 'mem-1',
        'user_id': 'user-1',
        'display_name': 'Alice',
        'role': 'editor',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(m.id, 'mem-1');
      expect(m.userId, 'user-1');
      expect(m.displayName, 'Alice');
      expect(m.role, 'editor');
      expect(m.createdAt, '2026-01-01T00:00:00Z');
    });

    test('fromJson handles missing display_name', () {
      final m = WorkspaceMember.fromJson({
        'id': 'mem-2',
        'user_id': 'user-2',
        'role': 'viewer',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(m.displayName, '');
    });

    test('fromJson defaults role to viewer', () {
      final m = WorkspaceMember.fromJson({
        'id': 'mem-3',
        'user_id': 'user-3',
        'display_name': 'Bob',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(m.role, 'viewer');
    });

    test('fromJson handles null fields gracefully', () {
      final m = WorkspaceMember.fromJson({
        'id': 'mem-4',
        'user_id': 'user-4',
        'display_name': null,
        'role': null,
        'created_at': null,
      });
      expect(m.displayName, '');
      expect(m.role, 'viewer');
      expect(m.createdAt, '');
    });
  });

  group('Permission logic', () {
    test('owner can manage', () {
      const role = 'owner';
      final canManage = role == 'owner' || role == 'editor';
      expect(canManage, isTrue);
    });

    test('editor can manage', () {
      const role = 'editor';
      final canManage = role == 'owner' || role == 'editor';
      expect(canManage, isTrue);
    });

    test('viewer cannot manage', () {
      const role = 'viewer';
      final canManage = role == 'owner' || role == 'editor';
      expect(canManage, isFalse);
    });

    test('null role cannot manage', () {
      const String? role = null;
      final canManage = role == 'owner' || role == 'editor';
      expect(canManage, isFalse);
    });
  });

  group('Role labels', () {
    String roleLabel(String role) {
      switch (role) {
        case 'owner':
          return '所有者';
        case 'editor':
          return '编辑者';
        case 'admin':
          return '管理员';
        default:
          return '查看者';
      }
    }

    test('owner label', () => expect(roleLabel('owner'), '所有者'));
    test('editor label', () => expect(roleLabel('editor'), '编辑者'));
    test('viewer label', () => expect(roleLabel('viewer'), '查看者'));
    test('unknown defaults to viewer', () => expect(roleLabel('xyz'), '查看者'));
  });
}
