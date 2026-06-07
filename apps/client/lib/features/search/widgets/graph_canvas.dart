import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/providers/workspace_provider.dart';
import '../providers/graph_filter_provider.dart';
import '../providers/graph_layout_engine.dart';
import '../providers/knowledge_graph_provider.dart';
import 'graph_detail_sidebar.dart';
import 'graph_layer_panel.dart';

class GraphCanvas extends ConsumerStatefulWidget {
  final GraphData fullData;
  final FilteredGraphData filtered;
  final VoidCallback onGenerateKnowledge;

  const GraphCanvas({
    super.key,
    required this.fullData,
    required this.filtered,
    required this.onGenerateKnowledge,
  });

  @override
  ConsumerState<GraphCanvas> createState() => _GraphCanvasState();
}

class _GraphCanvasState extends ConsumerState<GraphCanvas> {
  final TransformationController _transformCtrl = TransformationController();
  String? _selectedNodeId;
  String? _hoveredNodeId;
  GraphEdge? _selectedEdge;
  String? _draggingNodeId;
  bool _layoutApplied = false;
  bool _fitApplied = false;
  Size _lastCanvasSize = Size.zero;

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filtered.nodes.length != widget.filtered.nodes.length ||
        oldWidget.filtered.edges.length != widget.filtered.edges.length) {
      _layoutApplied = false;
      _fitApplied = false;
    }
  }

  void _applyLayout(Size size) {
    if (_layoutApplied && size == _lastCanvasSize) return;
    _lastCanvasSize = size;
    final filter = ref.read(graphFilterProvider);
    GraphLayoutEngine.applyLayout(
      nodes: widget.filtered.nodes,
      edges: widget.filtered.edges,
      canvasSize: size,
      mode: filter.layoutMode,
      centerNodeId: filter.centerNodeId,
      iterations: widget.filtered.nodes.length > 200 ? 50 : 100,
    );
    _layoutApplied = true;
    if (mounted) setState(() {});
  }

  void _fitToScreen() {
    if (widget.filtered.nodes.isEmpty) return;
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final n in widget.filtered.nodes) {
      minX = min(minX, n.position.dx);
      minY = min(minY, n.position.dy);
      maxX = max(maxX, n.position.dx);
      maxY = max(maxY, n.position.dy);
    }
    final graphW = maxX - minX + 80;
    final graphH = maxY - minY + 80;
    final vw = _lastCanvasSize.width;
    final vh = _lastCanvasSize.height;
    if (vw <= 0 || vh <= 0) return;
    final scale = min(vw / graphW, vh / graphH).clamp(0.1, 2.0);
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    _transformCtrl.value = Matrix4.identity()
      ..translate(vw / 2, vh / 2)
      ..scale(scale)
      ..translate(-cx, -cy);
  }

  void _centerOnNode(String nodeId) {
    final node = widget.filtered.nodes.where((n) => n.id == nodeId).firstOrNull;
    if (node == null) return;
    final scale = _transformCtrl.value.getMaxScaleOnAxis();
    final vw = _lastCanvasSize.width;
    final vh = _lastCanvasSize.height;
    _transformCtrl.value = Matrix4.identity()
      ..translate(vw / 2, vh / 2)
      ..scale(scale.clamp(0.5, 2.0))
      ..translate(-node.position.dx, -node.position.dy);
    setState(() => _selectedNodeId = nodeId);
    ref.read(graphFilterProvider.notifier).setCenterNode(nodeId);
  }

  Offset _toGraph(Offset local) {
    return MatrixUtils.transformPoint(Matrix4.inverted(_transformCtrl.value), local);
  }

  GraphNode? _hitNode(Offset graphPos) {
    final nodeCount = widget.filtered.nodes.length;
    final hitRadius = nodeCount > 200 ? 8.0 : (nodeCount > 100 ? 12.0 : 16.0);
    for (final node in widget.filtered.nodes) {
      if ((node.position - graphPos).distance < hitRadius) return node;
    }
    return null;
  }

  Set<String> _neighborIds(String nodeId) {
    final ids = <String>{nodeId};
    for (final e in widget.filtered.edges) {
      if (e.source == nodeId) ids.add(e.target);
      if (e.target == nodeId) ids.add(e.source);
    }
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showLabels = widget.filtered.nodes.length <= 80;

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        _applyLayout(canvasSize);
        if (!_fitApplied && widget.filtered.nodes.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _fitToScreen();
              _fitApplied = true;
            }
          });
        }

        final selectedNode = _selectedNodeId != null
            ? widget.filtered.nodes.where((n) => n.id == _selectedNodeId).firstOrNull
            : null;

        return Row(
          children: [
            Expanded(
              child: Stack(
                children: [
                  InteractiveViewer(
                    transformationController: _transformCtrl,
                    minScale: 0.05,
                    maxScale: 5.0,
                    boundaryMargin: const EdgeInsets.all(800),
                    panEnabled: _draggingNodeId == null,
                    child: SizedBox(
                      width: canvasSize.width,
                      height: canvasSize.height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => _onTap(d.localPosition),
                        onDoubleTapDown: (d) {
                          final node = _hitNode(_toGraph(d.localPosition));
                          if (node != null) {
                            ref.read(graphFilterProvider.notifier).setViewScope(GraphViewScope.neighborhood1);
                            ref.read(graphFilterProvider.notifier).setCenterNode(node.id);
                            _layoutApplied = false;
                          }
                        },
                        onSecondaryTapUp: (d) => _onSecondaryTap(d.localPosition),
                        onPanStart: (d) {
                          final node = _hitNode(_toGraph(d.localPosition));
                          if (node != null) {
                            setState(() {
                              _draggingNodeId = node.id;
                              _selectedNodeId = node.id;
                              _selectedEdge = null;
                            });
                          }
                        },
                        onPanUpdate: (d) {
                          if (_draggingNodeId == null) return;
                          final node = widget.filtered.nodes.where((n) => n.id == _draggingNodeId).firstOrNull;
                          if (node != null) {
                            setState(() {
                              node.position = _toGraph(d.localPosition);
                              node.velocity = Offset.zero;
                            });
                          }
                        },
                        onPanEnd: (_) => setState(() => _draggingNodeId = null),
                        child: CustomPaint(
                          size: canvasSize,
                          painter: _GraphPainter(
                            nodes: widget.filtered.nodes,
                            edges: widget.filtered.edges,
                            selectedNodeId: _selectedNodeId,
                            hoveredNodeId: _hoveredNodeId,
                            highlightIds: _selectedNodeId != null ? _neighborIds(_selectedNodeId!) : null,
                            showLabels: showLabels,
                            theme: theme,
                            scale: _transformCtrl.value.getMaxScaleOnAxis(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(left: 8, top: 8, child: const GraphLayerPanel()),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: _GraphToolbar(
                      onZoomIn: () => _zoom(1.3),
                      onZoomOut: () => _zoom(0.7),
                      onFit: _fitToScreen,
                      onResetView: () => _transformCtrl.value = Matrix4.identity(),
                      onResetLayout: () {
                        setState(() => _layoutApplied = false);
                        _applyLayout(canvasSize);
                        _fitToScreen();
                      },
                      nodeCount: widget.filtered.nodes.length,
                      edgeCount: widget.filtered.edges.length,
                      totalNodes: widget.filtered.totalNodes,
                      totalEdges: widget.filtered.totalEdges,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: _SearchBox(onSelect: _centerOnNode),
                  ),
                ],
              ),
            ),
            if (selectedNode != null || _selectedEdge != null)
              GraphDetailSidebar(
                node: selectedNode,
                edge: _selectedEdge,
                allNodes: widget.filtered.nodes,
                allEdges: widget.filtered.edges,
                onClose: () => setState(() {
                  _selectedNodeId = null;
                  _selectedEdge = null;
                }),
                onCenterNode: _centerOnNode,
                onExpandNeighbors: (id) {
                  ref.read(graphFilterProvider.notifier).setViewScope(GraphViewScope.neighborhood1);
                  ref.read(graphFilterProvider.notifier).setCenterNode(id);
                  setState(() => _layoutApplied = false);
                },
              ),
          ],
        );
      },
    );
  }

  void _zoom(double factor) {
    final m = _transformCtrl.value.clone();
    m.scale(factor, factor, 1.0);
    _transformCtrl.value = m;
  }

  void _onTap(Offset local) {
    final pos = _toGraph(local);
    final node = _hitNode(pos);
    if (node != null) {
      setState(() {
        _selectedNodeId = node.id;
        _selectedEdge = null;
      });
      return;
    }
    final nodeMap = {for (final n in widget.filtered.nodes) n.id: n};
    GraphEdge? edge;
    for (final e in widget.filtered.edges) {
      final src = nodeMap[e.source];
      final tgt = nodeMap[e.target];
      if (src == null || tgt == null) continue;
      if (_pointToSegmentDistance(pos, src.position, tgt.position) < 10) {
        edge = e;
        break;
      }
    }
    setState(() {
      _selectedNodeId = null;
      _selectedEdge = edge;
    });
  }

  void _onSecondaryTap(Offset local) {
    final pos = _toGraph(local);
    final node = _hitNode(pos);
    if (node == null) return;
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(local.dx, local.dy, local.dx, local.dy),
      items: [
        PopupMenuItem(onTap: () => _centerOnNode(node.id), child: const Text('居中此节点')),
        PopupMenuItem(
          onTap: () {
            ref.read(graphFilterProvider.notifier).setViewScope(GraphViewScope.neighborhood1);
            ref.read(graphFilterProvider.notifier).setCenterNode(node.id);
            setState(() => _layoutApplied = false);
          },
          child: const Text('展开一阶邻居'),
        ),
        PopupMenuItem(
          onTap: () => Clipboard.setData(ClipboardData(text: node.label)),
          child: const Text('复制名称'),
        ),
      ],
    );
  }

  double _pointToSegmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final t = (ap.dx * ab.dx + ap.dy * ab.dy) / (ab.dx * ab.dx + ab.dy * ab.dy);
    final c = t.clamp(0.0, 1.0);
    final closest = Offset(a.dx + c * ab.dx, a.dy + c * ab.dy);
    return (p - closest).distance;
  }
}

