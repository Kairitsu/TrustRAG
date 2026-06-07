import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error_messages.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart';
import '../../dashboard/providers/workspace_provider.dart';
import '../providers/graph_filter_provider.dart';
import '../providers/graph_generation_controller.dart';
import '../providers/knowledge_graph_provider.dart';
import '../widgets/graph_canvas.dart';
import '../widgets/graph_empty_state.dart';
import '../widgets/graph_progress_banner.dart';

class KnowledgeGraphPage extends ConsumerStatefulWidget {
  const KnowledgeGraphPage({super.key});

  @override
  ConsumerState<KnowledgeGraphPage> createState() => _KnowledgeGraphPageState();
}

class _KnowledgeGraphPageState extends ConsumerState<KnowledgeGraphPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _entityFilter = '';

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

  String _targetLanguage() {
    final locale = ref.read(localeProvider);
    return switch (locale?.languageCode) {
      'zh' => 'zh',
      'ja' => 'ja',
      'ko' => 'ko',
      _ => 'en',
    };
  }

  Future<void> _generateKnowledge() async {
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;
    try {
      await ref.read(graphGenerationControllerProvider.notifier)
          .startKnowledgeGeneration(ws.id, _targetLanguage());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图谱生成失败: $e'), backgroundColor: Colors.red),
        );
      }
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
      ref.invalidate(graphDataProvider);
      ref.invalidate(entityListProvider);
      ref.invalidate(knowledgeGraphStatsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图谱已清空')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清空失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showGenerationHistory() {
    ref.invalidate(generationHistoryProvider);
    showDialog(context: context, builder: (ctx) => const _GenerationHistoryDialog());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final ws = ref.watch(selectedWorkspaceProvider);
    final theme = Theme.of(context);
    final job = ref.watch(graphGenerationControllerProvider);

    if (ws == null) {
      return Center(
        child: Text(s.selectWorkspaceFirst, style: TextStyle(color: Colors.grey.shade500)),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(s.knowledgeGraph, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      switch (value) {
                        case 'generate':
                          _generateKnowledge();
                          break;
                        case 'history':
                          _showGenerationHistory();
                          break;
                        case 'reset':
                          _resetGraph();
                          break;
                        case 'refresh':
                          ref.invalidate(graphDataProvider);
                          ref.invalidate(entityListProvider);
                          ref.invalidate(knowledgeGraphStatsProvider);
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'generate',
                        enabled: !job.isActive,
                        child: const ListTile(
                          leading: Icon(Icons.auto_fix_high),
                          title: Text('生成知识图谱'),
                          subtitle: Text('从所有 ready 文档抽取实体和关系', style: TextStyle(fontSize: 11)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'history',
                        child: ListTile(
                          leading: Icon(Icons.history),
                          title: Text('生成历史'),
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
              Text(s.knowledgeGraphDesc(ws.name), style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                tabs: [Tab(text: s.graphView), Tab(text: s.entityList)],
              ),
            ],
          ),
        ),
        GraphProgressBanner(onShowLogs: _showGenerationHistory),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _GraphViewTab(onGenerate: _generateKnowledge),
              _EntityListTab(filter: _entityFilter, onFilterChanged: (v) => setState(() => _entityFilter = v)),
            ],
          ),
        ),
      ],
    );
  }
}

class _GraphViewTab extends ConsumerWidget {
  final VoidCallback onGenerate;

  const _GraphViewTab({required this.onGenerate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graphAsync = ref.watch(graphDataProvider);
    final filteredAsync = ref.watch(filteredGraphProvider);
    final layerStatsAsync = ref.watch(layerStatsProvider);
    final filter = ref.watch(graphFilterProvider);
    final job = ref.watch(graphGenerationControllerProvider);

    return graphAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => GraphEmptyState(
        reason: GraphEmptyReason.loadError,
        onGenerateKnowledge: onGenerate,
      ),
      data: (fullData) {
        if (fullData == null) return const SizedBox.shrink();

        final filtered = filteredAsync.valueOrNull;
        final emptyReason = resolveEmptyReason(
          fullData: fullData,
          filteredData: filtered,
          layerStats: layerStatsAsync.valueOrNull,
          isGenerating: job.isActive,
          filter: filter,
        );

        if (emptyReason != null) {
          return GraphEmptyState(
            reason: emptyReason,
            isGenerating: job.isActive,
            onGenerateKnowledge: onGenerate,
            onShowAllLayers: () {
              ref.read(graphFilterProvider.notifier).showAllLayers();
              ref.invalidate(graphDataProvider);
            },
            onClearSearch: () => ref.read(graphFilterProvider.notifier).setSearchQuery(''),
          );
        }

        if (filtered == null || filtered.nodes.isEmpty) {
          return GraphEmptyState(
            reason: GraphEmptyReason.layerFilterEmpty,
            onShowAllLayers: () => ref.read(graphFilterProvider.notifier).showAllLayers(),
          );
        }

        return GraphCanvas(
          fullData: fullData,
          filtered: filtered,
          onGenerateKnowledge: onGenerate,
        );
      },
    );
  }
}

