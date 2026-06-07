import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../../dashboard/providers/workspace_provider.dart';
import '../providers/graph_filter_provider.dart';
import '../providers/graph_generation_controller.dart';
import '../providers/knowledge_graph_provider.dart';

class GraphLayerPanel extends ConsumerWidget {
  const GraphLayerPanel({super.key});

  static const _layers = <String, (String, String, IconData)>{
    'document': ('文档网络', '以文档为节点，表示同文件夹、共享实体等文档级关系', Icons.description_outlined),
    'semantic': ('语义图谱', '基于共现、共享实体、主题相似的语义关系', Icons.hub_outlined),
    'knowledge': ('知识图谱', 'LLM 抽取的监管实体、法规、义务与限制关系', Icons.psychology_outlined),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(graphFilterProvider);
    final layerStatsAsync = ref.watch(layerStatsProvider);
    final job = ref.watch(graphGenerationControllerProvider);
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('图层', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._layers.entries.map((entry) {
              final key = entry.key;
              final (title, desc, icon) = entry.value;
              final stat = layerStatsAsync.valueOrNull?.layer(key);
              final generated = stat?.generated ?? false;
              final visible = filter.visibleLayers.contains(key);
              final isRunning = job.isActive &&
                  ((key == 'document' && job.jobType == 'document_layer') ||
                      (key == 'semantic' && job.jobType == 'semantic_layer') ||
                      (key == 'knowledge' && job.jobType.startsWith('knowledge')));

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 16, color: visible ? theme.colorScheme.primary : Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        Tooltip(
                          message: desc,
                          child: Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                        ),
                        const SizedBox(width: 4),
                        Switch(
                          value: visible,
                          onChanged: (v) {
                            if (!v && filter.visibleLayers.length <= 1) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('至少保留一个可见图层')),
                              );
                              return;
                            }
                            ref.read(graphFilterProvider.notifier).toggleLayer(key, visible: v);
                          },
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 22),
                      child: Text(
                        generated
                            ? '节点 ${stat?.entityCount ?? 0} · 边 ${stat?.relationCount ?? 0}'
                            : '未生成',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ),
                    if (!generated && key != 'knowledge')
                      Padding(
                        padding: const EdgeInsets.only(left: 22, top: 4),
                        child: FilledButton.tonalIcon(
                          onPressed: isRunning || job.isActive
                              ? null
                              : () => _generateLayer(ref, key),
                          icon: isRunning
                              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.play_arrow, size: 14),
                          label: Text('生成$title', style: const TextStyle(fontSize: 11)),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        ),
                      ),
                    if (!generated && key == 'knowledge')
                      Padding(
                        padding: const EdgeInsets.only(left: 22, top: 4),
                        child: Text(
                          '请使用顶部菜单「生成知识图谱」',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _generateLayer(WidgetRef ref, String layer) async {
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;
    final locale = ref.read(localeProvider);
    final lang = switch (locale?.languageCode) {
      'zh' => 'zh',
      'ja' => 'ja',
      'ko' => 'ko',
      _ => 'en',
    };
    await ref.read(graphGenerationControllerProvider.notifier).startLayerGeneration(ws.id, layer, lang);
  }
}