import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chat/providers/chat_provider.dart';
import '../../features/dashboard/providers/workspace_provider.dart';
import '../../features/documents/providers/document_provider.dart';
import '../../features/review/providers/review_list_provider.dart';
import '../../features/search/providers/knowledge_graph_provider.dart';

/// Clears in-memory state tied to the current account or workspace.
void resetAccountScopedState(WidgetRef ref) {
  ref.read(selectedWorkspaceProvider.notifier).state = null;
  ref.read(selectedConversationProvider.notifier).state = null;
  ref.read(messagesProvider.notifier).state = [];
  ref.read(graphStatsProvider.notifier).state = {};
  ref.read(selectedFolderProvider.notifier).state = null;

  ref.invalidate(workspaceProvider);
  ref.invalidate(documentProvider);
  ref.invalidate(conversationProvider);
  ref.invalidate(reviewListNotifierProvider);
  ref.invalidate(graphDataProvider);
  ref.invalidate(entityListProvider);
  ref.invalidate(generationHistoryProvider);
}

/// Reload workspace list after login/register without importing workspace in auth.
void invalidateWorkspaceList(Ref ref) {
  ref.invalidate(workspaceProvider);
}

/// Same reset for [Ref] (e.g. StateNotifier without WidgetRef).
void resetAccountScopedStateFromRef(Ref ref) {
  ref.read(selectedWorkspaceProvider.notifier).state = null;
  ref.read(selectedConversationProvider.notifier).state = null;
  ref.read(messagesProvider.notifier).state = [];
  ref.read(graphStatsProvider.notifier).state = {};
  ref.read(selectedFolderProvider.notifier).state = null;

  ref.invalidate(workspaceProvider);
  ref.invalidate(documentProvider);
  ref.invalidate(conversationProvider);
  ref.invalidate(reviewListNotifierProvider);
  ref.invalidate(graphDataProvider);
  ref.invalidate(entityListProvider);
  ref.invalidate(generationHistoryProvider);
}