class _GraphToolbar extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  final VoidCallback onResetView;
  final VoidCallback onResetLayout;
  final int nodeCount;
  final int edgeCount;
  final int totalNodes;
  final int totalEdges;

  const _GraphToolbar({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.onResetView,
    required this.onResetLayout,
    required this.nodeCount,
    required this.edgeCount,
    required this.totalNodes,
    required this.totalEdges,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(tooltip: '放大', icon: const Icon(Icons.zoom_in, size: 18), onPressed: onZoomIn, visualDensity: VisualDensity.compact),
            IconButton(tooltip: '缩小', icon: const Icon(Icons.zoom_out, size: 18), onPressed: onZoomOut, visualDensity: VisualDensity.compact),
            IconButton(tooltip: '适应屏幕', icon: const Icon(Icons.fit_screen, size: 18), onPressed: onFit, visualDensity: VisualDensity.compact),
            IconButton(tooltip: '重置视角', icon: const Icon(Icons.center_focus_strong, size: 18), onPressed: onResetView, visualDensity: VisualDensity.compact),
            IconButton(tooltip: '重置布局', icon: const Icon(Icons.refresh, size: 18), onPressed: onResetLayout, visualDensity: VisualDensity.compact),
            const VerticalDivider(width: 12),
            Text('节点 $nodeCount/$totalNodes · 边 $edgeCount/$totalEdges', style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _SearchBox extends ConsumerStatefulWidget {
  final ValueChanged<String> onSelect;

  const _SearchBox({required this.onSelect});

  @override
  ConsumerState<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends ConsumerState<_SearchBox> {
  final _controller = TextEditingController();
  List<EntityInfo> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    ref.read(graphFilterProvider.notifier).setSearchQuery(q);
    if (q.length < 2) {
      setState(() => _results = []);
      return;
    }
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;
    setState(() => _searching = true);
    try {
      final service = ref.read(knowledgeGraphServiceProvider);
      final results = await service.searchEntities(ws.id, q);
      if (mounted) setState(() { _results = results; _searching = false; });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        width: 240,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: '搜索实体…',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: _search,
            ),
            if (_results.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (ctx, i) {
                    final e = _results[i];
                    return ListTile(
                      dense: true,
                      title: Text(e.displayName ?? e.name, style: const TextStyle(fontSize: 12)),
                      subtitle: e.originalName != null && e.originalName != e.name
                          ? Text(e.originalName!, style: const TextStyle(fontSize: 10))
                          : null,
                      onTap: () => widget.onSelect(e.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final String? selectedNodeId;
  final String? hoveredNodeId;
  final Set<String>? highlightIds;
  final bool showLabels;
  final ThemeData theme;
  final double scale;

  _GraphPainter({
    required this.nodes,
    required this.edges,
    this.selectedNodeId,
    this.hoveredNodeId,
    this.highlightIds,
    required this.showLabels,
    required this.theme,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodeMap = {for (final n in nodes) n.id: n};
    final nodeCount = nodes.length;
    final baseRadius = nodeCount > 200 ? 4.0 : (nodeCount > 100 ? 6.0 : 8.0);
    final labelScale = scale.clamp(0.3, 2.0);

    for (final edge in edges) {
      final src = nodeMap[edge.source];
      final tgt = nodeMap[edge.target];
      if (src == null || tgt == null) continue;
      final highlighted = highlightIds != null &&
          (highlightIds!.contains(edge.source) && highlightIds!.contains(edge.target));
      final alpha = highlighted ? 0.7 : (nodeCount > 200 ? 0.12 : 0.25);
      canvas.drawLine(
        src.position,
        tgt.position,
        Paint()
          ..color = highlighted ? theme.colorScheme.primary.withValues(alpha: alpha) : Colors.grey.withValues(alpha: alpha)
          ..strokeWidth = highlighted ? 2.0 : 0.8,
      );
    }

    for (final node in nodes) {
      final isSelected = node.id == selectedNodeId;
      final isHighlighted = highlightIds?.contains(node.id) ?? false;
      final isCore = !showLabels && (isSelected || isHighlighted);
      final radius = isSelected ? baseRadius * 1.8 : baseRadius;

      if (isSelected || isHighlighted) {
        canvas.drawCircle(node.position, radius + 3, Paint()..color = node.color.withValues(alpha: 0.2));
      }

      canvas.drawCircle(node.position, radius, Paint()..color = node.color);

      final showThisLabel = showLabels || isCore || isSelected;
      if (showThisLabel) {
        final label = node.label.length > 20 ? '${node.label.substring(0, 20)}…' : node.label;
        final fontSize = (9 / labelScale).clamp(7.0, 11.0);
        final tp = TextPainter(
          text: TextSpan(text: label, style: TextStyle(fontSize: fontSize, color: theme.colorScheme.onSurface)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 100);
        tp.paint(canvas, node.position + Offset(-tp.width / 2, radius + 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}