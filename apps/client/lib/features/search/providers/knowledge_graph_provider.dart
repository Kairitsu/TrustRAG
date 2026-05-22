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
  Offset position;
  Offset velocity;

  GraphNode({
    required this.id,
    required this.label,
    required this.entityType,
    this.documentId,
    this.position = Offset.zero,
    this.velocity = Offset.zero,
  });

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    return GraphNode(
      id: json['id'] ?? '',
      label: json['label'] ?? '',
      entityType: json['entity_type'] ?? '',
      documentId: json['document_id'],
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
  final String source;
  final String target;
  final String relation;
  final double weight;

  GraphEdge({
    required this.source,
    required this.target,
    required this.relation,
    required this.weight,
  });

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    return GraphEdge(
      source: json['source'] ?? '',
      target: json['target'] ?? '',
      relation: json['relation'] ?? '',
      weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
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

  Future<GraphData> getGraph(String workspaceId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get('/workspaces/$workspaceId/knowledge-graph');
    return GraphData.fromJson(resp.data);
  }

  Future<List<EntityInfo>> listEntities(String workspaceId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get('/workspaces/$workspaceId/knowledge-graph/entities');
    return (resp.data as List)
        .map((e) => EntityInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final graphDataProvider =
    FutureProvider.autoDispose<GraphData?>((ref) async {
  final ws = ref.watch(selectedWorkspaceProvider);
  if (ws == null) return null;
  final service = ref.read(knowledgeGraphServiceProvider);
  final data = await service.getGraph(ws.id);
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
