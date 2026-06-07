import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/providers/workspace_provider.dart';
import 'knowledge_graph_provider.dart';

class GenerationJobState {
  final String? taskId;
  final String status;
  final String jobType;
  final double progressPercent;
  final int totalDocuments;
  final int processedDocuments;
  final int succeededDocuments;
  final int failedDocuments;
  final int entitiesCreated;
  final int relationsCreated;
  final int relationsSkippedMatch;
  final String? currentDocumentTitle;
  final List<String> errors;
  final List<String> warnings;
  final int? elapsedMs;
  final bool isPolling;

  const GenerationJobState({
    this.taskId,
    this.status = 'idle',
    this.jobType = '',
    this.progressPercent = 0,
    this.totalDocuments = 0,
    this.processedDocuments = 0,
    this.succeededDocuments = 0,
    this.failedDocuments = 0,
    this.entitiesCreated = 0,
    this.relationsCreated = 0,
    this.relationsSkippedMatch = 0,
    this.currentDocumentTitle,
    this.errors = const [],
    this.warnings = const [],
    this.elapsedMs,
    this.isPolling = false,
  });

  bool get isActive =>
      status == 'running' || status == 'cancelling';

  bool get isFinished =>
      status == 'completed' || status == 'failed' || status == 'cancelled';

  GenerationJobState copyWith({
    String? taskId,
    String? status,
    String? jobType,
    double? progressPercent,
    int? totalDocuments,
    int? processedDocuments,
    int? succeededDocuments,
    int? failedDocuments,
    int? entitiesCreated,
    int? relationsCreated,
    int? relationsSkippedMatch,
    String? currentDocumentTitle,
    List<String>? errors,
    List<String>? warnings,
    int? elapsedMs,
    bool? isPolling,
  }) {
    return GenerationJobState(
      taskId: taskId ?? this.taskId,
      status: status ?? this.status,
      jobType: jobType ?? this.jobType,
      progressPercent: progressPercent ?? this.progressPercent,
      totalDocuments: totalDocuments ?? this.totalDocuments,
      processedDocuments: processedDocuments ?? this.processedDocuments,
      succeededDocuments: succeededDocuments ?? this.succeededDocuments,
      failedDocuments: failedDocuments ?? this.failedDocuments,
      entitiesCreated: entitiesCreated ?? this.entitiesCreated,
      relationsCreated: relationsCreated ?? this.relationsCreated,
      relationsSkippedMatch: relationsSkippedMatch ?? this.relationsSkippedMatch,
      currentDocumentTitle: currentDocumentTitle ?? this.currentDocumentTitle,
      errors: errors ?? this.errors,
      warnings: warnings ?? this.warnings,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      isPolling: isPolling ?? this.isPolling,
    );
  }

  factory GenerationJobState.fromJson(Map<String, dynamic> json) {
    return GenerationJobState(
      taskId: json['task_id'] as String?,
      status: json['status'] as String? ?? 'idle',
      jobType: json['job_type'] as String? ?? '',
      progressPercent: (json['progress_percent'] as num?)?.toDouble() ?? 0,
      totalDocuments: json['total_documents'] as int? ?? 0,
      processedDocuments: json['processed_documents'] as int? ?? 0,
      succeededDocuments: json['succeeded_documents'] as int? ?? 0,
      failedDocuments: json['failed_documents'] as int? ?? 0,
      entitiesCreated: json['entities_created'] as int? ?? 0,
      relationsCreated: json['relations_created'] as int? ?? 0,
      relationsSkippedMatch: json['relations_skipped_match'] as int? ?? 0,
      currentDocumentTitle: json['current_document_title'] as String?,
      errors: (json['errors'] as List?)?.map((e) => e.toString()).toList() ?? [],
      warnings: (json['warnings'] as List?)?.map((e) => e.toString()).toList() ?? [],
      elapsedMs: json['elapsed_ms'] as int?,
    );
  }
}

final graphGenerationControllerProvider =
    StateNotifierProvider<GraphGenerationController, GenerationJobState>((ref) {
  return GraphGenerationController(ref);
});

class GraphGenerationController extends StateNotifier<GenerationJobState> {
  final Ref ref;
  Timer? _pollTimer;
  String? _workspaceId;

  GraphGenerationController(this.ref) : super(const GenerationJobState()) {
    ref.listen(selectedWorkspaceProvider, (prev, next) {
      if (next?.id != _workspaceId) {
        _stopPolling();
        _workspaceId = next?.id;
        if (next != null) {
          _restoreActiveTask(next.id);
        } else {
          state = const GenerationJobState();
        }
      }
    });
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws != null) {
      _workspaceId = ws.id;
      _restoreActiveTask(ws.id);
    }
  }

  Future<void> _restoreActiveTask(String wsId) async {
    try {
      final service = ref.read(knowledgeGraphServiceProvider);
      final active = await service.getActiveGeneration(wsId);
      if (active != null && active.isActive) {
        state = active.copyWith(isPolling: true);
        _startPolling(wsId, active.taskId!);
      }
    } catch (_) {}
  }

  void _startPolling(String wsId, String taskId) {
    _stopPolling();
    state = state.copyWith(isPolling: true, taskId: taskId);
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _pollOnce(wsId, taskId);
    });
    _pollOnce(wsId, taskId);
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollOnce(String wsId, String taskId) async {
    try {
      final service = ref.read(knowledgeGraphServiceProvider);
      final status = await service.getGenerationStatus(wsId, taskId);
      state = status.copyWith(isPolling: true, taskId: taskId);

      ref.invalidate(graphDataProvider);
      ref.invalidate(entityListProvider);
      ref.invalidate(knowledgeGraphStatsProvider);
      ref.invalidate(layerStatsProvider);

      if (status.isFinished) {
        _stopPolling();
        state = status.copyWith(isPolling: false);
      }
    } catch (_) {
      _stopPolling();
      state = state.copyWith(isPolling: false);
    }
  }

  Future<String?> startKnowledgeGeneration(String wsId, String targetLanguage) async {
    final service = ref.read(knowledgeGraphServiceProvider);
    final result = await service.generateForAll(wsId, targetLanguage: targetLanguage);
    final taskId = result['task_id'] as String?;
    if (taskId == null || taskId.isEmpty) return null;
    state = GenerationJobState(
      taskId: taskId,
      status: result['status'] as String? ?? 'running',
      jobType: 'knowledge_batch',
      totalDocuments: result['total_documents'] as int? ?? 0,
      isPolling: true,
    );
    _startPolling(wsId, taskId);
    return taskId;
  }

  Future<String?> startLayerGeneration(String wsId, String layer, String targetLanguage) async {
    final service = ref.read(knowledgeGraphServiceProvider);
    final Map<String, dynamic> result;
    if (layer == 'document') {
      result = await service.buildDocumentLayer(wsId, targetLanguage: targetLanguage);
    } else {
      result = await service.buildSemanticLayer(wsId, targetLanguage: targetLanguage);
    }
    final taskId = result['task_id'] as String?;
    if (taskId == null || taskId.isEmpty) return null;
    state = GenerationJobState(
      taskId: taskId,
      status: result['status'] as String? ?? 'running',
      jobType: layer == 'document' ? 'document_layer' : 'semantic_layer',
      totalDocuments: 1,
      isPolling: true,
    );
    _startPolling(wsId, taskId);
    return taskId;
  }

  Future<void> cancelCurrent(String wsId) async {
    final taskId = state.taskId;
    if (taskId == null) return;
    final service = ref.read(knowledgeGraphServiceProvider);
    await service.cancelGeneration(wsId, taskId);
    state = state.copyWith(status: 'cancelling');
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}