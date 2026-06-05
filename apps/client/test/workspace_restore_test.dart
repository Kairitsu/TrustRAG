import 'package:flutter_test/flutter_test.dart';

import 'package:client/features/dashboard/providers/workspace_provider.dart';

Workspace _ws(String id, String name) => Workspace(
      id: id,
      name: name,
      createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
    );

void main() {
  group('pickWorkspaceForRestore', () {
    test('returns saved workspace when id exists in list', () {
      final list = [_ws('a', 'A'), _ws('b', 'B')];
      expect(pickWorkspaceForRestore(list, 'b').id, 'b');
    });

    test('falls back to first when saved id is missing', () {
      final list = [_ws('a', 'A'), _ws('b', 'B')];
      expect(pickWorkspaceForRestore(list, 'stale-id').id, 'a');
    });

    test('returns first when saved id is null', () {
      final list = [_ws('x', 'X')];
      expect(pickWorkspaceForRestore(list, null).id, 'x');
    });
  });
}