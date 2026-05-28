import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../dashboard/providers/workspace_provider.dart';
import '../providers/knowledge_graph_provider.dart';

class KnowledgeGraphPage extends ConsumerStatefulWidget {
  const KnowledgeGraphPage({super.key});

  @override
  ConsumerState<KnowledgeGraphPage> createState() => _KnowledgeGraphPageState();
}

class _KnowledgeGraphPageState extends ConsumerState<KnowledgeGraphPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _entityFilter = '';
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _generateAll() async {
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;
    setState(() => _isGenerating = true);
    try {
      final service = ref.read(knowledgeGraphServiceProvider);
      final result = await service.generateForAll(ws.id);
      if (mounted) {
        final entities = result['entities_created'] ?? 0;
        final relations = result['relations_created'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图谱生成完成: $entities 个实体, $relations 条关系')),
        );
        ref.invalidate(graphDataProvider);
        ref.invalidate(entityListProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图谱生成失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _resetGraph() async {
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空图谱'),
        content: const Text('此操作将删除当前工作区的所有实体和关系数据，不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final service = ref.read(knowledgeGraphServiceProvider);
      await service.resetGraph(ws.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图谱已清空')),
        );
        ref.invalidate(graphDataProvider);
        ref.invalidate(entityListProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清空失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final ws = ref.watch(selectedWorkspaceProvider);
    final theme = Theme.of(context);

    if (ws == null) {
      return Center(
        child: Text(s.selectWorkspaceFirst,
            style: TextStyle(color: Colors.grey.shade500)),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(s.knowledgeGraph,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_isGenerating)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: '更多操作',
                    onSelected: (value) {
                      switch (value) {
                        case 'generate':
                          _generateAll();
                          break;
                        case 'reset':
                          _resetGraph();
                          break;
                        case 'refresh':
                          ref.invalidate(graphDataProvider);
                          ref.invalidate(entityListProvider);
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'generate',
                        enabled: !_isGenerating,
                        child: const ListTile(
                          leading: Icon(Icons.auto_fix_high),
                          title: Text('生成知识图谱'),
                          subtitle: Text('从所有文档抽取实体和关系', style: TextStyle(fontSize: 11)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'refresh',
                        child: ListTile(
                          leading: Icon(Icons.refresh),
                          title: Text('刷新图谱'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'reset',
                        child: ListTile(
                          leading: Icon(Icons.delete_forever, color: Colors.red),
                          title: Text('清空图谱', style: TextStyle(color: Colors.red)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(s.knowledgeGraphDesc(ws.name),
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: s.graphView),
                  Tab(text: s.entityList),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _GraphViewTab(isGenerating: _isGenerating, onGenerate: _generateAll),
              _EntityListTab(
                filter: _entityFilter,
                onFilterChanged: (v) => setState(() => _entityFilter = v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GraphViewTab extends ConsumerWidget {
  final bool isGenerating;
  final VoidCallback onGenerate;

  const _GraphViewTab({required this.isGenerating, required this.onGenerate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graphAsync = ref.watch(graphDataProvider);
    final s = S.of(context);

    return graphAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(s.loadFailed(e.toString()),
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
      data: (data) {
        if (data == null || data.nodes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hub_outlined,
                    size: 80, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(s.noGraphData,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: Colors.grey)),
                const SizedBox(height: 8),
                Text(
                  '点击下方按钮从文档中抽取实体和关系，生成知识图谱',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: isGenerating ? null : onGenerate,
                  icon: isGenerating
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.auto_fix_high),
                  label: Text(isGenerating ? '生成中...' : '生成知识图谱'),
                ),
                const SizedBox(height: 12),
                Text(
                  '需要已配置 LLM 模型，将通过 LLM 从文档 chunk 中抽取实体与关系',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ],
            ),
          );
        }

        return _InteractiveGraph(data: data);
      },
    );
  }
}

class _InteractiveGraph extends StatefulWidget {
  final GraphData data;
  const _InteractiveGraph({required this.data});

  @override
  State<_InteractiveGraph> createState() => _InteractiveGraphState();
}

class _InteractiveGraphState extends State<_InteractiveGraph> {
  final TransformationController _transformCtrl = TransformationController();
  String? _selectedNodeId;
  String? _hoveredNodeId;
  final Set<String> _hiddenTypes = {};

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    final visibleNodes = widget.data.nodes
        .where((n) => !_hiddenTypes.contains(n.entityType))
        .toList();
    final visibleNodeIds = visibleNodes.map((n) => n.id).toSet();
    final visibleEdges = widget.data.edges
        .where((e) => visibleNodeIds.contains(e.source) && visibleNodeIds.contains(e.target))
        .toList();

    final selectedNode = _selectedNodeId != null
        ? visibleNodes
            .where((n) => n.id == _selectedNodeId)
            .firstOrNull
        : null;

    return Stack(
      children: [
        InteractiveViewer(
          transformationController: _transformCtrl,
          minScale: 0.1,
          maxScale: 4.0,
          boundaryMargin: const EdgeInsets.all(500),
          child: GestureDetector(
            onTapUp: (details) => _handleTap(details.localPosition, visibleNodes),
            child: CustomPaint(
              size: const Size(800, 600),
              painter: _GraphPainter(
                nodes: visibleNodes,
                edges: visibleEdges,
                selectedNodeId: _selectedNodeId,
                hoveredNodeId: _hoveredNodeId,
                theme: Theme.of(context),
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: _FilterableLegend(
            allNodes: widget.data.nodes,
            hiddenTypes: _hiddenTypes,
            onToggleType: (type) {
              setState(() {
                if (_hiddenTypes.contains(type)) {
                  _hiddenTypes.remove(type);
                } else {
                  _hiddenTypes.add(type);
                }
              });
            },
          ),
        ),
        if (selectedNode != null)
          Positioned(
            left: 12,
            bottom: 12,
            child: _NodeInfoCard(
              node: selectedNode,
              edges: visibleEdges,
              allNodes: visibleNodes,
              onClose: () => setState(() => _selectedNodeId = null),
            ),
          ),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              '${s.nodes}: ${visibleNodes.length}/${widget.data.nodes.length}  |  ${s.edges}: ${visibleEdges.length}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ),
      ],
    );
  }

  void _handleTap(Offset localPosition, List<GraphNode> visibleNodes) {
    final matrix = _transformCtrl.value;
    final inverted = Matrix4.inverted(matrix);
    final transformed = MatrixUtils.transformPoint(inverted, localPosition);

    String? tappedId;
    for (final node in visibleNodes) {
      if ((node.position - transformed).distance < 20) {
        tappedId = node.id;
        break;
      }
    }
    setState(() => _selectedNodeId = tappedId);
  }
}

class _GraphPainter extends CustomPainter {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final String? selectedNodeId;
  final String? hoveredNodeId;
  final ThemeData theme;

  _GraphPainter({
    required this.nodes,
    required this.edges,
    this.selectedNodeId,
    this.hoveredNodeId,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodeMap = {for (final n in nodes) n.id: n};

    for (final edge in edges) {
      final src = nodeMap[edge.source];
      final tgt = nodeMap[edge.target];
      if (src == null || tgt == null) continue;

      final isHighlighted = selectedNodeId != null &&
          (edge.source == selectedNodeId || edge.target == selectedNodeId);

      final edgePaint = Paint()
        ..color = isHighlighted
            ? theme.colorScheme.primary.withValues(alpha: 0.6)
            : Colors.grey.withValues(alpha: 0.25)
        ..strokeWidth = isHighlighted ? 2.0 : 1.0
        ..style = PaintingStyle.stroke;

      canvas.drawLine(src.position, tgt.position, edgePaint);

      final mid = Offset(
        (src.position.dx + tgt.position.dx) / 2,
        (src.position.dy + tgt.position.dy) / 2,
      );
      if (isHighlighted && edge.relation.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: edge.relation,
            style: TextStyle(
              fontSize: 9,
              color: theme.colorScheme.primary.withValues(alpha: 0.8),
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: mid, width: tp.width + 8, height: tp.height + 4),
            const Radius.circular(4),
          ),
          Paint()..color = theme.colorScheme.surface.withValues(alpha: 0.9),
        );
        tp.paint(canvas,
            mid - Offset(tp.width / 2, tp.height / 2));
      }
    }

    for (final node in nodes) {
      final isSelected = node.id == selectedNodeId;
      final radius = isSelected ? 16.0 : 12.0;

      if (isSelected) {
        canvas.drawCircle(
          node.position,
          radius + 4,
          Paint()
            ..color = node.color.withValues(alpha: 0.2)
            ..style = PaintingStyle.fill,
        );
      }

      canvas.drawCircle(
        node.position,
        radius,
        Paint()
          ..color = node.color
          ..style = PaintingStyle.fill,
      );

      canvas.drawCircle(
        node.position,
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.3)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: node.label.length > 15
              ? '${node.label.substring(0, 15)}...'
              : node.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: theme.brightness == Brightness.dark
                ? Colors.white
                : Colors.black87,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout(maxWidth: 120);

      final bgRect = Rect.fromCenter(
        center: node.position + Offset(0, radius + 10),
        width: tp.width + 6,
        height: tp.height + 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
        Paint()..color = theme.colorScheme.surface.withValues(alpha: 0.85),
      );

      tp.paint(
        canvas,
        node.position + Offset(-tp.width / 2, radius + 10 - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) => true;
}

class _FilterableLegend extends StatelessWidget {
  final List<GraphNode> allNodes;
  final Set<String> hiddenTypes;
  final ValueChanged<String> onToggleType;

  const _FilterableLegend({
    required this.allNodes,
    required this.hiddenTypes,
    required this.onToggleType,
  });

  @override
  Widget build(BuildContext context) {
    final typeCounts = <String, int>{};
    for (final n in allNodes) {
      typeCounts[n.entityType] = (typeCounts[n.entityType] ?? 0) + 1;
    }
    if (typeCounts.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('类型过滤', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          ...typeCounts.entries.take(10).map((entry) {
            final type = entry.key;
            final count = entry.value;
            final sampleNode = allNodes.firstWhere((n) => n.entityType == type);
            final isHidden = hiddenTypes.contains(type);
            return InkWell(
              onTap: () => onToggleType(type),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isHidden ? Colors.grey.shade300 : sampleNode.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '$type ($count)',
                        style: TextStyle(
                          fontSize: 11,
                          color: isHidden ? Colors.grey.shade400 : null,
                          decoration: isHidden ? TextDecoration.lineThrough : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _NodeInfoCard extends StatelessWidget {
  final GraphNode node;
  final List<GraphEdge> edges;
  final List<GraphNode> allNodes;
  final VoidCallback onClose;

  const _NodeInfoCard({
    required this.node,
    required this.edges,
    required this.allNodes,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final nodeMap = {for (final n in allNodes) n.id: n};
    final related = edges
        .where((e) => e.source == node.id || e.target == node.id)
        .take(10)
        .toList();

    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: node.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(node.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              InkWell(onTap: onClose, child: const Icon(Icons.close, size: 18)),
            ],
          ),
          const SizedBox(height: 4),
          Text('${s.entityType}: ${node.entityType}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          if (node.documentId != null) ...[
            const SizedBox(height: 2),
            Text('${s.document}: ${node.documentId!.substring(0, 8)}...',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
          if (related.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(s.relatedEntities,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 4),
            ...related.map((e) {
              final otherId =
                  e.source == node.id ? e.target : e.source;
              final other = nodeMap[otherId];
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: other?.color ?? Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${other?.label ?? otherId} (${e.relation})',
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _EntityListTab extends ConsumerWidget {
  final String filter;
  final ValueChanged<String> onFilterChanged;

  const _EntityListTab({
    required this.filter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitiesAsync = ref.watch(entityListProvider);
    final s = S.of(context);
    final theme = Theme.of(context);

    return entitiesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(s.loadFailed(e.toString()),
            style: TextStyle(color: Colors.grey.shade600)),
      ),
      data: (entities) {
        if (entities.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.category_outlined,
                    size: 80, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(s.noEntities,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(color: Colors.grey)),
              ],
            ),
          );
        }

        final filtered = filter.isEmpty
            ? entities
            : entities
                .where((e) =>
                    e.name.toLowerCase().contains(filter.toLowerCase()) ||
                    e.entityType.toLowerCase().contains(filter.toLowerCase()))
                .toList();

        final typeGroups = <String, List<EntityInfo>>{};
        for (final e in filtered) {
          typeGroups.putIfAbsent(e.entityType, () => []).add(e);
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: s.searchEntities,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: onFilterChanged,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('${filtered.length} ${s.entitiesCount}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600)),
                  const Spacer(),
                  Text('${typeGroups.length} ${s.typesCount}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: typeGroups.entries.map((entry) {
                  final type = entry.key;
                  final items = entry.value;
                  final sampleNode = GraphNode(
                    id: '',
                    label: '',
                    entityType: type,
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: sampleNode.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('$type (${items.length})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                      ...items.map((entity) => Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    sampleNode.color.withValues(alpha: 0.15),
                                child: Text(
                                  entity.name.isNotEmpty
                                      ? entity.name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color: sampleNode.color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              title: Text(entity.name,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: entity.documentId != null
                                  ? Text(
                                      '${s.document}: ${entity.documentId!.substring(0, min(8, entity.documentId!.length))}...',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500),
                                    )
                                  : null,
                              trailing: Text(
                                _formatDate(entity.createdAt),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade500),
                              ),
                            ),
                          )),
                      const SizedBox(height: 4),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }
}
