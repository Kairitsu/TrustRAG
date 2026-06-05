import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/pages/login_page.dart';
import '../../features/auth/pages/register_page.dart';
import '../../features/dashboard/pages/dashboard_page.dart';
import '../../features/local/pages/local_startup_page.dart';
import '../../features/onboarding/pages/onboarding_page.dart';
import '../api/api_client.dart';
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
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) =>
          _fadeTransition(state, const _RootRedirector()),
    ),
    GoRoute(
      path: '/onboarding',
      pageBuilder: (context, state) =>
          _fadeTransition(state, const OnboardingPage()),
    ),
    GoRoute(
      path: '/local-startup',
      pageBuilder: (context, state) =>
          _fadeTransition(state, const LocalStartupPage()),
    ),
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) =>
          _fadeTransition(state, LoginPage(prefillEmail: state.uri.queryParameters['email'])),
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

/// Reads the persisted app_mode and redirects accordingly.
class _RootRedirector extends StatefulWidget {
  const _RootRedirector();

  @override
  State<_RootRedirector> createState() => _RootRedirectorState();
}

class _RootRedirectorState extends State<_RootRedirector> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    await ApiClient.purgeInternalLocalFromSavedAccounts();
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('app_mode');

    if (!mounted) return;

    if (mode == 'local') {
      context.go('/local-startup');
    } else if (mode == 'server') {
      final token = await ApiClient.getToken();
      if (!mounted) return;
      if (token != null && token.isNotEmpty) {
        context.go('/dashboard');
      } else {
        context.go('/login');
      }
    } else {
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}