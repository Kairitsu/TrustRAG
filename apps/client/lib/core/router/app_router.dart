import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/pages/login_page.dart';
import '../../features/auth/pages/register_page.dart';
import '../../features/dashboard/pages/dashboard_page.dart';
import '../../main.dart' show rootNavigatorKey;

CustomTransitionPage<void> _fadeTransition(
    GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) =>
          _fadeTransition(state, const LoginPage()),
    ),
    GoRoute(
      path: '/register',
      pageBuilder: (context, state) =>
          _fadeTransition(state, const RegisterPage()),
    ),
    GoRoute(
      path: '/dashboard',
      pageBuilder: (context, state) =>
          _fadeTransition(state, const DashboardPage()),
    ),
  ],
);
