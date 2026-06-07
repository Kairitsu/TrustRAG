import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dashboard sidebar / bottom-nav selected tab index.
/// 0 = Chat, 1 = Documents, 2 = Review, etc.
final dashboardTabProvider = StateProvider<int>((ref) => 0);