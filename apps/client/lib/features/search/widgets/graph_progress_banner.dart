import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/providers/workspace_provider.dart';
import '../providers/graph_generation_controller.dart';

class GraphProgressBanner extends ConsumerWidget {
  final VoidCallback? onShowLogs;

  const GraphProgressBanner({super.key, this.onShowLogs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(graphGenerationControllerProvider);
    if (!job.isActive && !job.isFinished) return const SizedBox.shrink();
    if (job.status == 'idle') return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isActive = job.isActive;

    return Material(
      elevation: 1,
      color: isActive
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : (job.status == 'failed' ? Colors.red.shade50 : Colors.green.shade50),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (isActive)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                Expanded(
                  child: Text(
                    _statusLabel(job),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (isActive)
                  TextButton(
                    onPressed: () {
                      final ws = ref.read(selectedWorkspaceProvider);
                      if (ws != null) {
                        ref.read(graphGenerationControllerProvider.notifier).cancelCurrent(ws.id);
                      }
                    },
                    child: const Text('取消'),
                  ),
                if (onShowLogs != null)
                  TextButton(onPressed: onShowLogs, child: const Text('日志')),
              ],
            ),
            if (isActive && job.totalDocuments > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: job.progressPercent / 100.0,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${job.progressPercent.toStringAsFixed(0)}% · 文档 ${job.processedDocuments}/${job.totalDocuments}'
                '${job.currentDocumentTitle != null ? ' · 当前: ${job.currentDocumentTitle}' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '实体 ${job.entitiesCreated} · 关系 ${job.relationsCreated}'
              '${job.relationsSkippedMatch > 0 ? ' · 跳过匹配 ${job.relationsSkippedMatch}' : ''}'
              '${job.failedDocuments > 0 ? ' · 失败 ${job.failedDocuments}' : ''}'
              '${job.elapsedMs != null ? ' · 耗时 ${(job.elapsedMs! / 1000).toStringAsFixed(0)}s' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(GenerationJobState job) {
    return switch (job.status) {
      'running' => switch (job.jobType) {
          'document_layer' => '正在生成文档网络…',
          'semantic_layer' => '正在生成语义图谱…',
          _ => '正在生成知识图谱…',
        },
      'cancelling' => '正在取消任务…',
      'cancelled' => '任务已取消',
      'failed' => '生成失败',
      'completed' => '生成完成',
      _ => job.status,
    };
  }
}