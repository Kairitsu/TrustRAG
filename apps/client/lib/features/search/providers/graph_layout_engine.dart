import 'dart:math';
import 'package:flutter/material.dart';
import 'knowledge_graph_provider.dart';

enum GraphLayoutMode { forceDirected, radial, cluster }

class GraphLayoutEngine {
  static void applyLayout({
    required List<GraphNode> nodes,
    required List<GraphEdge> edges,
    required Size canvasSize,
    GraphLayoutMode mode = GraphLayoutMode.forceDirected,
    String? centerNodeId,
    int iterations = 80,
  }) {
    if (nodes.isEmpty) return;

    final cx = canvasSize.width / 2;
    final cy = canvasSize.height / 2;
    final count = nodes.length;
    final scale = _layoutScale(count, canvasSize);

    if (mode == GraphLayoutMode.radial && centerNodeId != null) {
      _radialLayout(nodes, edges, centerNodeId, cx, cy, scale);
      return;
    }

    if (mode == GraphLayoutMode.cluster || count > 200) {
      _clusterLayout(nodes, cx, cy, scale);
      _forceDirected(nodes, edges, canvasSize, iterations: iterations ~/ 2);
      return;
    }

    _initialScatter(nodes, cx, cy, scale);
    _forceDirected(nodes, edges, canvasSize, iterations: iterations);
  }

  static double _layoutScale(int count, Size size) {
    final base = min(size.width, size.height) * 0.35;
    if (count <= 30) return base;
    if (count <= 100) return base * 1.2;
    if (count <= 200) return base * 1.5;
    return base * 2.0;
  }

  static void _initialScatter(List<GraphNode> nodes, double cx, double cy, double radius) {
    final rng = Random(42);
    for (var i = 0; i < nodes.length; i++) {
      final angle = (2 * pi * i) / nodes.length;
      final r = radius * (0.3 + rng.nextDouble() * 0.7);
      nodes[i].position = Offset(cx + r * cos(angle), cy + r * sin(angle));
      nodes[i].velocity = Offset.zero;
    }
  }

  static void _forceDirected(
    List<GraphNode> nodes,
    List<GraphEdge> edges,
    Size canvasSize, {
    int iterations = 80,
  }) {
    if (nodes.length < 2) return;

    final nodeMap = {for (final n in nodes) n.id: n};
    final count = nodes.length;
    final area = canvasSize.width * canvasSize.height;
    final k = sqrt(area / count.clamp(1, 10000));
    final repulsion = k * k;
    final attraction = 0.08;
    final damping = 0.85;
    final maxVel = 10.0;

    for (var iter = 0; iter < iterations; iter++) {
      final cooling = 1.0 - (iter / iterations);

      for (var i = 0; i < nodes.length; i++) {
        for (var j = i + 1; j < nodes.length; j++) {
          final a = nodes[i];
          final b = nodes[j];
          var dx = a.position.dx - b.position.dx;
          var dy = a.position.dy - b.position.dy;
          var dist = sqrt(dx * dx + dy * dy);
          if (dist < 1) dist = 1;
          final force = repulsion / dist * cooling;
          dx = (dx / dist) * force;
          dy = (dy / dist) * force;
          a.velocity += Offset(dx, dy);
          b.velocity -= Offset(dx, dy);
        }
      }

      for (final edge in edges) {
        final src = nodeMap[edge.source];
        final tgt = nodeMap[edge.target];
        if (src == null || tgt == null) continue;
        var dx = tgt.position.dx - src.position.dx;
        var dy = tgt.position.dy - src.position.dy;
        var dist = sqrt(dx * dx + dy * dy);
        if (dist < 1) dist = 1;
        final force = dist * attraction * edge.weight.clamp(0.3, 1.0) * cooling;
        dx = (dx / dist) * force;
        dy = (dy / dist) * force;
        src.velocity += Offset(dx, dy);
        tgt.velocity -= Offset(dx, dy);
      }

      final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
      for (final node in nodes) {
        var dx = center.dx - node.position.dx;
        var dy = center.dy - node.position.dy;
        node.velocity += Offset(dx * 0.001 * cooling, dy * 0.001 * cooling);

        if (node.velocity.distance > maxVel) {
          node.velocity = Offset.fromDirection(
            node.velocity.direction,
            maxVel,
          );
        }
        node.position += node.velocity;
        node.velocity *= damping;

        node.position = Offset(
          node.position.dx.clamp(20, canvasSize.width - 20),
          node.position.dy.clamp(20, canvasSize.height - 20),
        );
      }
    }
  }