class _EntityListTab extends ConsumerWidget {
  final String filter;
  final ValueChanged<String> onFilterChanged;

  const _EntityListTab({required this.filter, required this.onFilterChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitiesAsync = ref.watch(entityListProvider);
    final s = S.of(context);
    final theme = Theme.of(context);

    return entitiesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(s.loadFailed(friendlyApiError(e, fallback: '无法加载实体列表')),
            style: TextStyle(color: Colors.grey.shade600)),
      ),
      data: (entities) {
        if (entities.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.category_outlined, size: 80, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(s.noEntities, style: theme.textTheme.headlineSmall?.copyWith(color: Colors.grey)),
              ],
            ),
          );
        }

        final filtered = filter.isEmpty
            ? entities
            : entities.where((e) {
                final q = filter.toLowerCase();
                return e.name.toLowerCase().contains(q) ||
                    (e.originalName?.toLowerCase().contains(q) ?? false) ||
                    (e.aliases?.any((a) => a.toLowerCase().contains(q)) ?? false);
              }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: '搜索实体名称、别名、原文…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
                onChanged: onFilterChanged,
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final e = filtered[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: GraphNode(id: '', label: '', entityType: e.entityType).color.withValues(alpha: 0.2),
                        child: Text(e.entityType.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 10)),
                      ),
                      title: Text(e.displayName ?? e.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${e.entityType}${e.graphLayer != null ? ' · ${e.graphLayer}' : ''}', style: const TextStyle(fontSize: 11)),
                          if (e.originalName != null && e.originalName != e.name)
                            Text('原文: ${e.originalName}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        ],
                      ),
                      isThreeLine: e.originalName != null && e.originalName != e.name,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GenerationHistoryDialog extends ConsumerWidget {
  const _GenerationHistoryDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(generationHistoryProvider);

    return AlertDialog(
      title: const Text('生成历史'),
      content: SizedBox(
        width: 560,
        height: 400,
        child: historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('加载失败: $e'),
          data: (entries) {
            if (entries.isEmpty) return const Center(child: Text('暂无生成记录'));
            return ListView.builder(
              itemCount: entries.length,
              itemBuilder: (ctx, i) {
                final e = entries[i];
                return ExpansionTile(
                  title: Text('${e.status} · ${e.jobType ?? e.triggerType}'),
                  subtitle: Text(
                    '${e.startedAt} · 文档 ${e.processedDocuments}/${e.totalDocuments} · 实体 ${e.entitiesCreated} · 关系 ${e.relationsCreated}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (e.targetLanguage != null) Text('目标语言: ${e.targetLanguage}'),
                          if (e.llmModel != null) Text('模型: ${e.llmProvider ?? ''} / ${e.llmModel}'),
                          Text('成功文档: ${e.succeededDocuments} · 失败: ${e.failedDocuments}'),
                          if (e.relationsSkippedMatch > 0)
                            Text('关系匹配跳过: ${e.relationsSkippedMatch}', style: TextStyle(color: Colors.orange.shade700)),
                          if (e.elapsedMs != null) Text('耗时: ${(e.elapsedMs! / 1000).toStringAsFixed(1)}s'),
                          if (e.warnings.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('警告 (${e.warnings.length}):', style: const TextStyle(fontWeight: FontWeight.w600)),
                            ...e.warnings.take(5).map((w) => Text('• $w', style: const TextStyle(fontSize: 11))),
                          ],
                          if (e.errors.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('错误:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red.shade700)),
                            ...e.errors.take(5).map((err) => Text('• $err', style: const TextStyle(fontSize: 11))),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }
}