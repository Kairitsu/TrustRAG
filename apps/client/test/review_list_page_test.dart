import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/features/review/pages/review_list_page.dart';
import 'package:client/features/chat/providers/review_provider.dart';
import 'package:client/features/review/providers/review_list_provider.dart';
import 'package:client/l10n/app_localizations.dart';

ReviewListState _loadedState(List<ReviewRecordEnriched> records) {
  return ReviewListState(
    records: records,
    counts: ReviewCounts(
      approved: records.where((r) => r.status == 'approved').length,
      rejected: records.where((r) => r.status == 'rejected').length,
      suspicious: records.where((r) => r.status == 'flagged').length,
      pending: records.where((r) => r.status == 'pending').length,
    ),
  );
}

Widget _buildTestApp(ReviewListState state) {
  return ProviderScope(
    overrides: [
      reviewListNotifierProvider.overrideWith((ref) {
        return ReviewListNotifier(ref)..state = state;
      }),
    ],
    child: MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      locale: const Locale('zh'),
      home: const Scaffold(body: ReviewListPage()),
    ),
  );
}

final _sampleReviews = [
  ReviewRecordEnriched(
    id: 'r1',
    status: 'approved',
    textExcerpt: 'Looks correct',
    citationId: 'cit-1234-5678-0000-0000',
    citationShortId: 'cit-1234...',
    conversationId: 'conv-1',
    messageId: 'msg-1',
    targetAvailable: true,
    createdAt: '2026-05-21T10:00:00Z',
    updatedAt: '2026-05-21T10:00:00Z',
  ),
  ReviewRecordEnriched(
    id: 'r2',
    status: 'rejected',
    textExcerpt: 'Wrong source',
    citationId: 'cit-2345-6789-0000-0000',
    citationShortId: 'cit-2345...',
    conversationId: 'conv-1',
    messageId: 'msg-2',
    correctedText: 'Fixed citation',
    targetAvailable: true,
    createdAt: '2026-05-21T11:00:00Z',
    updatedAt: '2026-05-21T11:00:00Z',
  ),
  ReviewRecordEnriched(
    id: 'r3',
    status: 'flagged',
    citationId: 'cit-3456-7890-0000-0000',
    citationShortId: 'cit-3456...',
    conversationId: 'conv-1',
    messageId: 'msg-3',
    targetAvailable: true,
    createdAt: '2026-05-21T12:00:00Z',
    updatedAt: '2026-05-21T12:00:00Z',
  ),
  ReviewRecordEnriched(
    id: 'r4',
    status: 'pending',
    citationId: 'cit-4567-8901-0000-0000',
    citationShortId: 'cit-4567...',
    targetAvailable: false,
    createdAt: '2026-05-21T13:00:00Z',
    updatedAt: '2026-05-21T13:00:00Z',
  ),
];

void main() {
  group('ReviewListPage', () {
    testWidgets('shows empty state when no reviews', (tester) async {
      await tester.pumpWidget(_buildTestApp(const ReviewListState()));
      await tester.pumpAndSettle();

      expect(find.text('暂无审核记录'), findsOneWidget);
      expect(find.text('在对话中审核 AI 引用后，记录将在此处显示'), findsOneWidget);
    });

    testWidgets('shows three stat cards without pending', (tester) async {
      await tester.pumpWidget(_buildTestApp(_loadedState(_sampleReviews)));
      await tester.pumpAndSettle();

      expect(find.text('审核记录'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('通过'), findsWidgets);
      expect(find.text('拒绝'), findsWidgets);
      expect(find.text('存疑'), findsWidgets);
      expect(find.text('待定'), findsNothing);
    });

    testWidgets('filters by approved status', (tester) async {
      await tester.pumpWidget(_buildTestApp(_loadedState(_sampleReviews)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('stat-approved')));
      await tester.pumpAndSettle();

      expect(find.text('Looks correct'), findsOneWidget);
      expect(find.text('Wrong source'), findsNothing);
    });

    testWidgets('filters by rejected status', (tester) async {
      await tester.pumpWidget(_buildTestApp(_loadedState(_sampleReviews)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('stat-rejected')));
      await tester.pumpAndSettle();

      expect(find.text('Wrong source'), findsOneWidget);
      expect(find.text('Looks correct'), findsNothing);
    });

    testWidgets('filters by flagged status', (tester) async {
      await tester.pumpWidget(_buildTestApp(_loadedState(_sampleReviews)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('stat-flagged')));
      await tester.pumpAndSettle();

      expect(find.textContaining('cit-3456'), findsOneWidget);
      expect(find.text('Looks correct'), findsNothing);
    });

    testWidgets('can restore all records via 全部 chip', (tester) async {
      await tester.pumpWidget(_buildTestApp(_loadedState(_sampleReviews)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('stat-rejected')));
      await tester.pumpAndSettle();
      expect(find.text('Looks correct'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('filter-all')));
      await tester.pumpAndSettle();
      expect(find.text('Looks correct'), findsOneWidget);
    });

    testWidgets('shows pending records as 未审核 in list', (tester) async {
      await tester.pumpWidget(_buildTestApp(_loadedState(_sampleReviews)));
      await tester.pumpAndSettle();

      expect(find.text('未审核'), findsOneWidget);
    });

    testWidgets('shows review text excerpt', (tester) async {
      await tester.pumpWidget(_buildTestApp(_loadedState(_sampleReviews)));
      await tester.pumpAndSettle();

      expect(find.text('Looks correct'), findsOneWidget);
      expect(find.text('Wrong source'), findsOneWidget);
    });

    testWidgets('shows refresh button', (tester) async {
      await tester.pumpWidget(_buildTestApp(_loadedState(_sampleReviews)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('shows citation ID snippet with tooltip', (tester) async {
      await tester.pumpWidget(_buildTestApp(_loadedState(_sampleReviews)));
      await tester.pumpAndSettle();

      expect(find.textContaining('cit-1234'), findsOneWidget);
    });
  });
}