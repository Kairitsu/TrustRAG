import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import 'diagnostic_logger.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/dashboard/providers/workspace_provider.dart';
import 'backend_manager.dart';
import 'desktop_auto_setup.dart';
import 'local_data_path_guard.dart';
import 'mode_manager.dart' show ModeNotifier;
import 'session_reset.dart';

enum LocalBootstrapStatus {
  success,
  backendFailed,
  identityFailed,
  workspaceFailed,
}

class LocalBootstrapResult {
  final LocalBootstrapStatus status;
  final String message;
  final Workspace? workspace;

  const LocalBootstrapResult({
    required this.status,
    required this.message,
    this.workspace,
  });

  bool get isSuccess => status == LocalBootstrapStatus.success;
}

class LocalResetResult {
  final bool success;
  final String message;
  final List<String> deletedPaths;

  const LocalResetResult({
    required this.success,
    required this.message,
    this.deletedPaths = const [],
  });
}

/// Fixed embedded-backend account id for local mode (not shown in UI).
class LocalBootstrap {
  static const localAccountId = DesktopAutoSetup.defaultEmail;
  static const _setupDoneKey = 'desktop_setup_done';

  /// Full local-mode startup: backend → identity → default workspace.
  ///
  /// Pass [ref] from notifiers (e.g. [AuthNotifier]); pass [widgetRef] from
  /// [ConsumerState] widgets. Only one should be set.
  static Future<LocalBootstrapResult> bootstrap(
    ApiClient api, {
    Ref? ref,
    WidgetRef? widgetRef,
    bool forceBackendRestart = false,
  }) async {
    assert(
      ref == null || widgetRef == null,
      'Pass only ref or widgetRef, not both',
    );

    if (kIsWeb || !BackendManager.shouldRunEmbedded) {
      return const LocalBootstrapResult(
        status: LocalBootstrapStatus.backendFailed,
        message: '当前环境不支持本地模式',
      );
    }

    final bm = BackendManager();
    try {
      final dataDir = await bm.getAccountDataDir(localAccountId);
      final dbPath = p.join(dataDir, 'trustrag.db');
      final activeBefore = await ApiClient.getActiveAccount();
      final tokenBefore = await ApiClient.getToken();

      if (activeBefore != null &&
          activeBefore.isNotEmpty &&
          activeBefore != localAccountId) {
        await DiagnosticLogger.warn(
          'BOOTSTRAP clearing stale server active account=$activeBefore',
        );
        await ModeNotifier.clearServerRuntimePrefs();
      }

      await DiagnosticLogger.info(
        'BOOTSTRAP begin forceRestart=$forceBackendRestart '
        'dataDir=$dataDir db=$dbPath activeAccount=$activeBefore '
        'hasToken=${tokenBefore != null}',
      );

      if (forceBackendRestart) {
        await bm.restart(accountId: localAccountId);
      } else if (!bm.isRunning) {
        await bm.start(accountId: localAccountId);
      }
      await bm.ready;

      if (bm.hasFailed) {
        final msg = bm.startupError ?? '未知错误';
        await DiagnosticLogger.error('BOOTSTRAP backend failed: $msg');
        return LocalBootstrapResult(
          status: LocalBootstrapStatus.backendFailed,
          message: _formatError('本地服务启动失败', msg),
        );
      }

      api.dio.options.baseUrl = bm.baseUrl;
      await DiagnosticLogger.info('BOOTSTRAP backend ready baseUrl=${bm.baseUrl}');

      final identityOk = await DesktopAutoSetup.ensureLocalIdentity(api);
      if (!identityOk) {
        await DiagnosticLogger.error('BOOTSTRAP identity setup failed');
        return LocalBootstrapResult(
          status: LocalBootstrapStatus.identityFailed,
          message: _formatError(
            '本地身份初始化失败',
            DesktopAutoSetup.lastError ?? '无法创建或登录本地用户',
          ),
        );
      }

      final token = await ApiClient.getToken();
      if (token == null) {
        await DiagnosticLogger.error('BOOTSTRAP token missing after identity setup');
        return LocalBootstrapResult(
          status: LocalBootstrapStatus.identityFailed,
          message: _formatError('本地身份初始化失败', '未获得本地会话 Token'),
        );
      }

      try {
        final me = await api.dio.get('/auth/me');
        final user = me.data is Map<String, dynamic>
            ? me.data as Map<String, dynamic>
            : null;
        await DiagnosticLogger.info(
          'BOOTSTRAP local user verified id=${user?['id']} email=${user?['email']}',
        );
        if (ref != null) {
          ref
              .read(authProvider.notifier)
              .applyAuthenticatedSession(token: token, user: user);
        } else if (widgetRef != null) {
          widgetRef
              .read(authProvider.notifier)
              .applyAuthenticatedSession(token: token, user: user);
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          await ApiClient.clearToken();
        }
        final detail = _dioDetail(e);
        await DiagnosticLogger.error('BOOTSTRAP /auth/me failed: $detail');
        return LocalBootstrapResult(
          status: LocalBootstrapStatus.identityFailed,
          message: _formatError('本地身份验证失败', detail),
        );
      }

      final workspace = await _ensureDefaultWorkspace(api);
      if (workspace == null) {
        await DiagnosticLogger.error('BOOTSTRAP workspace setup failed');
        return const LocalBootstrapResult(
          status: LocalBootstrapStatus.workspaceFailed,
          message: '无法创建或加载本地工作区，请重试',
        );
      }

      await DiagnosticLogger.info('BOOTSTRAP workspace id=${workspace.id}');

      if (ref != null) {
        await _applyWorkspaceForRef(ref, workspace);
      } else if (widgetRef != null) {
        await _applyWorkspaceForWidgetRef(widgetRef, workspace);
      }

      return LocalBootstrapResult(
        status: LocalBootstrapStatus.success,
        message: '本地模式已就绪',
        workspace: workspace,
      );
    } catch (e, st) {
      await DiagnosticLogger.error('BOOTSTRAP failed: $e\n$st');
      debugPrint('[LocalBootstrap] failed: $e\n$st');
      return LocalBootstrapResult(
        status: LocalBootstrapStatus.backendFailed,
        message: _formatError('本地初始化失败', '$e'),
      );
    }
  }

