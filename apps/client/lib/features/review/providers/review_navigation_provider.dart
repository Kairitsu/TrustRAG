import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReviewNavigationTarget {
  final String? conversationId;
  final String? messageId;
  final String? citationId;
  final String? auditRecordId;

  const ReviewNavigationTarget({
    this.conversationId,
    this.messageId,
    this.citationId,
    this.auditRecordId,
  });

  bool get hasMinimumTarget =>
      conversationId != null &&
      conversationId!.isNotEmpty &&
      messageId != null &&
      messageId!.isNotEmpty;
}

final reviewNavigationTargetProvider =
    StateProvider<ReviewNavigationTarget?>((ref) => null);