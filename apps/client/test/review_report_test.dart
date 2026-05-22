import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/features/chat/providers/review_provider.dart';

void main() {
  group('ReviewReportData model', () {
    test('fromJson parses complete data', () {
      final json = {
        'generated_at': '2026-05-22 06:00:00 UTC',
        'stats': {
          'total_citations': 20,
          'approved': 12,
          'rejected': 3,
          'flagged': 2,
          'pending': 1,
          'unreviewed': 2,
        },
        'approval_rate': 66.67,
        'rejection_rate': 16.67,
        'hallucination_rate': 27.78,
        'review_coverage': 90.0,
        'recent_reviews': [
          {
            'id': 'r1',
            'citation_id': 'c1',
            'status': 'approved',
            'comment': 'Good',
            'corrected_text': null,
            'quoted_text': 'Some text',
            'document_title': 'Doc 1',
            'heading_path': 'Ch1 > Intro',
            'page_number': 5,
            'created_at': '2026-05-22 05:30:00',
          }
        ],
      };

      final report = ReviewReportData.fromJson(json);

      expect(report.generatedAt, '2026-05-22 06:00:00 UTC');
      expect(report.stats.totalCitations, 20);
      expect(report.stats.approved, 12);
      expect(report.stats.rejected, 3);
      expect(report.stats.flagged, 2);
      expect(report.stats.pending, 1);
      expect(report.stats.unreviewed, 2);
      expect(report.approvalRate, 66.67);
      expect(report.rejectionRate, 16.67);
      expect(report.hallucinationRate, 27.78);
      expect(report.reviewCoverage, 90.0);
      expect(report.recentReviews.length, 1);
      expect(report.recentReviews[0].status, 'approved');
      expect(report.recentReviews[0].documentTitle, 'Doc 1');
      expect(report.recentReviews[0].headingPath, 'Ch1 > Intro');
      expect(report.recentReviews[0].pageNumber, 5);
      expect(report.recentReviews[0].quotedText, 'Some text');
    });

    test('fromJson handles empty data', () {
      final json = <String, dynamic>{
        'stats': <String, dynamic>{},
        'recent_reviews': <dynamic>[],
      };

      final report = ReviewReportData.fromJson(json);

      expect(report.generatedAt, '');
      expect(report.stats.totalCitations, 0);
      expect(report.stats.approved, 0);
      expect(report.approvalRate, 0.0);
      expect(report.recentReviews, isEmpty);
    });

    test('fromJson handles missing fields', () {
      final json = <String, dynamic>{};

      final report = ReviewReportData.fromJson(json);

      expect(report.stats.totalCitations, 0);
      expect(report.approvalRate, 0.0);
      expect(report.recentReviews, isEmpty);
    });
  });

  group('ReviewRecordWithContext model', () {
    test('fromJson parses all fields', () {
      final json = {
        'id': 'r1',
        'citation_id': 'c1',
        'status': 'rejected',
        'comment': 'Wrong source',
        'corrected_text': 'Correct text here',
        'quoted_text': 'Original quote',
        'document_title': 'My Document',
        'heading_path': 'Section > Subsection',
        'page_number': 10,
        'created_at': '2026-05-22',
      };

      final record = ReviewRecordWithContext.fromJson(json);

      expect(record.id, 'r1');
      expect(record.citationId, 'c1');
      expect(record.status, 'rejected');
      expect(record.comment, 'Wrong source');
      expect(record.correctedText, 'Correct text here');
      expect(record.quotedText, 'Original quote');
      expect(record.documentTitle, 'My Document');
      expect(record.headingPath, 'Section > Subsection');
      expect(record.pageNumber, 10);
      expect(record.createdAt, '2026-05-22');
    });

    test('fromJson handles null optional fields', () {
      final json = {
        'id': 'r2',
        'citation_id': 'c2',
        'status': 'approved',
        'created_at': '2026-05-22',
      };

      final record = ReviewRecordWithContext.fromJson(json);

      expect(record.comment, isNull);
      expect(record.correctedText, isNull);
      expect(record.quotedText, isNull);
      expect(record.documentTitle, isNull);
      expect(record.headingPath, isNull);
      expect(record.pageNumber, isNull);
    });
  });

  group('Report i18n keys', () {
    testWidgets('Chinese locale has all report keys', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Builder(builder: (context) {
            final s = S.of(context);
            expect(s.exportReport, '导出报告');
            expect(s.reviewReport, '审核报告');
            expect(s.totalCitations, '总引用数');
            expect(s.reviewCoverage, '审核覆盖率');
            expect(s.hallucinationRate, '幻觉率');
            expect(s.approvalRate, '通过率');
            expect(s.rejectionRate, '拒绝率');
            expect(s.approved, '通过');
            expect(s.rejected, '拒绝');
            expect(s.flagged, '存疑');
            expect(s.pending, '待定');
            expect(s.copyMarkdown, '复制 Markdown');
            expect(s.copiedToClipboard, '已复制到剪贴板');
            expect(s.noReviewRecords, '暂无审核记录');
            return const SizedBox.shrink();
          }),
        ),
      );
    });

    testWidgets('English locale has all report keys', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Builder(builder: (context) {
            final s = S.of(context);
            expect(s.exportReport, 'Export Report');
            expect(s.reviewReport, 'Review Report');
            expect(s.hallucinationRate, 'Hallucination Rate');
            expect(s.copyMarkdown, 'Copy Markdown');
            expect(s.noReviewRecords, 'No review records');
            return const SizedBox.shrink();
          }),
        ),
      );
    });

    testWidgets('Japanese locale has all report keys', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Builder(builder: (context) {
            final s = S.of(context);
            expect(s.exportReport, 'レポート出力');
            expect(s.reviewReport, 'レビューレポート');
            expect(s.hallucinationRate, 'ハルシネーション率');
            expect(s.noReviewRecords, 'レビュー記録なし');
            return const SizedBox.shrink();
          }),
        ),
      );
    });

    testWidgets('Parameterized reportGeneratedAt works', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Builder(builder: (context) {
            final s = S.of(context);
            expect(s.reportGeneratedAt('2026-05-22'), '生成时间: 2026-05-22');
            return const SizedBox.shrink();
          }),
        ),
      );
    });
  });

  group('ReviewStats model', () {
    test('fromJson handles all fields', () {
      final json = {
        'total_citations': 100,
        'approved': 60,
        'rejected': 15,
        'flagged': 10,
        'pending': 5,
        'unreviewed': 10,
      };
      final stats = ReviewStats.fromJson(json);
      expect(stats.totalCitations, 100);
      expect(stats.approved, 60);
      expect(stats.rejected, 15);
      expect(stats.flagged, 10);
      expect(stats.pending, 5);
      expect(stats.unreviewed, 10);
    });

    test('fromJson defaults to 0', () {
      final stats = ReviewStats.fromJson({});
      expect(stats.totalCitations, 0);
      expect(stats.approved, 0);
    });
  });
}