  static void _radialLayout(
    List<GraphNode> nodes,
    List<GraphEdge> edges,
    String centerId,
    double cx,
    double cy,
    double scale,
  ) {
    final nodeMap = {for (final n in nodes) n.id: n};
    final center = nodeMap[centerId];
    if (center == null) {
      _initialScatter(nodes, cx, cy, scale);
      return;
    }
    center.position = Offset(cx, cy);

    final neighbors = <String>{};
    for (final e in edges) {
      if (e.source == centerId) neighbors.add(e.target);
      if (e.target == centerId) neighbors.add(e.source);
    }

    var i = 0;
    for (final nid in neighbors) {
      final n = nodeMap[nid];
      if (n == null) continue;
      final angle = (2 * pi * i) / neighbors.length.clamp(1, 100);
      n.position = Offset(cx + scale * 0.5 * cos(angle), cy + scale * 0.5 * sin(angle));
      i++;
    }

    var ring = 1;
    for (final node in nodes) {
      if (node.id == centerId || neighbors.contains(node.id)) continue;
      final angle = (2 * pi * ring) / nodes.length;
      final r = scale * (0.7 + (ring % 3) * 0.15);
      node.position = Offset(cx + r * cos(angle), cy + r * sin(angle));
      ring++;
    }
  }

  static void _clusterLayout(List<GraphNode> nodes, double cx, double cy, double scale) {
    final typeGroups = <String, List<GraphNode>>{};
    for (final n in nodes) {
      typeGroups.putIfAbsent(n.entityType, () => []).add(n);
    }
    final types = typeGroups.keys.toList();
    for (var ti = 0; ti < types.length; ti++) {
      final group = typeGroups[types[ti]]!;
      final groupAngle = (2 * pi * ti) / types.length;
      final gx = cx + scale * 0.6 * cos(groupAngle);
      final gy = cy + scale * 0.6 * sin(groupAngle);
      for (var i = 0; i < group.length; i++) {
        final angle = (2 * pi * i) / group.length.clamp(1, 100);
        final r = min(80.0, 20.0 + group.length * 0.5);
        group[i].position = Offset(gx + r * cos(angle), gy + r * sin(angle));
      }
    }
  }

  static Set<String> coreNodeIds(List<GraphNode> nodes, List<GraphEdge> edges, {int maxCore = 50}) {
    if (nodes.length <= maxCore) {
      return nodes.map((n) => n.id).toSet();
    }
    final degree = <String, int>{};
    for (final e in edges) {
      degree[e.source] = (degree[e.source] ?? 0) + 1;
      degree[e.target] = (degree[e.target] ?? 0) + 1;
    }
    final sorted = nodes.toList()
      ..sort((a, b) => (degree[b.id] ?? 0).compareTo(degree[a.id] ?? 0));
    return sorted.take(maxCore).map((n) => n.id).toSet();
  }

  static Set<String> neighborhoodIds(String nodeId, List<GraphEdge> edges, {int hops = 1}) {
    final result = <String>{nodeId};
    var frontier = {nodeId};
    for (var h = 0; h < hops; h++) {
      final next = <String>{};
      for (final e in edges) {
        if (frontier.contains(e.source)) next.add(e.target);
        if (frontier.contains(e.target)) next.add(e.source);
      }
      result.addAll(next);
      frontier = next;
    }
    return result;
  }
}