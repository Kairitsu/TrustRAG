import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/dev_mode_provider.dart';
import '../../auth/providers/auth_provider.dart';

const _sentinel = Object();

class Document {
  final String id;
  final String workspaceId;
  final String originalFilename;
  final String fileType;
  final int fileSize;
  final String processingStatus;
  final String? processingError;
  final int? chunkCount;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  Document({
    required this.id,
    required this.workspaceId,
    required this.originalFilename,
    required this.fileType,
    required this.fileSize,
    required this.processingStatus,
    this.processingError,
    this.chunkCount,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isProcessing =>
      processingStatus == 'processing' ||
      processingStatus == 'chunking' ||
      processingStatus == 'embedding' ||
      processingStatus == 'pending';

  bool get isStale =>
      isProcessing &&
      DateTime.now().difference(updatedAt).inMinutes > 5;

  factory Document.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    List<String> parsedTags = [];
    if (rawTags is List) {
      parsedTags = rawTags.map((e) => e.toString()).toList();
    }
    return Document(
      id: json['id'],
      workspaceId: json['workspace_id'],
      originalFilename: json['original_filename'],
      fileType: json['file_type'] ?? 'unknown',
      fileSize: json['file_size_bytes'] ?? json['file_size'] ?? 0,
      processingStatus: json['processing_status'] ?? 'pending',
      processingError: json['processing_error'],
      chunkCount: json['chunk_count'],
      tags: parsedTags,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.parse(json['created_at']),
    );
  }

  Document copyWith({
    List<String>? tags,
    String? processingStatus,
    Object? processingError = _sentinel,
  }) {
    return Document(
      id: id,
      workspaceId: workspaceId,
      originalFilename: originalFilename,
      fileType: fileType,
      fileSize: fileSize,
      processingStatus: processingStatus ?? this.processingStatus,
      processingError: processingError == _sentinel ? this.processingError : processingError as String?,
      chunkCount: chunkCount,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class DocumentNotifier extends StateNotifier<AsyncValue<List<Document>>> {
  final Ref ref;

  DocumentNotifier(this.ref) : super(const AsyncValue.data([]));

  Future<void> loadDocuments(String workspaceId) async {
    DebugLogBuffer().add('DOC 加载文档列表: workspace=$workspaceId');
    state = const AsyncValue.loading();
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/workspaces/$workspaceId/documents');
      final data = resp.data;
      final items = data is List ? data : (data['items'] ?? []);
      final list = (items as List).map((j) => Document.fromJson(j)).toList();
      final statusSummary = <String, int>{};
      for (final d in list) {
        statusSummary[d.processingStatus] = (statusSummary[d.processingStatus] ?? 0) + 1;
      }
      DebugLogBuffer().add('DOC 加载完成: ${list.length}个文档, 状态分布: $statusSummary');
      state = AsyncValue.data(list);
    } catch (e, st) {
      DebugLogBuffer().add('ERROR DOC 加载失败: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<bool> uploadDocument(String workspaceId, List<int> bytes, String filename) async {
    final sizeKb = (bytes.length / 1024).toStringAsFixed(1);
    DebugLogBuffer().add('DOC 上传开始: $filename (${sizeKb}KB)');
    try {
      final api = ref.read(apiClientProvider);
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      await api.dio.post(
        '/workspaces/$workspaceId/documents',
        data: formData,
      );
      DebugLogBuffer().add('DOC 上传成功: $filename');
      await loadDocuments(workspaceId);
      return true;
    } catch (e) {
      DebugLogBuffer().add('ERROR DOC 上传失败: $filename — $e');
      return false;
    }
  }

  Future<bool> deleteDocument(String workspaceId, String docId) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.delete('/workspaces/$workspaceId/documents/$docId');
      state = AsyncValue.data(
        (state.value ?? []).where((d) => d.id != docId).toList(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> reprocessDocument(String workspaceId, String docId) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('/workspaces/$workspaceId/documents/$docId/reprocess');
      final docs = state.value ?? [];
      state = AsyncValue.data(
        docs.map((d) => d.id == docId
            ? d.copyWith(processingStatus: 'pending', processingError: null)
            : d).toList(),
      );
      return true;
    } catch (e) {
      DebugLogBuffer().add('ERROR DOC 重新处理失败: $docId — $e');
      return false;
    }
  }

  Future<bool> updateTags(String workspaceId, String docId, List<String> tags) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.patch(
        '/workspaces/$workspaceId/documents/$docId',
        data: {'tags': tags},
      );
      final docs = state.value ?? [];
      state = AsyncValue.data(
        docs.map((d) => d.id == docId ? d.copyWith(tags: tags) : d).toList(),
      );
      return true;
    } catch (e) {
      DebugLogBuffer().add('ERROR DOC 更新标签失败: $docId — $e');
      return false;
    }
  }
}

final documentProvider =
    StateNotifierProvider<DocumentNotifier, AsyncValue<List<Document>>>((ref) {
  return DocumentNotifier(ref);
});

final selectedFolderProvider = StateProvider<String?>((ref) => null);
