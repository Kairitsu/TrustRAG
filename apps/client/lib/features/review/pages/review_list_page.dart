import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../chat/providers/review_provider.dart';

final reviewListProvider =
    FutureProvider.autoDispose<List<ReviewRecord>>((ref) async {
  final service = ref.read(reviewServiceProvider);
  return service.listAllReviews(limit: 100);
});

class ReviewListPage extends ConsumerWidget {
  const ReviewListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(reviewListProvider);
    final theme = Theme.of(context);
    final s = S.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
          ),
          child: Row(
            children: [
              Text(s.reviewRecords,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              _ExportReportButton(),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(reviewListProvider),
                tooltip: s.refresh,
              ),
            ],
          ),
        ),
        Expanded(
          child: reviewsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                  const SizedBox(height: 12),
                  Text(s.loadFailed(e.toString()),
                      style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(reviewListProvider),
                    child: Text(s.retry),
                  ),
                ],
              ),
            ),
            data: (reviews) {
              if (reviews.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.rate_review_outlined,
                          size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(s.noReviewRecords,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(color: Colors.grey)),
                      const SizedBox(height: 8),
                      Text(s.reviewRecordsHint,
                          style: TextStyle(color: Colors.grey.shade500)),
                    ],
                  ),
                );
              }

              final stats = _calcStats(reviews);

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _StatCard(
                            label: s.approved,
                            count: stats['approved']!,
                            color: Colors.green),
                        const SizedBox(width: 8),
                        _StatCard(
                            label: s.rejected,
                            count: stats['rejected']!,
                            color: Colors.red),
                        const SizedBox(width: 8),
                        _StatCard(
                            label: s.flagged,
                            count: stats['flagged']!,
                            color: Colors.orange),
                        const SizedBox(width: 8),
                        _StatCard(
                            label: s.pending,
                            count: stats['pending']!,
                            color: Colors.grey),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: reviews.length,
                      itemBuilder: (ctx, i) =>
                          _ReviewCard(review: reviews[i]),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Map<String, int> _calcStats(List<ReviewRecord> reviews) {
    final stats = {
      'approved': 0,
      'rejected': 0,
      'flagged': 0,
      'pending': 0,
    };
    for (final r in reviews) {
      if (stats.containsKey(r.status)) {
        stats[r.status] = stats[r.status]! + 1;
      }
    }
    return stats;
  }
}

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
                        const SizedBox(width: 8),
                        _MiniStatChip(
                            label: s.pending,
                            count: report.stats.pending,
                            color: Colors.grey),
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

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatCard({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text('$count',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final ReviewRecord review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final (icon, color, label) = _statusInfo(context, review.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
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
                  child: Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ),
                const Spacer(),
                Text(
                  _formatDate(review.createdAt),
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
            if (review.comment != null && review.comment!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(review.comment!,
                  style: const TextStyle(fontSize: 14)),
            ],
            if (review.correctedText != null &&
                review.correctedText!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${s.correction}: ${review.correctedText!}',
                  style: TextStyle(
                      fontSize: 13, color: Colors.blue.shade700),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Citation ID: ${review.citationId.substring(0, 8)}...',
              style: TextStyle(
                  fontSize: 11, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String) _statusInfo(BuildContext context, String status) {
    final s = S.of(context);
    return switch (status) {
      'approved' => (Icons.check_circle, Colors.green, s.approved),
      'rejected' => (Icons.cancel, Colors.red, s.rejected),
      'flagged' => (Icons.flag, Colors.orange, s.flagged),
      'pending' => (Icons.hourglass_empty, Colors.grey, s.pending),
      _ => (Icons.help_outline, Colors.grey, status),
    };
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
