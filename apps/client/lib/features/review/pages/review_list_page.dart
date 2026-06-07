import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error_messages.dart';
import '../../../l10n/app_localizations.dart';
import '../../chat/providers/review_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../providers/review_list_provider.dart';
import '../providers/review_navigation_provider.dart';

class ReviewListPage extends ConsumerWidget {
  const ReviewListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listState = ref.watch(reviewListNotifierProvider);
    final theme = Theme.of(context);
    final s = S.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor, width: 1),
            ),
          ),
          child: Row(
            children: [
              Text(
                s.reviewRecords,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _ExportReportButton(),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    ref.read(reviewListNotifierProvider.notifier).load(),
                tooltip: s.refresh,
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildBody(context, ref, listState, theme, s),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    ReviewListState listState,
    ThemeData theme,
    S s,
  ) {
    if (listState.loading && listState.records.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (listState.error != null && listState.records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: theme.colorScheme.error.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(
              s.loadFailed(
                friendlyApiError(
                  listState.error!,
                  fallback: '无法加载审核记录',
                ),
              ),
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () =>
                  ref.read(reviewListNotifierProvider.notifier).load(),
              child: Text(s.retry),
            ),
          ],
        ),
      );
    }

    if (listState.records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rate_review_outlined,
                size: 80, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              s.noReviewRecords,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              s.reviewRecordsHint,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final filtered = listState.filteredRecords;
    final counts = listState.counts;
    final selected = listState.selectedStatus;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              _FilterChip(
                key: const ValueKey('filter-all'),
                label: '全部',
                isActive: selected == ReviewFilterStatus.all,
                color: theme.colorScheme.primary,
                onTap: () => ref
                    .read(reviewListNotifierProvider.notifier)
                    .setFilter(ReviewFilterStatus.all),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  key: const ValueKey('stat-approved'),
                  label: s.approved,
                  count: counts.approved,
                  color: Colors.green,
                  isActive: selected == ReviewFilterStatus.approved,
                  onTap: () => ref
                      .read(reviewListNotifierProvider.notifier)
                      .setFilter(ReviewFilterStatus.approved),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  key: const ValueKey('stat-rejected'),
                  label: s.rejected,
                  count: counts.rejected,
                  color: Colors.red,
                  isActive: selected == ReviewFilterStatus.rejected,
                  onTap: () => ref
                      .read(reviewListNotifierProvider.notifier)
                      .setFilter(ReviewFilterStatus.rejected),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  key: const ValueKey('stat-flagged'),
                  label: s.flagged,
                  count: counts.suspicious,
                  color: Colors.orange,
                  isActive: selected == ReviewFilterStatus.suspicious,
                  onTap: () => ref
                      .read(reviewListNotifierProvider.notifier)
                      .setFilter(ReviewFilterStatus.suspicious),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _emptyFilterMessage(selected, s),
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 15,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) => _ReviewCard(review: filtered[i]),
                ),
        ),
      ],
    );
  }

  String _emptyFilterMessage(ReviewFilterStatus filter, S s) {
    return switch (filter) {
      ReviewFilterStatus.approved => '暂无通过记录',
      ReviewFilterStatus.rejected => '暂无拒绝记录',
      ReviewFilterStatus.suspicious => '暂无存疑记录',
      ReviewFilterStatus.all => s.noReviewRecords,
    };
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    super.key,
    required this.label,
    required this.isActive,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? color.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? color : Colors.grey.shade300,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive ? color : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  const _StatCard({
    super.key,
    required this.label,
    required this.count,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? color.withValues(alpha: 0.14) : color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      elevation: isActive ? 2 : 0,
      shadowColor: isActive ? color.withValues(alpha: 0.3) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: color.withValues(alpha: 0.12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? color : color.withValues(alpha: 0.2),
              width: isActive ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: color.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  final ReviewRecordEnriched review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (icon, color, label) = _statusInfo(context, review.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _navigateToSource(context, ref),
        hoverColor: theme.colorScheme.primary.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(review.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.info_outline, size: 18),
                    tooltip: '查看详情',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => _showDetailDialog(context),
                  ),
                ],
              ),
              if (review.textExcerpt != null &&
                  review.textExcerpt!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  review.textExcerpt!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ] else if (review.comment != null &&
                  review.comment!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  review.comment!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 8),
              Tooltip(
                message: review.citationId.isNotEmpty
                    ? review.citationId
                    : '无 Citation ID',
                child: Text(
                  'Citation ID: ${review.citationShortId.isNotEmpty ? review.citationShortId : _shortId(review.citationId)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (!review.targetAvailable) ...[
                const SizedBox(height: 6),
                Text(
                  '缺少定位信息',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.error.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToSource(BuildContext context, WidgetRef ref) async {
    ReviewTarget? target;

    if (review.targetAvailable &&
        review.conversationId != null &&
        review.messageId != null) {
      target = ReviewTarget(
        auditRecordId: review.id,
        conversationId: review.conversationId,
        messageId: review.messageId,
        citationId: review.citationId.isNotEmpty ? review.citationId : null,
        documentId: review.documentId,
        chunkId: review.chunkId,
        targetAvailable: true,
      );
    } else {
      final service = ref.read(reviewServiceProvider);
      try {
        if (review.id.isNotEmpty) {
          target = await service.getReviewTarget(review.id);
        } else if (review.citationId.isNotEmpty) {
          target = await service.getReviewTargetByCitation(review.citationId);
        }
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('该审核记录缺少定位信息，无法跳转到原始上下文。'),
          ),
        );
        return;
      }
    }

    if (target == null || !target.targetAvailable) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法定位该审核记录，对应对话或引用可能已被删除。'),
        ),
      );
      return;
    }

    ref.read(reviewNavigationTargetProvider.notifier).state =
        ReviewNavigationTarget(
      conversationId: target.conversationId,
      messageId: target.messageId,
      citationId: target.citationId,
      auditRecordId: target.auditRecordId ?? review.id,
    );
    ref.read(dashboardTabProvider.notifier).state = 0;
  }

  void _showDetailDialog(BuildContext context) {
    final s = S.of(context);
    final (_, color, label) = _statusInfo(context, review.status);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('审核记录详情'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('状态', label, valueColor: color),
              _detailRow('Citation ID', review.citationId),
              if (review.textExcerpt != null)
                _detailRow('审核内容', review.textExcerpt!),
              if (review.comment != null) _detailRow('备注', review.comment!),
              if (review.documentTitle != null)
                _detailRow(s.document, review.documentTitle!),
              if (review.conversationTitle != null)
                _detailRow('所属对话', review.conversationTitle!),
              if (review.messageId != null)
                _detailRow('Message ID', review.messageId!),
              if (review.chunkId != null) _detailRow('Chunk ID', review.chunkId!),
              _detailRow('创建时间', _formatDate(review.createdAt)),
              _detailRow('更新时间', _formatDate(review.updatedAt)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: TextStyle(fontSize: 13, color: valueColor),
          ),
        ],
      ),
    );
  }

  (IconData, Color, String) _statusInfo(BuildContext context, String status) {
    final s = S.of(context);
    return switch (status) {
      'approved' => (Icons.check_circle, Colors.green, s.approved),
      'rejected' => (Icons.cancel, Colors.red, s.rejected),
      'flagged' => (Icons.flag, Colors.orange, s.flagged),
      'pending' => (Icons.hourglass_empty, Colors.grey, '未审核'),
      _ => (Icons.help_outline, Colors.grey, status),
    };
  }

  String _shortId(String id) {
    if (id.length > 8) return '${id.substring(0, 8)}...';
    return id;
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }
}

