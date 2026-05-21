import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/features/review/pages/review_list_page.dart';
import 'package:client/features/chat/providers/review_provider.dart';

Widget _buildTestApp(List<ReviewRecord> reviews) {
  return ProviderScope(
    overrides: [
      reviewListProvider.overrideWith((ref) => Future.value(reviews)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: ReviewListPage()),
    ),
  );
}

final _sampleReviews = [
  ReviewRecord(
    id: 'r1',
    citationId: 'cit-1234-5678',
    reviewerId: 'user-1',
    status: 'approved',
    comment: 'Looks correct',
    createdAt: '2026-05-21T10:00:00Z',
  ),
  ReviewRecord(
    id: 'r2',
    citationId: 'cit-2345-6789',
    reviewerId: 'user-1',
    status: 'rejected',
    comment: 'Wrong source',
    correctedText: 'Fixed citation',
    createdAt: '2026-05-21T11:00:00Z',
  ),
  ReviewRecord(
    id: 'r3',
    citationId: 'cit-3456-7890',
    reviewerId: 'user-1',
    status: 'flagged',
    createdAt: '2026-05-21T12:00:00Z',
  ),
];

void main() {
  group('ReviewListPage', () {
    testWidgets('shows empty state when no reviews', (tester) async {
      await tester.pumpWidget(_buildTestApp([]));
      await tester.pumpAndSettle();

      expect(find.text('暂无审核记录'), findsOneWidget);
      expect(find.text('在对话中审核 AI 引用后，记录将在此处显示'), findsOneWidget);
    });

    testWidgets('shows review list with stat cards', (tester) async {
      await tester.pumpWidget(_buildTestApp(_sampleReviews));
      await tester.pumpAndSettle();

      expect(find.text('审核记录'), findsOneWidget);

      expect(find.text('通过'), findsWidgets);
      expect(find.text('拒绝'), findsWidgets);
      expect(find.text('存疑'), findsWidgets);
      expect(find.text('待定'), findsOneWidget);
    });

    testWidgets('shows review comments', (tester) async {
      await tester.pumpWidget(_buildTestApp(_sampleReviews));
      await tester.pumpAndSettle();

      expect(find.text('Looks correct'), findsOneWidget);
      expect(find.text('Wrong source'), findsOneWidget);
    });

    testWidgets('shows corrected text', (tester) async {
      await tester.pumpWidget(_buildTestApp(_sampleReviews));
      await tester.pumpAndSettle();

      expect(find.textContaining('Fixed citation'), findsOneWidget);
    });

    testWidgets('shows refresh button', (tester) async {
      await tester.pumpWidget(_buildTestApp(_sampleReviews));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('shows citation ID snippet', (tester) async {
      await tester.pumpWidget(_buildTestApp(_sampleReviews));
      await tester.pumpAndSettle();

      expect(find.textContaining('cit-1234'), findsOneWidget);
    });
  });
}
