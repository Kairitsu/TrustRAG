import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';

class ReviewRecord {
  final String id;
  final String citationId;
  final String reviewerId;
  final String status;
  final String? comment;
  final String? correctedText;
  final String createdAt;

  ReviewRecord({
    required this.id,
    required this.citationId,
    required this.reviewerId,
    required this.status,
    this.comment,
    this.correctedText,
    required this.createdAt,
  });

  factory ReviewRecord.fromJson(Map<String, dynamic> json) {
    return ReviewRecord(
      id: json['id'] ?? '',
      citationId: json['citation_id'] ?? '',
      reviewerId: json['reviewer_id'] ?? '',
      status: json['status'] ?? 'pending',
      comment: json['comment'],
      correctedText: json['corrected_text'],
      createdAt: json['created_at'] ?? '',
    );
  }
}

class ReviewReportData {
  final String generatedAt;
  final ReviewStats stats;
  final double approvalRate;
  final double rejectionRate;
  final double hallucinationRate;
  final double reviewCoverage;
  final List<ReviewRecordWithContext> recentReviews;

  ReviewReportData({
    required this.generatedAt,
    required this.stats,
    required this.approvalRate,
    required this.rejectionRate,
    required this.hallucinationRate,
    required this.reviewCoverage,
    required this.recentReviews,
  });

  factory ReviewReportData.fromJson(Map<String, dynamic> json) {
    return ReviewReportData(
      generatedAt: json['generated_at'] ?? '',
      stats: ReviewStats.fromJson(json['stats'] ?? {}),
      approvalRate: (json['approval_rate'] ?? 0).toDouble(),
      rejectionRate: (json['rejection_rate'] ?? 0).toDouble(),
      hallucinationRate: (json['hallucination_rate'] ?? 0).toDouble(),
      reviewCoverage: (json['review_coverage'] ?? 0).toDouble(),
      recentReviews: (json['recent_reviews'] as List? ?? [])
          .map((e) => ReviewRecordWithContext.fromJson(e))
          .toList(),
    );
  }
}

class ReviewRecordWithContext {
  final String id;
  final String citationId;
  final String status;
  final String? comment;
  final String? correctedText;
  final String? quotedText;
  final String? documentTitle;
  final String? headingPath;
  final int? pageNumber;
  final String createdAt;

  ReviewRecordWithContext({
    required this.id,
    required this.citationId,
    required this.status,
    this.comment,
    this.correctedText,
    this.quotedText,
    this.documentTitle,
    this.headingPath,
    this.pageNumber,
    required this.createdAt,
  });

  factory ReviewRecordWithContext.fromJson(Map<String, dynamic> json) {
    return ReviewRecordWithContext(
      id: json['id'] ?? '',
      citationId: json['citation_id'] ?? '',
      status: json['status'] ?? 'pending',
      comment: json['comment'],
      correctedText: json['corrected_text'],
      quotedText: json['quoted_text'],
      documentTitle: json['document_title'],
      headingPath: json['heading_path'],
      pageNumber: json['page_number'],
      createdAt: json['created_at'] ?? '',
    );
  }
}

class ReviewStats {
  final int totalCitations;
  final int approved;
  final int rejected;
  final int flagged;
  final int pending;
  final int unreviewed;

  ReviewStats({
    required this.totalCitations,
    required this.approved,
    required this.rejected,
    required this.flagged,
    required this.pending,
    required this.unreviewed,
  });

  factory ReviewStats.fromJson(Map<String, dynamic> json) {
    return ReviewStats(
      totalCitations: json['total_citations'] ?? 0,
      approved: json['approved'] ?? 0,
      rejected: json['rejected'] ?? 0,
      flagged: json['flagged'] ?? 0,
      pending: json['pending'] ?? 0,
      unreviewed: json['unreviewed'] ?? 0,
    );
  }
}

final reviewServiceProvider = Provider<ReviewService>((ref) {
  return ReviewService(ref);
});

class ReviewService {
  final Ref ref;
  ReviewService(this.ref);

  Future<ReviewRecord> createReview(
    String citationId, {
    required String status,
    String? comment,
    String? correctedText,
  }) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.post(
      '/citations/$citationId/reviews',
      data: {
        'status': status,
        if (comment != null) 'comment': comment,
        if (correctedText != null) 'corrected_text': correctedText,
      },
    );
    return ReviewRecord.fromJson(resp.data);
  }

  Future<List<ReviewRecord>> listReviews(String citationId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get('/citations/$citationId/reviews');
    return (resp.data as List).map((e) => ReviewRecord.fromJson(e)).toList();
  }

  Future<ReviewStats> getConversationStats(String conversationId) async {
    final api = ref.read(apiClientProvider);
    final resp =
        await api.dio.get('/conversations/$conversationId/review-stats');
    return ReviewStats.fromJson(resp.data);
  }

  Future<List<ReviewRecord>> listAllReviews({
    int limit = 50,
    int offset = 0,
  }) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get(
      '/reviews',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return (resp.data as List).map((e) => ReviewRecord.fromJson(e)).toList();
  }

  Future<ReviewReportData> getReport() async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get('/reviews/report');
    return ReviewReportData.fromJson(resp.data);
  }

  Future<String> getReportMarkdown() async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get('/reviews/report/markdown');
    return resp.data as String;
  }
}
