import 'package:flutter/material.dart';
import '../providers/graph_filter_provider.dart';

class GraphEmptyState extends StatelessWidget {
  final GraphEmptyReason reason;
  final VoidCallback? onGenerateKnowledge;
  final VoidCallback? onGenerateDocument;
  final VoidCallback? onGenerateSemantic;
  final VoidCallback? onShowAllLayers;
  final VoidCallback? onClearSearch;
  final bool isGenerating;

  const GraphEmptyState({
    super.key,
    required this.reason,
    this.onGenerateKnowledge,
    this.onGenerateDocument,
    this.onGenerateSemantic,
    this.onShowAllLayers,
    this.onClearSearch,
    this.isGenerating = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, subtitle, actions) = _content();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 72, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleLarge?.copyWith(color: Colors.grey.shade700), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }

  (IconData, String, String, List<Widget>) _content() {
    return switch (reason) {
      GraphEmptyReason.generating => (
          Icons.hourglass_top,
          '正在生成图谱',
          '任务运行中，实体和关系将自动刷新显示',
          [const SizedBox(height: 8)],
        ),
      GraphEmptyReason.notGenerated => (
          Icons.hub_outlined,
          '尚未生成知识图谱',
          '工作区已有文档，但还未从文档中抽取实体与关系',
          [
            if (onGenerateKnowledge != null)
              FilledButton.icon(
                onPressed: isGenerating ? null : onGenerateKnowledge,
                icon: const Icon(Icons.auto_fix_high),
                label: Text(isGenerating ? '生成中…' : '生成知识图谱'),
              ),
          ],
        ),
      GraphEmptyReason.layerFilterEmpty => (
          Icons.layers_outlined,
          '当前图层过滤条件下没有可见节点',
          '图谱数据存在，但当前图层开关或过滤条件隐藏了所有节点',
          [
            if (onShowAllLayers != null)
              OutlinedButton.icon(
                onPressed: onShowAllLayers,
                icon: const Icon(Icons.visibility),
                label: const Text('显示全部图层'),
              ),
          ],
        ),
      GraphEmptyReason.searchEmpty => (
          Icons.search_off,
          '搜索无结果',
          '没有匹配当前搜索条件的实体',
          [
            if (onClearSearch != null)
              OutlinedButton.icon(
                onPressed: onClearSearch,
                icon: const Icon(Icons.clear),
                label: const Text('清除搜索'),
              ),
          ],
        ),
      GraphEmptyReason.entitiesNoRelations => (
          Icons.link_off,
          '已生成实体但未生成关系',
          '实体已抽取，但关系可能因 LLM 端点匹配失败而未保存。请查看生成日志中的警告信息。',
          [
            if (onGenerateKnowledge != null)
              OutlinedButton.icon(
                onPressed: onGenerateKnowledge,
                icon: const Icon(Icons.refresh),
                label: const Text('重新生成'),
              ),
          ],
        ),
      GraphEmptyReason.loadError => (
          Icons.error_outline,
          '图谱加载失败',
          '无法从服务器获取图谱数据，请检查网络或稍后重试',
          [],
        ),
      _ => (
          Icons.hub_outlined,
          '暂无图谱数据',
          '',
          [],
        ),
    };
  }
}