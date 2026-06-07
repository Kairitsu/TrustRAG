import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/features/search/providers/knowledge_graph_provider.dart';

void main() {
  group('GraphNode model', () {
    test('fromJson parses all fields including graph_layer', () {
      final json = {
        'id': 'n1',
        'label': 'Test Entity',
        'entity_type': 'person',
        'document_id': 'doc-123',
        'graph_layer': 'knowledge',
      };
      final node = GraphNode.fromJson(json);
      expect(node.id, 'n1');
      expect(node.label, 'Test Entity');
      expect(node.entityType, 'person');
      expect(node.documentId, 'doc-123');
      expect(node.graphLayer, 'knowledge');
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'n2',
        'label': 'Entity',
        'entity_type': 'concept',
      };
      final node = GraphNode.fromJson(json);
      expect(node.documentId, isNull);
      expect(node.graphLayer, isNull);
    });

    test('graph_layer values for different layers', () {
      for (final layer in ['document', 'semantic', 'knowledge']) {
        final node = GraphNode.fromJson({
          'id': 'n',
          'label': 'X',
          'entity_type': 'concept',
          'graph_layer': layer,
        });
        expect(node.graphLayer, layer);
      }
    });

    test('color mapping for known entity types', () {
      expect(GraphNode(id: '', label: '', entityType: 'person').color, Colors.blue);
      expect(GraphNode(id: '', label: '', entityType: 'organization').color, Colors.purple);
      expect(GraphNode(id: '', label: '', entityType: 'regulator').color, Colors.indigo);
      expect(GraphNode(id: '', label: '', entityType: 'stablecoin').color, Colors.blue);
      expect(GraphNode(id: '', label: '', entityType: 'prohibition').color, Colors.red);
      expect(GraphNode(id: '', label: '', entityType: 'document').color, Colors.teal.shade300);
      expect(GraphNode(id: '', label: '', entityType: 'unknown').color, Colors.grey);
    });
  });

  group('GraphEdge model', () {
    test('fromJson parses all fields including CRUD and layer fields', () {
      final json = {
        'id': 'rel-001',
        'source': 's1',
        'target': 't1',
        'relation': 'works_at',
        'weight': 0.85,
        'description': 'Employment relationship',
        'source_document_id': 'doc-xyz',
        'graph_layer': 'knowledge',
      };
      final edge = GraphEdge.fromJson(json);
      expect(edge.id, 'rel-001');
      expect(edge.source, 's1');
      expect(edge.target, 't1');
      expect(edge.relation, 'works_at');
      expect(edge.weight, 0.85);
      expect(edge.description, 'Employment relationship');
      expect(edge.sourceDocumentId, 'doc-xyz');
      expect(edge.graphLayer, 'knowledge');
    });

    test('fromJson defaults weight to 1.0', () {
      final json = {
        'source': 's1',
        'target': 't1',
        'relation': 'related',
      };
      final edge = GraphEdge.fromJson(json);
      expect(edge.weight, 1.0);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'source': 's1',
        'target': 't1',
        'relation': 'related',
        'weight': 0.5,
      };
      final edge = GraphEdge.fromJson(json);
      expect(edge.id, '');
      expect(edge.description, isNull);
      expect(edge.sourceDocumentId, isNull);
      expect(edge.graphLayer, isNull);
    });

    test('fromJson with null description and source_document_id', () {
      final json = {
        'id': 'rel-002',
        'source': 'a',
        'target': 'b',
        'relation': 'test',
        'weight': 0.7,
        'description': null,
        'source_document_id': null,
      };
      final edge = GraphEdge.fromJson(json);
      expect(edge.description, isNull);
      expect(edge.sourceDocumentId, isNull);
    });
  });

  group('GraphEdge CRUD data integrity', () {
    test('edge id is preserved for update/delete operations', () {
      final json = {
        'id': 'uuid-edge-123',
        'source': 'entity-a',
        'target': 'entity-b',
        'relation': 'related_to',
        'weight': 0.9,
      };
      final edge = GraphEdge.fromJson(json);
      expect(edge.id, 'uuid-edge-123');
      expect(edge.id.isNotEmpty, true);
    });

    test('edge with description from metadata', () {
      final json = {
        'id': 'rel-meta',
        'source': 's1',
        'target': 't1',
        'relation': 'mentions',
        'weight': 0.6,
        'description': 'Entity A is mentioned in context of Entity B',
      };
      final edge = GraphEdge.fromJson(json);
      expect(edge.description, contains('mentioned'));
    });
  });

  group('GraphData model', () {
    test('fromJson parses nodes and edges', () {
      final json = {
        'nodes': [
          {'id': 'n1', 'label': 'Node 1', 'entity_type': 'person'},
          {'id': 'n2', 'label': 'Node 2', 'entity_type': 'org'},
        ],
        'edges': [
          {'source': 'n1', 'target': 'n2', 'relation': 'belongs_to', 'weight': 0.9},
        ],
      };
      final data = GraphData.fromJson(json);
      expect(data.nodes.length, 2);
      expect(data.edges.length, 1);
      expect(data.nodes[0].label, 'Node 1');
      expect(data.edges[0].relation, 'belongs_to');
    });

    test('fromJson handles empty data', () {
      final data = GraphData.fromJson({});
      expect(data.nodes, isEmpty);
      expect(data.edges, isEmpty);
    });
  });

  group('EntityInfo model', () {
    test('fromJson parses all fields', () {
      final json = {
        'id': 'e1',
        'name': 'Test Entity',
        'entity_type': 'concept',
        'document_id': 'doc-abc',
        'metadata': {'key': 'value'},
        'created_at': '2026-05-22T06:00:00Z',
      };
      final entity = EntityInfo.fromJson(json);
      expect(entity.id, 'e1');
      expect(entity.name, 'Test Entity');
      expect(entity.entityType, 'concept');
      expect(entity.documentId, 'doc-abc');
      expect(entity.metadata['key'], 'value');
      expect(entity.createdAt, '2026-05-22T06:00:00Z');
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'e2',
        'name': 'Entity',
        'entity_type': 'person',
        'created_at': '',
      };
      final entity = EntityInfo.fromJson(json);
      expect(entity.documentId, isNull);
      expect(entity.metadata, isEmpty);
    });

    test('fromJson handles non-map metadata', () {
      final json = {
        'id': 'e3',
        'name': 'X',
        'entity_type': 'x',
        'metadata': 'not a map',
        'created_at': '',
      };
      final entity = EntityInfo.fromJson(json);
      expect(entity.metadata, isEmpty);
    });
  });

  group('GenerationLogEntry model', () {
    test('fromJson parses all fields', () {
      final json = {
        'id': 'log-001',
        'status': 'completed',
        'trigger_type': 'manual_single',
        'document_id': 'doc-abc',
        'llm_provider': 'openai',
        'llm_model': 'gpt-4',
        'total_documents': 1,
        'processed_documents': 1,
        'entities_created': 10,
        'relations_created': 5,
        'errors': [],
        'started_at': '2026-05-27T10:00:00Z',
        'completed_at': '2026-05-27T10:00:05Z',
        'elapsed_ms': 5000,
      };
      final entry = GenerationLogEntry.fromJson(json);
      expect(entry.id, 'log-001');
      expect(entry.status, 'completed');
      expect(entry.triggerType, 'manual_single');
      expect(entry.documentId, 'doc-abc');
      expect(entry.llmProvider, 'openai');
      expect(entry.llmModel, 'gpt-4');
      expect(entry.totalDocuments, 1);
      expect(entry.processedDocuments, 1);
      expect(entry.entitiesCreated, 10);
      expect(entry.relationsCreated, 5);
      expect(entry.errors, isEmpty);
      expect(entry.startedAt, '2026-05-27T10:00:00Z');
      expect(entry.completedAt, '2026-05-27T10:00:05Z');
      expect(entry.elapsedMs, 5000);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'log-002',
        'status': 'running',
        'total_documents': 5,
        'processed_documents': 2,
        'entities_created': 3,
        'relations_created': 1,
        'errors': [],
        'started_at': '2026-05-27T10:00:00Z',
      };
      final entry = GenerationLogEntry.fromJson(json);
      expect(entry.triggerType, 'manual_batch');
      expect(entry.documentId, isNull);
      expect(entry.llmProvider, isNull);
      expect(entry.llmModel, isNull);
      expect(entry.completedAt, isNull);
      expect(entry.elapsedMs, isNull);
    });

    test('fromJson handles batch generation with errors', () {
      final json = {
        'id': 'log-003',
        'status': 'completed',
        'trigger_type': 'manual_batch',
        'llm_provider': 'ollama',
        'llm_model': 'llama3',
        'total_documents': 10,
        'processed_documents': 10,
        'entities_created': 50,
        'relations_created': 30,
        'errors': ['doc abc: connection timeout', 'doc xyz: parse error'],
        'started_at': '2026-05-27T10:00:00Z',
        'completed_at': '2026-05-27T10:05:00Z',
        'elapsed_ms': 300000,
      };
      final entry = GenerationLogEntry.fromJson(json);
      expect(entry.errors.length, 2);
      expect(entry.errors[0], contains('connection timeout'));
      expect(entry.errors[1], contains('parse error'));
      expect(entry.triggerType, 'manual_batch');
    });

    test('fromJson handles failed status', () {
      final json = {
        'id': 'log-004',
        'status': 'failed',
        'trigger_type': 'manual_single',
        'document_id': 'doc-fail',
        'total_documents': 1,
        'processed_documents': 0,
        'entities_created': 0,
        'relations_created': 0,
        'errors': ['LLM API returned 500'],
        'started_at': '2026-05-27T10:00:00Z',
        'completed_at': '2026-05-27T10:00:02Z',
        'elapsed_ms': 2000,
      };
      final entry = GenerationLogEntry.fromJson(json);
      expect(entry.status, 'failed');
      expect(entry.processedDocuments, 0);
      expect(entry.errors.length, 1);
    });

    test('fromJson with completely empty JSON defaults gracefully', () {
      final entry = GenerationLogEntry.fromJson({});
      expect(entry.id, '');
      expect(entry.status, '');
      expect(entry.triggerType, 'manual_batch');
      expect(entry.totalDocuments, 0);
      expect(entry.processedDocuments, 0);
      expect(entry.entitiesCreated, 0);
      expect(entry.relationsCreated, 0);
      expect(entry.errors, isEmpty);
      expect(entry.startedAt, '');
    });
  });

  group('Knowledge Graph i18n keys', () {
    testWidgets('Chinese locale has all graph keys', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Builder(builder: (context) {
            final s = S.of(context);
            expect(s.navKnowledgeGraph, '图谱');
            expect(s.knowledgeGraph, '知识图谱');
            expect(s.graphView, '关系图');
            expect(s.entityList, '实体列表');
            expect(s.noGraphData, '暂无图谱数据');
            expect(s.noEntities, '暂无实体');
            expect(s.entityType, '类型');
            expect(s.relatedEntities, '关联实体');
            expect(s.nodes, '节点');
            expect(s.edges, '关系');
            expect(s.knowledgeGraphDesc('测试'), contains('测试'));
            return const SizedBox.shrink();
          }),
        ),
      );
    });

    testWidgets('English locale has all graph keys', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Builder(builder: (context) {
            final s = S.of(context);
            expect(s.navKnowledgeGraph, 'Graph');
            expect(s.knowledgeGraph, 'Knowledge Graph');
            expect(s.graphView, 'Graph View');
            expect(s.entityList, 'Entity List');
            expect(s.noGraphData, 'No graph data');
            expect(s.nodes, 'Nodes');
            expect(s.edges, 'Edges');
            return const SizedBox.shrink();
          }),
        ),
      );
    });

    testWidgets('Japanese locale has all graph keys', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Builder(builder: (context) {
            final s = S.of(context);
            expect(s.navKnowledgeGraph, 'グラフ');
            expect(s.knowledgeGraph, 'ナレッジグラフ');
            expect(s.graphView, '関係図');
            expect(s.entityList, 'エンティティ一覧');
            expect(s.nodes, 'ノード');
            return const SizedBox.shrink();
          }),
        ),
      );
    });
  });
}
