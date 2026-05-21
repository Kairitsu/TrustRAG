import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
              Text('审核记录',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(reviewListProvider),
                tooltip: '刷新',
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
                  Text('加载失败: $e',
                      style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(reviewListProvider),
                    child: const Text('重试'),
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
                      Text('暂无审核记录',
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(color: Colors.grey)),
                      const SizedBox(height: 8),
                      Text('在对话中审核 AI 引用后，记录将在此处显示',
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
                            label: '通过',
                            count: stats['approved']!,
                            color: Colors.green),
                        const SizedBox(width: 8),
                        _StatCard(
                            label: '拒绝',
                            count: stats['rejected']!,
                            color: Colors.red),
                        const SizedBox(width: 8),
                        _StatCard(
                            label: '存疑',
                            count: stats['flagged']!,
                            color: Colors.orange),
                        const SizedBox(width: 8),
                        _StatCard(
                            label: '待定',
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
    final (icon, color, label) = _statusInfo(review.status);

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
                  '修正: ${review.correctedText!}',
                  style: TextStyle(
                      fontSize: 13, color: Colors.blue.shade700),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '引用 ID: ${review.citationId.substring(0, 8)}...',
              style: TextStyle(
                  fontSize: 11, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String) _statusInfo(String status) {
    return switch (status) {
      'approved' => (Icons.check_circle, Colors.green, '通过'),
      'rejected' => (Icons.cancel, Colors.red, '拒绝'),
      'flagged' => (Icons.flag, Colors.orange, '存疑'),
      'pending' => (Icons.hourglass_empty, Colors.grey, '待定'),
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
