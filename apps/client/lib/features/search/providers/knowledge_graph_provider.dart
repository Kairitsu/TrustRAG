import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/workspace_provider.dart';

class GraphNode {
  final String id;
  final String label;
  final String entityType;
  final String? documentId;
  final String? graphLayer;
  Offset position;
  Offset velocity;

  GraphNode({
    required this.id,
    required this.label,
    required this.entityType,
    this.documentId,
    this.graphLayer,
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
    );
  }

  Color get color {
    return switch (entityType.toLowerCase()) {
      'person' || 'people' => Colors.blue,
      'organization' || 'org' || 'company' => Colors.purple,
      'location' || 'place' => Colors.green,
      'concept' || 'topic' => Colors.orange,
      'event' => Colors.red,
      'document' => Colors.teal,
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
  final String? sourceDocumentId;
  final String? graphLayer;

  GraphEdge({
    required this.id,
    required this.source,
    required this.target,
    required this.relation,
    required this.weight,
    this.description,
    this.sourceDocumentId,
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
      sourceDocumentId: json['source_document_id'],
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
}

class EntityInfo {
  final String id;
  final String name;
  final String entityType;
  final String? documentId;
  final Map<String, dynamic> metadata;
  final String createdAt;

  EntityInfo({
    required this.id,
    required this.name,
    required this.entityType,
    this.documentId,
    required this.metadata,
    required this.createdAt,
  });

  factory EntityInfo.fromJson(Map<String, dynamic> json) {
    return EntityInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      entityType: json['entity_type'] ?? '',
      documentId: json['document_id'],
      metadata: json['metadata'] is Map ? json['metadata'] as Map<String, dynamic> : {},
      createdAt: json['created_at'] ?? '',
    );
  }
}

final knowledgeGraphServiceProvider = Provider<KnowledgeGraphService>((ref) {
  return KnowledgeGraphService(ref);
});

class KnowledgeGraphService {
  final Ref ref;
  KnowledgeGraphService(this.ref);

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

  Future<Map<String, dynamic>> generateForDocument(String workspaceId, String documentId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.post('/workspaces/$workspaceId/knowledge-graph/generate/$documentId');
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> generateForAll(String workspaceId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.post('/workspaces/$workspaceId/knowledge-graph/generate-all');
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getGenerationStatus(String workspaceId, String taskId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get('/workspaces/$workspaceId/knowledge-graph/generation-status/$taskId');
    return resp.data as Map<String, dynamic>;
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

  // ── Entity CRUD ──

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

  // ── Relation CRUD ──

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

  // ── Merge ──

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

  Future<Map<String, dynamic>> buildDocumentLayer(String workspaceId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.post(
      '/workspaces/$workspaceId/knowledge-graph/build-document-layer',
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> buildSemanticLayer(String workspaceId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.post(
      '/workspaces/$workspaceId/knowledge-graph/build-semantic-layer',
    );
    return resp.data as Map<String, dynamic>;
  }
}

class GraphStats {
  final int totalEntities;
  final int totalRelations;
  final List<TypeCount> entityTypes;
  final List<TypeCount> relationTypes;

  GraphStats({
    required this.totalEntities,
    required this.totalRelations,
    required this.entityTypes,
    required this.relationTypes,
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

final selectedGraphLayersProvider = StateProvider<Set<String>>((ref) {
  return {'document', 'semantic', 'knowledge'};
});

final graphDataProvider =
    FutureProvider.autoDispose<GraphData?>((ref) async {
  final ws = ref.watch(selectedWorkspaceProvider);
  if (ws == null) return null;
  final layers = ref.watch(selectedGraphLayersProvider);
  final service = ref.read(knowledgeGraphServiceProvider);
  final allLayers = {'document', 'semantic', 'knowledge'};
  final filterLayers = layers.length < allLayers.length ? layers.toList() : null;
  final data = await service.getGraph(ws.id, layers: filterLayers);
  _initializePositions(data);
  return data;
});

final entityListProvider =
    FutureProvider.autoDispose<List<EntityInfo>>((ref) async {
  final ws = ref.watch(selectedWorkspaceProvider);
  if (ws == null) return [];
  final service = ref.read(knowledgeGraphServiceProvider);
  return service.listEntities(ws.id);
});

void _initializePositions(GraphData data) {
  final rng = Random(42);
  const radius = 300.0;
  final count = data.nodes.length;
  for (var i = 0; i < count; i++) {
    final angle = (2 * pi * i) / count;
    final r = radius * (0.5 + rng.nextDouble() * 0.5);
    data.nodes[i].position = Offset(
      400 + r * cos(angle),
      300 + r * sin(angle),
    );
    data.nodes[i].velocity = Offset.zero;
  }
}
