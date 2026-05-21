import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/features/dashboard/providers/workspace_provider.dart';

void main() {
  group('Workspace persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saveLastWorkspaceId stores the id in SharedPreferences', () async {
      await saveLastWorkspaceId('ws-abc-123');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_workspace_id'), 'ws-abc-123');
    });

    test('saveLastWorkspaceId overwrites previous value', () async {
      await saveLastWorkspaceId('ws-old');
      await saveLastWorkspaceId('ws-new');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_workspace_id'), 'ws-new');
    });

    test('SharedPreferences returns null when no workspace saved', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_workspace_id'), isNull);
    });

    test('saved id persists across SharedPreferences instances', () async {
      await saveLastWorkspaceId('ws-persist');

      final prefs1 = await SharedPreferences.getInstance();
      expect(prefs1.getString('last_workspace_id'), 'ws-persist');

      final prefs2 = await SharedPreferences.getInstance();
      expect(prefs2.getString('last_workspace_id'), 'ws-persist');
    });

    test('Workspace.fromJson round-trip preserves id', () {
      final json = {
        'id': 'ws-test-1',
        'name': 'Test WS',
        'description': 'desc',
        'document_count': 5,
        'created_at': '2026-05-21T00:00:00Z',
      };
      final ws = Workspace.fromJson(json);
      expect(ws.id, 'ws-test-1');
      expect(ws.name, 'Test WS');
      expect(ws.documentCount, 5);
    });
  });
}
