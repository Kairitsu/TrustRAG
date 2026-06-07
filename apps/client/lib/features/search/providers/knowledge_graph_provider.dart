import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/workspace_provider.dart';
import 'graph_filter_provider.dart';
import 'graph_generation_controller.dart';

class GraphNode {
  final String id;
  final String label;
  final String entityType;
  final String? documentId;
  final String? graphLayer;
  final String? originalName;
  final String? displayName;
  final String? originalLanguage;
  final List<String>? aliases;
  final String? description;
  final String? jurisdiction;
  Offset position;
  Offset velocity;

  GraphNode({
    required this.id,
    required this.label,
    required this.entityType,
    this.documentId,
    this.graphLayer,
    this.originalName,
    this.displayName,
    this.originalLanguage,
    this.aliases,
    this.description,
    this.jurisdiction,
    this.position = Offset.zero,
    this.velocity = Offset.zero,
  });

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    return GraphNode(
      id: json['id'] ?? '',
      label: json['label'] ?? '',
      entityType: json['entity_type'] ?? '',
      documentId: json['document_id'],
      graphLayer: json['graph_layer'],
      originalName: json['original_name'],
      displayName: json['display_name'],
      originalLanguage: json['original_language'],
      aliases: (json['aliases'] as List?)?.map((e) => e.toString()).toList(),
      description: json['description'],
      jurisdiction: json['jurisdiction'],
    );
  }

  Color get color {
    return switch (entityType.toLowerCase()) {
      'regulator' => Colors.indigo,
      'law' => Colors.deepPurple,
      'jurisdiction' => Colors.teal,
      'stablecoin' => Colors.blue,
      'issuer' || 'exchange' => Colors.purple,
      'bank' => Colors.cyan,
      'license' => Colors.amber.shade700,
      'reserve_asset' => Colors.green,
      'requirement' || 'reporting_obligation' => Colors.orange,
      'prohibition' || 'sanction' => Colors.red,
      'risk' => Colors.deepOrange,
      'aml_cft_rule' || 'consumer_protection' => Colors.brown,
      'supervision_measure' => Colors.blueGrey,
      'document' => Colors.teal.shade300,
      'event' => Colors.pink,
      'person' || 'people' => Colors.blue,
      'organization' || 'org' || 'company' => Colors.purple,
      'location' || 'place' => Colors.green,
      'concept' || 'topic' => Colors.orange,
      'technology' || 'tool' => Colors.indigo,
      _ => Colors.grey,
    };
  }
}

class GraphEdge {
  final String id;
  final String source;
  final String target;
  final String relation;
  final double weight;
  final String? description;
  final String? evidenceText;
  final String? sourceDocumentId;
  final String? sourceChunkId;
  final String? graphLayer;

  GraphEdge({
    required this.id,
    required this.source,
    required this.target,
    required this.relation,
    required this.weight,
    this.description,
    this.evidenceText,
    this.sourceDocumentId,
    this.sourceChunkId,
    this.graphLayer,
  });

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    return GraphEdge(
      id: json['id'] ?? '',
      source: json['source'] ?? '',
      target: json['target'] ?? '',
      relation: json['relation'] ?? '',
      weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
      description: json['description'],
      evidenceText: json['evidence_text'],
      sourceDocumentId: json['source_document_id'],
      sourceChunkId: json['source_chunk_id'],
      graphLayer: json['graph_layer'],
    );
  }
}

class GraphData {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  GraphData({required this.nodes, required this.edges});

