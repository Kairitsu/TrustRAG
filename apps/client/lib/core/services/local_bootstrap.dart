import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/dashboard/providers/workspace_provider.dart';
import 'backend_manager.dart';
import 'desktop_auto_setup.dart';
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

/// Fixed embedded-backend account id for local mode (not shown in UI).
class LocalBootstrap {
  static const localAccountId = DesktopAutoSetup.defaultEmail;
  static const _setupDoneKey = 'desktop_setup_done';

  /// Full local-mode startup: backend → identity → default workspace.
  static Future<LocalBootstrapResult> bootstrap(
    ApiClient api, {
    Ref? ref,
  }) async {
    if (kIsWeb || !BackendManager.shouldRunEmbedded) {
      return const LocalBootstrapResult(
        status: LocalBootstrapStatus.backendFailed,
        message: '当前环境不支持本地模式',
      );
    }

    final bm = BackendManager();
    try {
      if (!bm.isRunning) {
        await bm.start(accountId: localAccountId);
        await bm.ready;
      }
      if (bm.hasFailed) {
        return LocalBootstrapResult(
          status: LocalBootstrapStatus.backendFailed,
          message: '本地服务启动失败：${bm.startupError ?? "未知错误"}',
        );
      }
      api.dio.options.baseUrl = bm.baseUrl;

      await DesktopAutoSetup.ensureLocalIdentity(api);

      final token = await ApiClient.getToken();
      if (token == null) {
        return const LocalBootstrapResult(
          status: LocalBootstrapStatus.identityFailed,
          message: '本地身份初始化失败，请重试或清除本地数据后重新初始化',
        );
      }

      try {
        final me = await api.dio.get('/auth/me');
        if (ref != null) {
          ref.read(authProvider.notifier).state = AuthState(
            status: AuthStatus.authenticated,
            token: token,
            user: me.data is Map<String, dynamic>
                ? me.data as Map<String, dynamic>
                : null,
          );
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          await ApiClient.clearToken();
        }
        return const LocalBootstrapResult(
          status: LocalBootstrapStatus.identityFailed,
          message: '本地身份验证失败，请重试',
        );
      }

      final workspace = await _ensureDefaultWorkspace(api);
      if (workspace == null) {
        return const LocalBootstrapResult(
          status: LocalBootstrapStatus.workspaceFailed,
          message: '无法创建或加载工作区，请重试',
        );
      }

      if (ref != null) {
        final current = ref.read(selectedWorkspaceProvider);
        if (current == null || current.id != workspace.id) {
          resetAccountScopedStateFromRef(ref);
          ref.read(selectedWorkspaceProvider.notifier).state = workspace;
          await saveLastWorkspaceId(workspace.id);
          ref.invalidate(workspaceProvider);
        }
      }

      return LocalBootstrapResult(
        status: LocalBootstrapStatus.success,
        message: '本地模式已就绪',
        workspace: workspace,
      );
    } catch (e, st) {
      debugPrint('[LocalBootstrap] failed: $e\n$st');
      return LocalBootstrapResult(
        status: LocalBootstrapStatus.backendFailed,
        message: '本地初始化失败：$e',
      );
    }
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
    final activeAccount = await ApiClient.getActiveAccount();
    final key = activeAccount != null && activeAccount.isNotEmpty
        ? 'last_workspace_id_$activeAccount'
        : 'last_workspace_id';
    final savedId = prefs.getString(key) ?? prefs.getString('last_workspace_id');
    if (savedId != null) {
      for (final w in list) {
        if (w.id == savedId) return w;
      }
    }
    return list.first;
  }

  /// Clears local setup flags and embedded data for the default local account.
  static Future<void> resetLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_setupDoneKey);
    await ApiClient.clearToken();
    await ApiClient.clearAllAccountData();

    if (BackendManager.shouldRunEmbedded) {
      try {
        await BackendManager().stop();
        await BackendManager().deleteAccountData(localAccountId);
      } catch (e) {
        debugPrint('[LocalBootstrap] resetLocalData: $e');
      }
    }
  }
}