// --- Export report section (unchanged functionality) ---

class _ExportReportButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ExportReportButton> createState() =>
      _ExportReportButtonState();
}

class _ExportReportButtonState extends ConsumerState<_ExportReportButton> {
  bool _loading = false;

  Future<void> _exportReport() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(reviewServiceProvider);
      final report = await service.getReport();
      final markdown = await service.getReportMarkdown();
      if (!mounted) return;
      _showReportDialog(report, markdown);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.of(context).reportLoadFailed}: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showReportDialog(ReviewReportData report, String markdown) {
    showDialog(
      context: context,
      builder: (ctx) => _ReportDialog(report: report, markdown: markdown),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return _loading
        ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : IconButton(
            icon: const Icon(Icons.summarize_outlined),
            onPressed: _exportReport,
            tooltip: s.exportReport,
          );
  }
}

class _ReportDialog extends StatelessWidget {
  final ReviewReportData report;
  final String markdown;

  const _ReportDialog({required this.report, required this.markdown});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final reviewed = report.stats.totalCitations - report.stats.unreviewed;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.summarize, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.reviewReport,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(s.reportGeneratedAt(report.generatedAt),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: s.copyMarkdown,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: markdown));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.copiedToClipboard)),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.overview,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _MetricGrid(
                      items: [
                        _MetricItem(
                          label: s.totalCitations,
                          value: '${report.stats.totalCitations}',
                          icon: Icons.format_quote,
                        ),
                        _MetricItem(
                          label: s.reviewed,
                          value: '$reviewed',
                          icon: Icons.fact_check,
                        ),
                        _MetricItem(
                          label: s.unreviewedCount,
                          value: '${report.stats.unreviewed}',
                          icon: Icons.pending_actions,
                        ),
                        _MetricItem(
                          label: s.reviewCoverage,
                          value: '${report.reviewCoverage.toStringAsFixed(1)}%',
                          icon: Icons.pie_chart,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(s.keyMetrics,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _MetricBar(
                      label: s.approvalRate,
                      value: report.approvalRate,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 8),
                    _MetricBar(
                      label: s.rejectionRate,
                      value: report.rejectionRate,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 8),
                    _MetricBar(
                      label: s.hallucinationRate,
                      value: report.hallucinationRate,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 24),
                    Text(s.reviewResults,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MiniStatChip(
                            label: s.approved,
                            count: report.stats.approved,
                            color: Colors.green),
                        const SizedBox(width: 8),
                        _MiniStatChip(
                            label: s.rejected,
                            count: report.stats.rejected,
                            color: Colors.red),
                        const SizedBox(width: 8),
                        _MiniStatChip(
                            label: s.flagged,
                            count: report.stats.flagged,
                            color: Colors.orange),
                        if (report.stats.pending > 0) ...[
                          const SizedBox(width: 8),
                          _MiniStatChip(
                              label: s.pending,
                              count: report.stats.pending,
                              color: Colors.grey),
                        ],
                      ],
                    ),
                    if (report.recentReviews.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(s.reviewDetails,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ...report.recentReviews
                          .take(20)
                          .map((r) => _ReportDetailCard(review: r)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricItem {
  final String label;
  final String value;
  final IconData icon;
  const _MetricItem(
      {required this.label, required this.value, required this.icon});
}

class _MetricGrid extends StatelessWidget {
  final List<_MetricItem> items;
  const _MetricGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items.map((item) {
        return SizedBox(
          width: 150,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.icon, size: 20, color: Colors.grey.shade600),
                const SizedBox(height: 8),
                Text(item.value,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(item.label,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MetricBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _MetricBar(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const Spacer(),
            Text('${value.toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (value / 100).clamp(0.0, 1.0),
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class _MiniStatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _MiniStatChip(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text('$count',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }
}

class _ReportDetailCard extends StatelessWidget {
  final ReviewRecordWithContext review;
  const _ReportDetailCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final (icon, color) = switch (review.status) {
      'approved' => (Icons.check_circle, Colors.green),
      'rejected' => (Icons.cancel, Colors.red),
      'flagged' => (Icons.flag, Colors.orange),
      'pending' => (Icons.hourglass_empty, Colors.grey),
      _ => (Icons.help_outline, Colors.grey),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Text(review.status,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w600, fontSize: 13)),
                const Spacer(),
                Text(review.createdAt,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
            if (review.documentTitle != null) ...[
              const SizedBox(height: 6),
              Text('${s.document}: ${review.documentTitle}',
                  style: const TextStyle(fontSize: 13)),
            ],
            if (review.headingPath != null) ...[
              const SizedBox(height: 2),
              Text('${s.section}: ${review.headingPath}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
            if (review.pageNumber != null) ...[
              const SizedBox(height: 2),
              Text('${s.page}: ${review.pageNumber}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
            if (review.quotedText != null &&
                review.quotedText!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  review.quotedText!.length > 200
                      ? '${review.quotedText!.substring(0, 200)}...'
                      : review.quotedText!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
            ],
            if (review.comment != null && review.comment!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('💬 ${review.comment}',
                  style: const TextStyle(fontSize: 13)),
            ],
            if (review.correctedText != null &&
                review.correctedText!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${s.correction}: ${review.correctedText}',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}