  factory GraphData.fromJson(Map<String, dynamic> json) {
    return GraphData(
      nodes: (json['nodes'] as List? ?? [])
          .map((e) => GraphNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      edges: (json['edges'] as List? ?? [])
          .map((e) => GraphEdge.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  GraphData copyWithPositions() {
    return GraphData(
      nodes: nodes.map((n) => GraphNode(
        id: n.id,
        label: n.label,
        entityType: n.entityType,
        documentId: n.documentId,
        graphLayer: n.graphLayer,
        originalName: n.originalName,
        displayName: n.displayName,
        originalLanguage: n.originalLanguage,
        aliases: n.aliases,
        description: n.description,
        jurisdiction: n.jurisdiction,
        position: n.position,
        velocity: n.velocity,
      )).toList(),
      edges: edges,
    );
  }
}

class EntityInfo {
  final String id;
  final String name;
  final String entityType;
  final String? documentId;
  final Map<String, dynamic> metadata;
  final String createdAt;
  final String? entityKey;
  final String? originalName;
  final String? displayName;
  final String? originalLanguage;
  final List<String>? aliases;
  final String? graphLayer;

  EntityInfo({
    required this.id,
    required this.name,
    required this.entityType,
    this.documentId,
    required this.metadata,
    required this.createdAt,
    this.entityKey,
    this.originalName,
    this.displayName,
    this.originalLanguage,
    this.aliases,
    this.graphLayer,
  });

  factory EntityInfo.fromJson(Map<String, dynamic> json) {
    return EntityInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? json['display_name'] ?? '',
      entityType: json['entity_type'] ?? '',
      documentId: json['document_id'],
      metadata: json['metadata'] is Map ? json['metadata'] as Map<String, dynamic> : {},
      createdAt: json['created_at'] ?? '',
      entityKey: json['entity_key'],
      originalName: json['original_name'],
      displayName: json['display_name'],
      originalLanguage: json['original_language'],
      aliases: (json['aliases'] as List?)?.map((e) => e.toString()).toList(),
      graphLayer: json['graph_layer'],
    );
  }
}

final knowledgeGraphServiceProvider = Provider<KnowledgeGraphService>((ref) {
  return KnowledgeGraphService(ref);
});

class KnowledgeGraphService {
  final Ref ref;
  KnowledgeGraphService(this.ref);

  String _targetLanguage() {
    final locale = ref.read(localeProvider);
    return switch (locale?.languageCode) {
      'zh' => 'zh',
      'ja' => 'ja',
      'ko' => 'ko',
      _ => 'en',
    };
  }

  Future<GraphData> getGraph(String workspaceId, {List<String>? layers}) async {
    final api = ref.read(apiClientProvider);
    final queryParams = <String, dynamic>{};
    if (layers != null && layers.isNotEmpty) {
      queryParams['layers'] = layers.join(',');
    }
    final resp = await api.dio.get(
      '/workspaces/$workspaceId/knowledge-graph',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    return GraphData.fromJson(resp.data);
  }

  Future<List<EntityInfo>> listEntities(String workspaceId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get('/workspaces/$workspaceId/knowledge-graph/entities');
    return (resp.data as List)
        .map((e) => EntityInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<EntityInfo>> searchEntities(String workspaceId, String query) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get(
      '/workspaces/$workspaceId/knowledge-graph/entities/search',
      queryParameters: {'q': query, 'limit': 20},
    );
    return (resp.data as List)
        .map((e) => EntityInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> generateForDocument(String workspaceId, String documentId, {String? targetLanguage}) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.post(
      '/workspaces/$workspaceId/knowledge-graph/generate/$documentId',
      data: {'target_language': targetLanguage ?? _targetLanguage()},
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> generateForAll(String workspaceId, {String? targetLanguage}) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.post(
      '/workspaces/$workspaceId/knowledge-graph/generate-all',
      data: {'target_language': targetLanguage ?? _targetLanguage()},
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<GenerationJobState> getGenerationStatus(String workspaceId, String taskId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get('/workspaces/$workspaceId/knowledge-graph/generation-status/$taskId');
    return GenerationJobState.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<GenerationJobState?> getActiveGeneration(String workspaceId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get('/workspaces/$workspaceId/knowledge-graph/generation-active');
    if (resp.data == null) return null;
    return GenerationJobState.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> cancelGeneration(String workspaceId, String taskId) async {
    final api = ref.read(apiClientProvider);
    await api.dio.post('/workspaces/$workspaceId/knowledge-graph/generation-status/$taskId/cancel');
  }

  Future<List<GenerationLogEntry>> getGenerationHistory(String workspaceId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get('/workspaces/$workspaceId/knowledge-graph/generation-history');
    return (resp.data as List)
        .map((e) => GenerationLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> resetGraph(String workspaceId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.delete('/workspaces/$workspaceId/knowledge-graph/reset');
    return resp.data as Map<String, dynamic>;
  }

  Future<GraphStats> getStats(String workspaceId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get('/workspaces/$workspaceId/knowledge-graph/stats');
    return GraphStats.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> createEntity(String workspaceId, {
    required String name,
    required String entityType,
    String? documentId,
    String? description,
  }) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.post(
      '/workspaces/$workspaceId/knowledge-graph/entities/new',
      data: {
        'name': name,
        'entity_type': entityType,
        if (documentId != null) 'document_id': documentId,
        if (description != null) 'description': description,
      },
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateEntity(String workspaceId, String entityId, {
    String? name,
    String? entityType,
  }) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.put(
      '/workspaces/$workspaceId/knowledge-graph/entities/$entityId',
      data: {
        if (name != null) 'name': name,
        if (entityType != null) 'entity_type': entityType,
      },
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteEntity(String workspaceId, String entityId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.delete(
      '/workspaces/$workspaceId/knowledge-graph/entities/$entityId',
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createRelation(String workspaceId, {
    required String sourceEntityId,
    required String targetEntityId,
    required String relationType,
    double weight = 1.0,
    String? description,
  }) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.post(
      '/workspaces/$workspaceId/knowledge-graph/relations/new',
      data: {
        'source_entity_id': sourceEntityId,
        'target_entity_id': targetEntityId,
        'relation_type': relationType,
        'weight': weight,
        if (description != null) 'description': description,
      },
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateRelation(String workspaceId, String relationId, {
    String? relationType,
    double? weight,
    String? description,
  }) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.put(
      '/workspaces/$workspaceId/knowledge-graph/relations/$relationId',
      data: {
        if (relationType != null) 'relation_type': relationType,
        if (weight != null) 'weight': weight,
        if (description != null) 'description': description,
      },
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteRelation(String workspaceId, String relationId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.delete(
      '/workspaces/$workspaceId/knowledge-graph/relations/$relationId',
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> mergeEntities(String workspaceId, {
    required String keepEntityId,
    required List<String> mergeEntityIds,
  }) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.post(
      '/workspaces/$workspaceId/knowledge-graph/entities/merge',
      data: {
        'keep_entity_id': keepEntityId,
        'merge_entity_ids': mergeEntityIds,
      },
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> buildDocumentLayer(String workspaceId, {String? targetLanguage}) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.post(
      '/workspaces/$workspaceId/knowledge-graph/build-document-layer',
      data: {'target_language': targetLanguage ?? _targetLanguage()},
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> buildSemanticLayer(String workspaceId, {String? targetLanguage}) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.post(
      '/workspaces/$workspaceId/knowledge-graph/build-semantic-layer',
      data: {'target_language': targetLanguage ?? _targetLanguage()},
    );
    return resp.data as Map<String, dynamic>;
  }
}

class GraphStats {
  final int totalEntities;
  final int totalRelations;
  final List<TypeCount> entityTypes;
  final List<TypeCount> relationTypes;
  final List<LayerStatEntry> layerStats;

  GraphStats({
    required this.totalEntities,
    required this.totalRelations,
    required this.entityTypes,
    required this.relationTypes,
    this.layerStats = const [],
  });

  factory GraphStats.fromJson(Map<String, dynamic> json) {
    return GraphStats(
      totalEntities: json['entity_count'] ?? json['total_entities'] ?? 0,
      totalRelations: json['relation_count'] ?? json['total_relations'] ?? 0,
      entityTypes: (json['entity_types'] as List? ?? [])
          .map((e) => TypeCount.fromJson(e as Map<String, dynamic>))
          .toList(),
      relationTypes: (json['relation_types'] as List? ?? [])
          .map((e) => TypeCount.fromJson(e as Map<String, dynamic>))
          .toList(),
      layerStats: (json['layer_stats'] as List? ?? [])
          .map((e) => LayerStatEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class LayerStatEntry {
  final String layer;
  final int entityCount;
  final int relationCount;

  LayerStatEntry({required this.layer, required this.entityCount, required this.relationCount});

  factory LayerStatEntry.fromJson(Map<String, dynamic> json) {
    return LayerStatEntry(
      layer: json['layer'] ?? '',
      entityCount: json['entity_count'] ?? 0,
      relationCount: json['relation_count'] ?? 0,
    );
  }
}

class TypeCount {
  final String typeName;
  final int count;

  TypeCount({required this.typeName, required this.count});

  factory TypeCount.fromJson(Map<String, dynamic> json) {
    return TypeCount(
      typeName: json['name'] ?? json['type_name'] ?? '',
      count: json['count'] ?? 0,
    );
  }
}

class GenerationLogEntry {
  final String id;
  final String status;
  final String triggerType;
  final String? jobType;
  final String? layerType;
  final String? targetLanguage;
  final String? documentId;
  final String? llmProvider;
  final String? llmModel;
  final int totalDocuments;
  final int processedDocuments;
  final int succeededDocuments;
  final int failedDocuments;
  final int entitiesCreated;
  final int relationsCreated;
  final int relationsSkippedMatch;
  final List<String> errors;
  final List<String> warnings;
  final String startedAt;
  final String? completedAt;
  final int? elapsedMs;

  GenerationLogEntry({
    required this.id,
    required this.status,
    required this.triggerType,
    this.jobType,
    this.layerType,
    this.targetLanguage,
    this.documentId,
    this.llmProvider,
    this.llmModel,
    required this.totalDocuments,
    required this.processedDocuments,
    this.succeededDocuments = 0,
    this.failedDocuments = 0,
    required this.entitiesCreated,
    required this.relationsCreated,
    this.relationsSkippedMatch = 0,
    required this.errors,
    this.warnings = const [],
    required this.startedAt,
    this.completedAt,
    this.elapsedMs,
  });

  factory GenerationLogEntry.fromJson(Map<String, dynamic> json) {
    return GenerationLogEntry(
      id: json['id'] ?? '',
      status: json['status'] ?? '',
      triggerType: json['trigger_type'] ?? 'manual_batch',
      jobType: json['job_type'],
      layerType: json['layer_type'],
      targetLanguage: json['target_language'],
      documentId: json['document_id'],
      llmProvider: json['llm_provider'],
      llmModel: json['llm_model'],
      totalDocuments: json['total_documents'] ?? 0,
      processedDocuments: json['processed_documents'] ?? 0,
      succeededDocuments: json['succeeded_documents'] ?? 0,
      failedDocuments: json['failed_documents'] ?? 0,
      entitiesCreated: json['entities_created'] ?? 0,
      relationsCreated: json['relations_created'] ?? 0,
      relationsSkippedMatch: json['relations_skipped_match'] ?? 0,
      errors: (json['errors'] as List?)?.map((e) => e.toString()).toList() ?? [],
      warnings: (json['warnings'] as List?)?.map((e) => e.toString()).toList() ?? [],
      startedAt: json['started_at'] ?? '',
      completedAt: json['completed_at'],
      elapsedMs: json['elapsed_ms'],
    );
  }
}

final generationHistoryProvider =
    FutureProvider.autoDispose<List<GenerationLogEntry>>((ref) async {
  final ws = ref.watch(selectedWorkspaceProvider);
  if (ws == null) return [];
  final service = ref.read(knowledgeGraphServiceProvider);
  return service.getGenerationHistory(ws.id);
});

final knowledgeGraphStatsProvider = FutureProvider.autoDispose<GraphStats?>((ref) async {
  final ws = ref.watch(selectedWorkspaceProvider);
  if (ws == null) return null;
  ref.watch(graphGenerationControllerProvider);
  final service = ref.read(knowledgeGraphServiceProvider);
  return service.getStats(ws.id);
});

final layerStatsProvider = FutureProvider.autoDispose<LayerStatsMap?>((ref) async {
  final stats = await ref.watch(knowledgeGraphStatsProvider.future);
  if (stats == null) return null;
  final map = <String, LayerStat>{};
  for (final layer in ['document', 'semantic', 'knowledge']) {
    final entry = stats.layerStats.where((l) => l.layer == layer).firstOrNull;
    map[layer] = LayerStat(
      layer: layer,
      entityCount: entry?.entityCount ?? 0,
      relationCount: entry?.relationCount ?? 0,
      generated: (entry?.entityCount ?? 0) > 0 || (entry?.relationCount ?? 0) > 0,
    );
  }
  return LayerStatsMap(map);
});

/// Raw graph data — always fetches all layers; filtering applied separately.
final graphDataProvider = FutureProvider<GraphData?>((ref) async {
  final ws = ref.watch(selectedWorkspaceProvider);
  if (ws == null) return null;
  ref.watch(graphGenerationControllerProvider);
  final service = ref.read(knowledgeGraphServiceProvider);
  return service.getGraph(ws.id);
});

final filteredGraphProvider = Provider<AsyncValue<FilteredGraphData?>>((ref) {
  final graphAsync = ref.watch(graphDataProvider);
  final filter = ref.watch(graphFilterProvider);
  return graphAsync.whenData((data) {
    if (data == null) return null;
    return applyFilters(data, filter);
  });
});

final entityListProvider = FutureProvider<List<EntityInfo>>((ref) async {
  final ws = ref.watch(selectedWorkspaceProvider);
  if (ws == null) return [];
  ref.watch(graphGenerationControllerProvider);
  final service = ref.read(knowledgeGraphServiceProvider);
  return service.listEntities(ws.id);
});

/// Backward-compatible alias
final selectedGraphLayersProvider = Provider<Set<String>>((ref) {
  return ref.watch(graphFilterProvider).visibleLayers;
});