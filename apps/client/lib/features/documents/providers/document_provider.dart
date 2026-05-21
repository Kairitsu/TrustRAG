import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/dev_mode_provider.dart';
import '../../auth/providers/auth_provider.dart';

class Document {
  final String id;
  final String workspaceId;
  final String originalFilename;
  final String fileType;
  final int fileSize;
  final String processingStatus;
  final String? processingError;
  final int? chunkCount;
  final DateTime createdAt;

  Document({
    required this.id,
    required this.workspaceId,
    required this.originalFilename,
    required this.fileType,
    required this.fileSize,
    required this.processingStatus,
    this.processingError,
    this.chunkCount,
    required this.createdAt,
  });

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id'],
      workspaceId: json['workspace_id'],
      originalFilename: json['original_filename'],
      fileType: json['file_type'] ?? 'unknown',
      fileSize: json['file_size_bytes'] ?? json['file_size'] ?? 0,
      processingStatus: json['processing_status'] ?? 'pending',
      processingError: json['processing_error'],
      chunkCount: json['chunk_count'],
      createdAt: DateTime.parse(json['created_at']),
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
}

final documentProvider =
    StateNotifierProvider<DocumentNotifier, AsyncValue<List<Document>>>((ref) {
  return DocumentNotifier(ref);
});
