import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/local_bootstrap.dart';
import '../../../core/services/mode_manager.dart';
import '../../../core/services/mode_switch_coordinator.dart';
import '../../../core/services/session_reset.dart';
import '../../auth/providers/auth_provider.dart';

/// Boots embedded backend and local library; never shown as a login screen.
class LocalStartupPage extends ConsumerStatefulWidget {
  const LocalStartupPage({super.key});

  @override
  ConsumerState<LocalStartupPage> createState() => _LocalStartupPageState();
}

class _LocalStartupPageState extends ConsumerState<LocalStartupPage> {
  bool _inProgress = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runBootstrap());
  }

  Future<void> _runBootstrap({bool isRetry = false}) async {
    if (_inProgress || ModeSwitchCoordinator.isSwitchInProgress) return;

    setState(() {
      _inProgress = true;
      _error = null;
    });

    try {
      if (isRetry) {
        await ModeSwitchCoordinator.resetPartialLocalState();
        resetAccountScopedState(ref);
        ref.read(authProvider.notifier).clearSessionState();
        ref.invalidate(authProvider);
      }

      final mode = ref.read(modeProvider).mode;
      final LocalBootstrapResult result;

      if (mode == AppMode.server) {
        result = await ModeSwitchCoordinator.migrateServerToLocal(
          widgetRef: ref,
          fromRetry: isRetry,
        );
      } else {
        final api = ref.read(apiClientProvider);
        result = await LocalBootstrap.bootstrap(
          api,
          widgetRef: ref,
          forceBackendRestart: isRetry,
        );
      }

      if (!mounted) return;

      if (result.isSuccess) {
        resetAccountScopedState(ref);
        ref.invalidate(authProvider);
        context.go('/dashboard');
        return;
      }

      setState(() => _error = result.message);
    } catch (e, st) {
      if (mounted) {
        setState(() => _error = kDebugMode
            ? '本地初始化失败：$e\n$st'
            : '本地初始化失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _inProgress = false);
    }
  }

  Future<void> _backToOnboarding() async {
    if (_inProgress) return;

    setState(() => _inProgress = true);
    try {
      await ModeSwitchCoordinator.resetPartialLocalState();
      resetAccountScopedState(ref);
      ref.read(authProvider.notifier).clearSessionState();
      await ref.read(modeProvider.notifier).resetMode();
      ref.invalidate(apiClientProvider);
      ref.invalidate(authProvider);
      if (mounted) context.go('/onboarding');
    } finally {
      if (mounted) setState(() => _inProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.computer_rounded,
                  size: 64,
                  color: Colors.green.shade600,
                ),
                const SizedBox(height: 16),
                Text(
                  'TrustRAG',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '正在准备本地工作台…',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_inProgress) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('正在启动本地服务并初始化…'),
                ],
                if (_error != null && !_inProgress) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '本地模式初始化失败',
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _inProgress ? null : () => _runBootstrap(isRetry: true),
                    child: const Text('重试'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _inProgress ? null : _backToOnboarding,
                    child: const Text('返回选择使用方式'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}