import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/knowledge_graph_provider.dart';

class GraphDetailSidebar extends ConsumerWidget {
  final GraphNode? node;
  final GraphEdge? edge;
  final List<GraphNode> allNodes;
  final List<GraphEdge> allEdges;
  final VoidCallback onClose;
  final ValueChanged<String>? onCenterNode;
  final ValueChanged<String>? onExpandNeighbors;

  const GraphDetailSidebar({
    super.key,
    this.node,
    this.edge,
    required this.allNodes,
    required this.allEdges,
    required this.onClose,
    this.onCenterNode,
    this.onExpandNeighbors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: node != null
          ? _NodeDetail(
              node: node!,
              edges: allEdges,
              allNodes: allNodes,
              onClose: onClose,
              onCenterNode: onCenterNode,
              onExpandNeighbors: onExpandNeighbors,
              ref: ref,
            )
          : edge != null
              ? _EdgeDetail(edge: edge!, allNodes: allNodes, onClose: onClose)
              : const SizedBox.shrink(),
    );
  }
}

class _NodeDetail extends StatelessWidget {
  final GraphNode node;
  final List<GraphEdge> edges;
  final List<GraphNode> allNodes;
  final VoidCallback onClose;
  final ValueChanged<String>? onCenterNode;
  final ValueChanged<String>? onExpandNeighbors;
  final WidgetRef ref;

  const _NodeDetail({
    required this.node,
    required this.edges,
    required this.allNodes,
    required this.onClose,
    this.onCenterNode,
    this.onExpandNeighbors,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodeMap = {for (final n in allNodes) n.id: n};
    final related = edges.where((e) => e.source == node.id || e.target == node.id).toList();
    final incoming = related.where((e) => e.target == node.id).toList();
    final outgoing = related.where((e) => e.source == node.id).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: node.color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(node.label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClose),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _chip(node.entityType, node.color),
                if (node.originalName != null && node.originalName != node.label) ...[
                  const SizedBox(height: 8),
                  _field('原始名称', node.originalName!),
                ],
                if (node.originalLanguage != null) _field('原始语言', node.originalLanguage!),
                if (node.aliases != null && node.aliases!.isNotEmpty)
                  _field('别名', node.aliases!.join(', ')),
                if (node.description != null && node.description!.isNotEmpty)
                  _field('描述', node.description!),
                if (node.jurisdiction != null) _field('司法辖区', node.jurisdiction!),
                if (node.documentId != null) _field('来源文档', node.documentId!.substring(0, 8)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (onCenterNode != null)
                      TextButton.icon(
                        onPressed: () => onCenterNode!(node.id),
                        icon: const Icon(Icons.center_focus_strong, size: 14),
                        label: const Text('居中', style: TextStyle(fontSize: 11)),
                      ),
                    if (onExpandNeighbors != null)
                      TextButton.icon(
                        onPressed: () => onExpandNeighbors!(node.id),
                        icon: const Icon(Icons.hub, size: 14),
                        label: const Text('展开邻居', style: TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
                const Divider(),
                Text('出边 (${outgoing.length})', style: theme.textTheme.labelMedium),
                ...outgoing.take(20).map((e) => _relationTile(e, nodeMap, isOut: true)),
                const SizedBox(height: 8),
                Text('入边 (${incoming.length})', style: theme.textTheme.labelMedium),
                ...incoming.take(20).map((e) => _relationTile(e, nodeMap, isOut: false)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _relationTile(GraphEdge e, Map<String, GraphNode> nodeMap, {required bool isOut}) {
    final otherId = isOut ? e.target : e.source;
    final other = nodeMap[otherId];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: other?.label ?? otherId, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
            TextSpan(text: ' — ${e.relation}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
          ])),
          if (e.description != null && e.description!.isNotEmpty)
            Text(e.description!, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          if (e.evidenceText != null && e.evidenceText!.isNotEmpty)
            Text('证据: ${e.evidenceText}', style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}

class _EdgeDetail extends StatelessWidget {
  final GraphEdge edge;
  final List<GraphNode> allNodes;
  final VoidCallback onClose;

  const _EdgeDetail({required this.edge, required this.allNodes, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodeMap = {for (final n in allNodes) n.id: n};
    final src = nodeMap[edge.source];
    final tgt = nodeMap[edge.target];

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('关系详情', style: theme.textTheme.titleMedium)),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClose),
            ],
          ),
          const SizedBox(height: 12),
          Text('${src?.label ?? edge.source} → ${tgt?.label ?? edge.target}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _row('关系类型', edge.relation),
          _row('置信度', '${(edge.weight * 100).toStringAsFixed(0)}%'),
          if (edge.description != null) _row('描述', edge.description!),
          if (edge.evidenceText != null) _row('证据文本', edge.evidenceText!),
          if (edge.sourceDocumentId != null) _row('来源文档', edge.sourceDocumentId!),
          if (edge.sourceChunkId != null) _row('来源 Chunk', edge.sourceChunkId!),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}