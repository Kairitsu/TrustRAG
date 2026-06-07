import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'graph_layout_engine.dart';
import 'knowledge_graph_provider.dart';

enum GraphViewScope { global, document, neighborhood1, neighborhood2, cluster }

class GraphFilterState {
  final Set<String> visibleLayers;
  final Set<String> hiddenEntityTypes;
  final Set<String> hiddenRelationTypes;
  final String searchQuery;
  final String? selectedDocumentId;
  final String? centerNodeId;
  final double minConfidence;
  final bool hideIsolatedNodes;
  final bool hideWeakRelations;
  final GraphViewScope viewScope;
  final GraphLayoutMode layoutMode;
  final bool aggregateMode;

  const GraphFilterState({
    this.visibleLayers = const {'document', 'semantic', 'knowledge'},
    this.hiddenEntityTypes = const {},
    this.hiddenRelationTypes = const {},
    this.searchQuery = '',
    this.selectedDocumentId,
    this.centerNodeId,
    this.minConfidence = 0.0,
    this.hideIsolatedNodes = false,
    this.hideWeakRelations = false,
    this.viewScope = GraphViewScope.global,
    this.layoutMode = GraphLayoutMode.forceDirected,
    this.aggregateMode = true,
  });

  GraphFilterState copyWith({
    Set<String>? visibleLayers,
    Set<String>? hiddenEntityTypes,
    Set<String>? hiddenRelationTypes,
    String? searchQuery,
    String? selectedDocumentId,
    String? centerNodeId,
    double? minConfidence,
    bool? hideIsolatedNodes,
    bool? hideWeakRelations,
    GraphViewScope? viewScope,
    GraphLayoutMode? layoutMode,
    bool? aggregateMode,
    bool clearCenterNode = false,
    bool clearDocument = false,
  }) {
    return GraphFilterState(
      visibleLayers: visibleLayers ?? this.visibleLayers,
      hiddenEntityTypes: hiddenEntityTypes ?? this.hiddenEntityTypes,
      hiddenRelationTypes: hiddenRelationTypes ?? this.hiddenRelationTypes,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedDocumentId: clearDocument ? null : (selectedDocumentId ?? this.selectedDocumentId),
      centerNodeId: clearCenterNode ? null : (centerNodeId ?? this.centerNodeId),
      minConfidence: minConfidence ?? this.minConfidence,
      hideIsolatedNodes: hideIsolatedNodes ?? this.hideIsolatedNodes,
      hideWeakRelations: hideWeakRelations ?? this.hideWeakRelations,
      viewScope: viewScope ?? this.viewScope,
      layoutMode: layoutMode ?? this.layoutMode,
      aggregateMode: aggregateMode ?? this.aggregateMode,
    );
  }
}

final graphFilterProvider =
    StateNotifierProvider<GraphFilterNotifier, GraphFilterState>((ref) {
  return GraphFilterNotifier();
});

class GraphFilterNotifier extends StateNotifier<GraphFilterState> {
  GraphFilterNotifier() : super(const GraphFilterState());

  void toggleLayer(String layer, {required bool visible}) {
    final layers = Set<String>.from(state.visibleLayers);
    if (visible) {
      layers.add(layer);
    } else if (layers.length > 1) {
      layers.remove(layer);
    }
    state = state.copyWith(visibleLayers: layers);
  }

  void showAllLayers() {
    state = state.copyWith(
      visibleLayers: {'document', 'semantic', 'knowledge'},
    );
  }

  void toggleEntityType(String type) {
    final hidden = Set<String>.from(state.hiddenEntityTypes);
    if (hidden.contains(type)) {
      hidden.remove(type);
    } else {
      hidden.add(type);
    }
    state = state.copyWith(hiddenEntityTypes: hidden);
  }

  void setSearchQuery(String q) => state = state.copyWith(searchQuery: q);

  void setCenterNode(String? id) =>
      state = state.copyWith(centerNodeId: id, clearCenterNode: id == null);

  void setViewScope(GraphViewScope scope) =>
      state = state.copyWith(viewScope: scope);

  void setLayoutMode(GraphLayoutMode mode) =>
      state = state.copyWith(layoutMode: mode);
}

enum GraphEmptyReason {
  noWorkspace,
  noDocuments,
  notGenerated,
  layerFilterEmpty,
  searchEmpty,
  entitiesNoRelations,
  loadError,
  generating,
}

