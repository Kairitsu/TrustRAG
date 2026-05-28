import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';

class Conversation {
  final String id;
  final String workspaceId;
  final String? title;
  final DateTime updatedAt;

  Conversation({
    required this.id,
    required this.workspaceId,
    this.title,
    required this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'],
      workspaceId: json['workspace_id'],
      title: json['title'],
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}

class Citation {
  final String id;
  final int index;
  final String chunkId;
  final String documentId;
  final String? heading;
  final int? page;
  final double score;
  final String text;
  final int? embeddingRank;
  final double? rerankScore;

  Citation({
    required this.id,
    required this.index,
    required this.chunkId,
    required this.documentId,
    this.heading,
    this.page,
    required this.score,
    required this.text,
    this.embeddingRank,
    this.rerankScore,
  });

  factory Citation.fromJson(Map<String, dynamic> json) {
    return Citation(
      id: json['id'] ?? '',
      index: json['index'] ?? json['citation_index'] ?? 0,
      chunkId: json['chunk_id'] ?? '',
      documentId: json['document_id'] ?? '',
      heading: json['heading'] ?? json['heading_path'],
      page: json['page'] ?? json['page_number'],
      score: (json['score'] ?? json['relevance_score'] ?? 0).toDouble(),
      embeddingRank: json['embedding_rank'],
      rerankScore: (json['rerank_score'] as num?)?.toDouble(),
      text: json['text'] ?? json['quoted_text'] ?? '',
    );
  }
}

class ChatMessage {
  final String id;
  final String role;
  final String content;
  final String? modelName;
  final List<Citation> citations;
  final List<String> suggestions;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.modelName,
    this.citations = const [],
    this.suggestions = const [],
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final citationsJson = json['citations'] as List?;
    return ChatMessage(
      id: json['id'],
      role: json['role'],
      content: json['content'],
      modelName: json['model_name'],
      citations: citationsJson != null
          ? citationsJson.map((c) => Citation.fromJson(c as Map<String, dynamic>)).toList()
          : [],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  ChatMessage copyWith({
    List<Citation>? citations,
    List<String>? suggestions,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content,
      modelName: modelName,
      citations: citations ?? this.citations,
      suggestions: suggestions ?? this.suggestions,
      createdAt: createdAt,
    );
  }
}

class ConversationNotifier
    extends StateNotifier<AsyncValue<List<Conversation>>> {
  final Ref ref;

  ConversationNotifier(this.ref) : super(const AsyncValue.data([]));

  Future<void> loadConversations(String workspaceId) async {
    state = const AsyncValue.loading();
    try {
      final api = ref.read(apiClientProvider);
      final resp =
          await api.dio.get('/workspaces/$workspaceId/conversations');
      final list = (resp.data as List)
          .map((j) => Conversation.fromJson(j))
          .toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Conversation?> createConversation(
      String workspaceId, String? title) async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post(
        '/workspaces/$workspaceId/conversations',
        data: {'title': title ?? '新对话'},
      );
      final conv = Conversation.fromJson(resp.data);
      state = AsyncValue.data([conv, ...state.value ?? []]);
      return conv;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteConversation(
      String workspaceId, String convId) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio
          .delete('/workspaces/$workspaceId/conversations/$convId');
      state = AsyncValue.data(
        (state.value ?? []).where((c) => c.id != convId).toList(),
      );
    } catch (_) {}
  }
}

final conversationProvider = StateNotifierProvider<ConversationNotifier,
    AsyncValue<List<Conversation>>>((ref) {
  return ConversationNotifier(ref);
});

final selectedConversationProvider =
    StateProvider<Conversation?>((ref) => null);

final messagesProvider =
    StateProvider<List<ChatMessage>>((ref) => []);
