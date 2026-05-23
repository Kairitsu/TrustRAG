import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/features/chat/pages/chat_page.dart';
import 'package:client/features/chat/providers/chat_provider.dart';
import 'package:client/features/dashboard/providers/workspace_provider.dart';

Widget _buildTestApp({
  required Size screenSize,
  Workspace? selectedWorkspace,
}) {
  return ProviderScope(
    overrides: [
      selectedWorkspaceProvider.overrideWith((ref) => selectedWorkspace),
      conversationProvider.overrideWith(
          (ref) => _FakeConversationNotifier()),
      messagesProvider.overrideWith((ref) => <ChatMessage>[]),
      selectedConversationProvider.overrideWith((ref) => null),
      workspaceProvider.overrideWith(
          (ref) => _FakeWorkspaceNotifier(selectedWorkspace)),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: screenSize),
        child: const Scaffold(body: ChatPage()),
      ),
    ),
  );
}

class _FakeConversationNotifier
    extends StateNotifier<AsyncValue<List<Conversation>>>
    implements ConversationNotifier {
  _FakeConversationNotifier() : super(const AsyncValue.data([]));

  @override
  Ref get ref => throw UnimplementedError();

  @override
  Future<void> loadConversations(String workspaceId) async {}

  @override
  Future<Conversation?> createConversation(
      String workspaceId, String? title) async {
    return null;
  }

  @override
  Future<void> deleteConversation(String workspaceId, String convId) async {}
}

class _FakeWorkspaceNotifier
    extends StateNotifier<AsyncValue<List<Workspace>>>
    implements WorkspaceNotifier {
  _FakeWorkspaceNotifier(Workspace? ws)
      : super(AsyncValue.data(ws != null ? [ws] : []));

  @override
  Ref get ref => throw UnimplementedError();

  @override
  WorkspaceErrorInfo? lastError;

  @override
  bool get isOfflineMode => false;

  @override
  Future<void> loadWorkspaces() async {}

  @override
  Future<Workspace?> createWorkspace(String name, String? description, {String type = 'personal'}) async {
    return null;
  }

  @override
  Future<Workspace?> joinWorkspace(String inviteCode) async {
    return null;
  }

  @override
  Future<String?> regenerateInviteCode(String workspaceId) async {
    return null;
  }

  @override
  Future<bool> transferOwnership(String workspaceId, String newOwnerId) async {
    return false;
  }
}

final _testWorkspace = Workspace(
  id: 'ws-test-1',
  name: 'Test Workspace',
  description: 'For testing',
  createdAt: DateTime(2026, 5, 21),
);

void main() {
  group('ChatPage responsive layout', () {
    testWidgets('shows placeholder when no workspace selected',
        (tester) async {
      await tester.pumpWidget(_buildTestApp(
        screenSize: const Size(400, 800),
        selectedWorkspace: null,
      ));
      await tester.pumpAndSettle();

      expect(find.text('请先选择工作区'), findsOneWidget);
    });

    testWidgets('compact mode (<600px): has AppBar with menu button',
        (tester) async {
      await tester.pumpWidget(_buildTestApp(
        screenSize: const Size(400, 800),
        selectedWorkspace: _testWorkspace,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.byType(VerticalDivider), findsNothing);
    });

    testWidgets('compact mode: Drawer opens on menu tap', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        screenSize: const Size(400, 800),
        selectedWorkspace: _testWorkspace,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('新对话'), findsOneWidget);
    });

    testWidgets('wide mode (>=600px): no AppBar, has VerticalDivider',
        (tester) async {
      await tester.pumpWidget(_buildTestApp(
        screenSize: const Size(1024, 768),
        selectedWorkspace: _testWorkspace,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('wide mode: conversation panel visible inline',
        (tester) async {
      await tester.pumpWidget(_buildTestApp(
        screenSize: const Size(1024, 768),
        selectedWorkspace: _testWorkspace,
      ));
      await tester.pumpAndSettle();

      expect(find.text('新对话'), findsOneWidget);
      expect(find.text('暂无对话'), findsOneWidget);
    });

    testWidgets('compact mode: AppBar shows workspace name', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        screenSize: const Size(400, 800),
        selectedWorkspace: _testWorkspace,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Test Workspace'), findsOneWidget);
    });

    testWidgets('compact mode: input bar present', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        screenSize: const Size(400, 800),
        selectedWorkspace: _testWorkspace,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('compact mode: workspace bar NOT visible', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        screenSize: const Size(400, 800),
        selectedWorkspace: _testWorkspace,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.workspaces_outlined), findsNothing);
    });

    testWidgets('wide mode: workspace bar IS visible', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        screenSize: const Size(1024, 768),
        selectedWorkspace: _testWorkspace,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.workspaces_outlined), findsOneWidget);
    });
  });
}