GraphEmptyReason? resolveEmptyReason({
  required GraphData? fullData,
  required FilteredGraphData? filteredData,
  required LayerStatsMap? layerStats,
  required bool isGenerating,
  required GraphFilterState filter,
}) {
  if (isGenerating && (fullData == null || fullData.nodes.isEmpty)) {
    return GraphEmptyReason.generating;
  }
  if (fullData == null) return null;
  if (fullData.nodes.isEmpty) {
    final hasAnyLayer = layerStats?.hasAnyLayer ?? false;
    if (!hasAnyLayer) return GraphEmptyReason.notGenerated;
    return GraphEmptyReason.notGenerated;
  }
  if (fullData.nodes.isNotEmpty && fullData.edges.isEmpty) {
    return GraphEmptyReason.entitiesNoRelations;
  }
  if (filteredData != null && filteredData.nodes.isEmpty && fullData.nodes.isNotEmpty) {
    if (filter.searchQuery.isNotEmpty) return GraphEmptyReason.searchEmpty;
    return GraphEmptyReason.layerFilterEmpty;
  }
  return null;
}

class LayerStatsMap {
  final Map<String, LayerStat> layers;

  LayerStatsMap(this.layers);

  bool get hasAnyLayer => layers.values.any((l) => l.entityCount > 0 || l.relationCount > 0);

  LayerStat layer(String name) =>
      layers[name] ?? const LayerStat(layer: '', entityCount: 0, relationCount: 0, generated: false);
}

class LayerStat {
  final String layer;
  final int entityCount;
  final int relationCount;
  final bool generated;

  const LayerStat({
    required this.layer,
    required this.entityCount,
    required this.relationCount,
    required this.generated,
  });
}

FilteredGraphData applyFilters(GraphData data, GraphFilterState filter) {
  var nodes = data.nodes.where((n) {
    final layer = n.graphLayer ?? 'knowledge';
    if (!filter.visibleLayers.contains(layer)) return false;
    if (filter.hiddenEntityTypes.contains(n.entityType)) return false;
    if (filter.selectedDocumentId != null && n.documentId != filter.selectedDocumentId) {
      return false;
    }
    if (filter.searchQuery.isNotEmpty) {
      final q = filter.searchQuery.toLowerCase();
      final match = n.label.toLowerCase().contains(q) ||
          (n.originalName?.toLowerCase().contains(q) ?? false) ||
          (n.displayName?.toLowerCase().contains(q) ?? false) ||
          (n.aliases?.any((a) => a.toLowerCase().contains(q)) ?? false);
      if (!match) return false;
    }
    return true;
  }).toList();

  if (filter.viewScope == GraphViewScope.neighborhood1 && filter.centerNodeId != null) {
    final ids = GraphLayoutEngine.neighborhoodIds(filter.centerNodeId!, data.edges, hops: 1);
    nodes = nodes.where((n) => ids.contains(n.id)).toList();
  } else if (filter.viewScope == GraphViewScope.neighborhood2 && filter.centerNodeId != null) {
    final ids = GraphLayoutEngine.neighborhoodIds(filter.centerNodeId!, data.edges, hops: 2);
    nodes = nodes.where((n) => ids.contains(n.id)).toList();
  }

  if (filter.aggregateMode && nodes.length > 200) {
    final coreIds = GraphLayoutEngine.coreNodeIds(nodes, data.edges, maxCore: 80);
    nodes = nodes.where((n) => coreIds.contains(n.id)).toList();
  }

  final nodeIds = nodes.map((n) => n.id).toSet();
  var edges = data.edges.where((e) {
    if (!nodeIds.contains(e.source) || !nodeIds.contains(e.target)) return false;
    final layer = e.graphLayer ?? 'knowledge';
    if (!filter.visibleLayers.contains(layer)) return false;
    if (filter.hiddenRelationTypes.contains(e.relation)) return false;
    if (filter.hideWeakRelations && e.weight < 0.4) return false;
    if (e.weight < filter.minConfidence) return false;
    return true;
  }).toList();

  if (filter.hideIsolatedNodes) {
    final connected = <String>{};
    for (final e in edges) {
      connected.add(e.source);
      connected.add(e.target);
    }
    nodes = nodes.where((n) => connected.contains(n.id)).toList();
    final nids = nodes.map((n) => n.id).toSet();
    edges = edges.where((e) => nids.contains(e.source) && nids.contains(e.target)).toList();
  }

  return FilteredGraphData(
    nodes: nodes,
    edges: edges,
    totalNodes: data.nodes.length,
    totalEdges: data.edges.length,
  );
}

class FilteredGraphData {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final int totalNodes;
  final int totalEdges;

  FilteredGraphData({
    required this.nodes,
    required this.edges,
    required this.totalNodes,
    required this.totalEdges,
  });
}