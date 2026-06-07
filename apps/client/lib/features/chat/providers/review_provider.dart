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

class ReviewCounts {
  final int approved;
  final int rejected;
  final int suspicious;
  final int pending;

  const ReviewCounts({
    this.approved = 0,
    this.rejected = 0,
    this.suspicious = 0,
    this.pending = 0,
  });

  factory ReviewCounts.fromJson(Map<String, dynamic> json) {
    return ReviewCounts(
      approved: json['approved'] ?? 0,
      rejected: json['rejected'] ?? 0,
      suspicious: json['suspicious'] ?? 0,
      pending: json['pending'] ?? 0,
    );
  }
}

class ReviewRecordEnriched {
  final String id;
  final String status;
  final String? textExcerpt;
  final String citationId;
  final String citationShortId;
  final String? conversationId;
  final String? messageId;
  final String? documentId;
  final String? chunkId;
  final String? documentTitle;
  final String? conversationTitle;
  final String? comment;
  final String? correctedText;
  final String createdAt;
  final String updatedAt;
  final bool targetAvailable;

  ReviewRecordEnriched({
    required this.id,
    required this.status,
    this.textExcerpt,
    required this.citationId,
    required this.citationShortId,
    this.conversationId,
    this.messageId,
    this.documentId,
    this.chunkId,
    this.documentTitle,
    this.conversationTitle,
    this.comment,
    this.correctedText,
    required this.createdAt,
    required this.updatedAt,
    required this.targetAvailable,
  });

  factory ReviewRecordEnriched.fromJson(Map<String, dynamic> json) {
    return ReviewRecordEnriched(
      id: json['id'] ?? '',
      status: json['status'] ?? 'pending',
      textExcerpt: json['text_excerpt'],
      citationId: json['citation_id'] ?? '',
      citationShortId: json['citation_short_id'] ?? '',
      conversationId: json['conversation_id'],
      messageId: json['message_id'],
      documentId: json['document_id'],
      chunkId: json['chunk_id'],
      documentTitle: json['document_title'],
      conversationTitle: json['conversation_title'],
      comment: json['comment'],
      correctedText: json['corrected_text'],
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      targetAvailable: json['target_available'] ?? false,
    );
  }
}

class ReviewListResponse {
  final List<ReviewRecordEnriched> records;
  final ReviewCounts counts;

  ReviewListResponse({
    required this.records,
    required this.counts,
  });

  factory ReviewListResponse.fromJson(Map<String, dynamic> json) {
    return ReviewListResponse(
      records: (json['records'] as List? ?? [])
          .map((e) => ReviewRecordEnriched.fromJson(e as Map<String, dynamic>))
          .toList(),
      counts: ReviewCounts.fromJson(json['counts'] ?? {}),
    );
  }
}

class ReviewTarget {
  final String? auditRecordId;
  final String? conversationId;
  final String? messageId;
  final String? citationId;
  final String? documentId;
  final String? chunkId;
  final bool targetAvailable;

  ReviewTarget({
    this.auditRecordId,
    this.conversationId,
    this.messageId,
    this.citationId,
    this.documentId,
    this.chunkId,
    required this.targetAvailable,
  });

  factory ReviewTarget.fromJson(Map<String, dynamic> json) {
    return ReviewTarget(
      auditRecordId: json['audit_record_id'],
      conversationId: json['conversation_id'],
      messageId: json['message_id'],
      citationId: json['citation_id'],
      documentId: json['document_id'],
      chunkId: json['chunk_id'],
      targetAvailable: json['target_available'] ?? false,
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

  Future<ReviewListResponse> listAllReviewsEnriched({
    int limit = 50,
    int offset = 0,
  }) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get(
      '/reviews',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return ReviewListResponse.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<ReviewTarget> getReviewTarget(String reviewId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get('/reviews/$reviewId/target');
    return ReviewTarget.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<ReviewTarget> getReviewTargetByCitation(String citationId) async {
    final api = ref.read(apiClientProvider);
    final resp = await api.dio.get(
      '/reviews/target',
      queryParameters: {'citation_id': citationId},
    );
    return ReviewTarget.fromJson(resp.data as Map<String, dynamic>);
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
