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
}
