import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/providers/review_provider.dart';

/// Internal filter values — display labels are handled in the UI layer.
enum ReviewFilterStatus {
  all,
  approved,
  rejected,
  suspicious,
}

extension ReviewFilterStatusX on ReviewFilterStatus {
  /// Maps to backend `review_records.status` values.
  String? get backendStatus => switch (this) {
        ReviewFilterStatus.all => null,
        ReviewFilterStatus.approved => 'approved',
        ReviewFilterStatus.rejected => 'rejected',
        ReviewFilterStatus.suspicious => 'flagged',
      };

  bool matchesRecord(ReviewRecordEnriched record) {
    if (this == ReviewFilterStatus.all) return true;
    return record.status == backendStatus;
  }
}

class ReviewListState {
  final List<ReviewRecordEnriched> records;
  final ReviewCounts counts;
  final ReviewFilterStatus selectedStatus;
  final bool loading;
  final String? error;

  const ReviewListState({
    this.records = const [],
    this.counts = const ReviewCounts(),
    this.selectedStatus = ReviewFilterStatus.all,
    this.loading = false,
    this.error,
  });

  List<ReviewRecordEnriched> get filteredRecords =>
      records.where((r) => selectedStatus.matchesRecord(r)).toList();

  ReviewListState copyWith({
    List<ReviewRecordEnriched>? records,
    ReviewCounts? counts,
    ReviewFilterStatus? selectedStatus,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return ReviewListState(
      records: records ?? this.records,
      counts: counts ?? this.counts,
      selectedStatus: selectedStatus ?? this.selectedStatus,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ReviewListNotifier extends StateNotifier<ReviewListState> {
  final Ref ref;

  ReviewListNotifier(this.ref) : super(const ReviewListState());

  Future<void> load({int limit = 100}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final service = ref.read(reviewServiceProvider);
      final response = await service.listAllReviewsEnriched(limit: limit);
      state = state.copyWith(
        records: response.records,
        counts: response.counts,
        loading: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void setFilter(ReviewFilterStatus status) {
    if (state.selectedStatus == status && status != ReviewFilterStatus.all) {
      state = state.copyWith(selectedStatus: ReviewFilterStatus.all);
      return;
    }
    state = state.copyWith(selectedStatus: status);
  }
}

final reviewListNotifierProvider =
    StateNotifierProvider<ReviewListNotifier, ReviewListState>((ref) {
  final notifier = ReviewListNotifier(ref);
  notifier.load();
  return notifier;
});