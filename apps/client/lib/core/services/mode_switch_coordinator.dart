import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../../features/auth/providers/auth_provider.dart';
import 'backend_manager.dart';
import 'diagnostic_logger.dart';
import 'local_bootstrap.dart';
import 'mode_manager.dart';
import 'session_reset.dart';

/// Atomic server → local mode migration (runtime state machine).
class ModeSwitchCoordinator {
  ModeSwitchCoordinator._();

  static bool _switchInProgress = false;

  static bool get isSwitchInProgress => _switchInProgress;

  /// Clears in-flight server context without deleting saved server account tokens.
  static Future<void> clearServerRuntimeContext({
    required WidgetRef? widgetRef,
    Ref? ref,
    ApiClient? api,
  }) async {
    assert(ref == null || widgetRef == null);

    if (widgetRef != null) {
      api?.cancelAllRequests('mode switch to local');
      resetAccountScopedState(widgetRef);
      widgetRef.read(authProvider.notifier).clearSessionState();
    } else if (ref != null) {
      api?.cancelAllRequests('mode switch to local');
      resetAccountScopedStateFromRef(ref);
      ref.read(authProvider.notifier).clearSessionState();
    }

    await ApiClient.clearActiveServerSession();
    await ModeNotifier.clearServerRuntimePrefs();
    await DiagnosticLogger.info('MIGRATION cleared server runtime session');
  }

  /// Stops backend and clears half-initialized local state (retry / back).
  static Future<void> resetPartialLocalState() async {
    await DiagnosticLogger.info('MIGRATION reset partial local state');
    await ApiClient.clearToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_account_email');
    await BackendManager().stop();
    BackendManager().resetLifecycle();
  }

  static Future<LocalBootstrapResult> migrateServerToLocal({
    required WidgetRef widgetRef,
    bool fromRetry = false,
  }) async {
    if (_switchInProgress) {
      return const LocalBootstrapResult(
        status: LocalBootstrapStatus.backendFailed,
        message: '模式切换正在进行中，请稍候',
      );
    }

    _switchInProgress = true;
    try {
      final modeBefore = widgetRef.read(modeProvider).mode;
      final activeBefore = await ApiClient.getActiveAccount();
      final prefs = await SharedPreferences.getInstance();
      final wsBefore = prefs.getString('last_workspace_id') ??
          (activeBefore != null
              ? prefs.getString('last_workspace_id_$activeBefore')
              : null);

      await DiagnosticLogger.info(
        'MIGRATION server→local begin mode=$modeBefore '
        'user=$activeBefore workspace=$wsBefore retry=$fromRetry',
      );

      final api = widgetRef.read(apiClientProvider);
      await clearServerRuntimeContext(widgetRef: widgetRef, api: api);

      await widgetRef.read(modeProvider.notifier).setLocalMode();
      widgetRef.invalidate(apiClientProvider);
      widgetRef.invalidate(authProvider);

      final freshApi = widgetRef.read(apiClientProvider);
      final result = await LocalBootstrap.bootstrap(
        freshApi,
        widgetRef: widgetRef,
        forceBackendRestart: true,
      );

      await DiagnosticLogger.info(
        'MIGRATION server→local end status=${result.status} '
        'success=${result.isSuccess}',
      );
      return result;
    } catch (e, st) {
      await DiagnosticLogger.error('MIGRATION server→local failed: $e\n$st');
      if (kDebugMode) {
        return LocalBootstrapResult(
          status: LocalBootstrapStatus.backendFailed,
          message: '模式切换失败：$e',
        );
      }
      return LocalBootstrapResult(
        status: LocalBootstrapStatus.backendFailed,
        message: '模式切换失败，请重试',
      );
    } finally {
      _switchInProgress = false;
    }
  }
}