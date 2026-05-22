import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/features/search/providers/knowledge_graph_provider.dart';

void main() {
  group('GraphNode model', () {
    test('fromJson parses all fields', () {
      final json = {
        'id': 'n1',
        'label': 'Test Entity',
        'entity_type': 'person',
        'document_id': 'doc-123',
      };
      final node = GraphNode.fromJson(json);
      expect(node.id, 'n1');
      expect(node.label, 'Test Entity');
      expect(node.entityType, 'person');
      expect(node.documentId, 'doc-123');
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'n2',
        'label': 'Entity',
        'entity_type': 'concept',
      };
      final node = GraphNode.fromJson(json);
      expect(node.documentId, isNull);
    });

    test('color mapping for known entity types', () {
      expect(GraphNode(id: '', label: '', entityType: 'person').color, Colors.blue);
      expect(GraphNode(id: '', label: '', entityType: 'organization').color, Colors.purple);
      expect(GraphNode(id: '', label: '', entityType: 'location').color, Colors.green);
      expect(GraphNode(id: '', label: '', entityType: 'concept').color, Colors.orange);
      expect(GraphNode(id: '', label: '', entityType: 'event').color, Colors.red);
      expect(GraphNode(id: '', label: '', entityType: 'document').color, Colors.teal);
      expect(GraphNode(id: '', label: '', entityType: 'technology').color, Colors.indigo);
      expect(GraphNode(id: '', label: '', entityType: 'unknown').color, Colors.grey);
    });
  });

  group('GraphEdge model', () {
    test('fromJson parses all fields', () {
      final json = {
        'source': 's1',
        'target': 't1',
        'relation': 'works_at',
        'weight': 0.85,
      };
      final edge = GraphEdge.fromJson(json);
      expect(edge.source, 's1');
      expect(edge.target, 't1');
      expect(edge.relation, 'works_at');
      expect(edge.weight, 0.85);
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