  static String _formatError(String headline, String detail) {
    if (kDebugMode) return '$headline：$detail';
    return '$headline，请重试或清除本地数据后重新初始化';
  }

  static String _dioDetail(DioException e) {
    final code = e.response?.statusCode;
    final body = e.response?.data;
    if (code != null) {
      return 'HTTP $code ${body ?? e.message ?? ''}'.trim();
    }
    return e.message ?? e.type.name;
  }

  static Future<void> _applyWorkspaceForRef(Ref ref, Workspace workspace) async {
    final current = ref.read(selectedWorkspaceProvider);
    if (current != null && current.id == workspace.id) return;

    resetAccountScopedStateFromRef(ref);
    ref.read(selectedWorkspaceProvider.notifier).state = workspace;
    await saveLastWorkspaceId(workspace.id);
    ref.invalidate(workspaceProvider);
  }

  static Future<void> _applyWorkspaceForWidgetRef(
    WidgetRef widgetRef,
    Workspace workspace,
  ) async {
    final current = widgetRef.read(selectedWorkspaceProvider);
    if (current != null && current.id == workspace.id) return;

    resetAccountScopedState(widgetRef);
    widgetRef.read(selectedWorkspaceProvider.notifier).state = workspace;
    await saveLastWorkspaceId(workspace.id);
    widgetRef.invalidate(workspaceProvider);
  }

  static Future<Workspace?> _ensureDefaultWorkspace(ApiClient api) async {
    try {
      final resp = await api.dio.get('/workspaces');
      final list = (resp.data as List)
          .map((j) => Workspace.fromJson(j as Map<String, dynamic>))
          .toList();
      if (list.isNotEmpty) {
        return _pickWorkspace(list);
      }

      final created = await api.dio.post('/workspaces', data: {
        'name': '个人空间',
        'description': null,
        'type': 'personal',
      });
      return Workspace.fromJson(created.data as Map<String, dynamic>);
    } on DioException catch (e) {
      debugPrint('[LocalBootstrap] workspace error: ${e.message}');
      return null;
    }
  }

  static Future<Workspace> _pickWorkspace(List<Workspace> list) async {
    final prefs = await SharedPreferences.getInstance();
    final localKey = 'last_workspace_id_$localAccountId';
    final savedId = prefs.getString(localKey);
    if (savedId != null) {
      for (final w in list) {
        if (w.id == savedId) return w;
      }
    }
    return list.first;
  }

  /// Clears local setup flags and embedded data for the default local account.
  static Future<LocalResetResult> resetLocalData() async {
    await DiagnosticLogger.info('RESET local data started');
    final deletedPaths = <String>[];

    try {
      if (!BackendManager.shouldRunEmbedded) {
        return const LocalResetResult(
          success: false,
          message: '当前环境不支持删除本机资料库',
        );
      }

      final bm = BackendManager();
      final dataDir = await bm.getAccountDataDir(localAccountId);
      await DiagnosticLogger.info('RESET target data_dir=$dataDir');

      if (!LocalDataPathGuard.isSafeToDelete(dataDir)) {
        final msg = '拒绝删除：路径不安全 ($dataDir)';
        await DiagnosticLogger.error('RESET $msg');
        return LocalResetResult(success: false, message: msg);
      }

      await DiagnosticLogger.info('RESET stopping backend before delete');
      await bm.stop();

      final deleteResult = await bm.deleteDataDirectory(dataDir);
      if (!deleteResult.success) {
        await DiagnosticLogger.error('RESET delete failed: ${deleteResult.message}');
        return LocalResetResult(
          success: false,
          message: deleteResult.message,
          deletedPaths: deletedPaths,
        );
      }
      if (deleteResult.message.contains('已删除')) {
        deletedPaths.add(dataDir);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_setupDoneKey);
      await prefs.remove('last_workspace_id');
      await prefs.remove('last_workspace_id_$localAccountId');
      await ApiClient.clearToken();
      await prefs.remove('active_account_email');
      await prefs.remove('auth_token_$localAccountId');
      bm.resetLifecycle();

      await DiagnosticLogger.info('RESET local data completed');
      return LocalResetResult(
        success: true,
        message: '本机资料库已删除',
        deletedPaths: deletedPaths,
      );
    } catch (e, st) {
      await DiagnosticLogger.error('RESET failed: $e\n$st');
      debugPrint('[LocalBootstrap] resetLocalData: $e\n$st');
      return LocalResetResult(
        success: false,
        message: BackendManager().hasFailed
            ? '删除失败：$e'
            : '删除本机资料库失败：$e',
        deletedPaths: deletedPaths,
      );
    }
  }

  /// Visible for tests — only TrustRAG per-account dirs may be deleted.
  static bool isDataDirSafeToDelete(String dirPath) =>
      LocalDataPathGuard.isSafeToDelete(dirPath);
}