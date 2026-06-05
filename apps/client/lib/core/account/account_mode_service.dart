import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/settings/providers/server_config_provider.dart';
import '../api/api_client.dart';
import '../services/backend_manager.dart';
import '../services/local_bootstrap.dart';
import '../services/mode_manager.dart';
import '../services/session_reset.dart';

/// Mode switches and local library deletion (await-before-navigate).
class AccountModeService {
  AccountModeService._();

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = '确认',
    bool isDanger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: isDanger
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  static Future<void> switchToServerMode(
    WidgetRef ref,
    BuildContext context,
  ) async {
    final ok = await confirm(
      context,
      title: '切换到服务器账号',
      message:
          '即将切换到服务器账号模式。本机资料库仍会保留在当前设备，可稍后切回本地模式继续使用。',
    );
    if (!ok || !context.mounted) return;

    if (BackendManager.shouldRunEmbedded) {
      try {
        await BackendManager().stop();
      } catch (_) {}
    }

    resetAccountScopedState(ref);
    await ApiClient.clearCurrentServerSession();
    ref.read(authProvider.notifier).clearSessionState();

    final modeState = ref.read(modeProvider);
    var url = modeState.serverUrl?.trim() ?? '';
    if (url.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      url = prefs.getString('custom_server_url')?.trim() ?? '';
    }
    if (url.isEmpty) {
      url = ServerConfig.officialUrl;
    }

    final api = ref.read(apiClientProvider);
    await ref.read(modeProvider.notifier).setServerMode(url);
    api.dio.options.baseUrl = url;
    ref.invalidate(authProvider);

    if (context.mounted) context.go('/login');
  }

  static Future<void> deleteLocalLibrary(
    WidgetRef ref,
    BuildContext context,
  ) async {
    final ok = await confirm(
      context,
      title: '删除本机资料库',
      message:
          '删除后，当前设备上的所有本机资料库数据都会被永久删除，包括上传文档、知识库、工作区、对话记录、索引、引用审核记录等。此操作不可恢复。',
      confirmLabel: '永久删除',
      isDanger: true,
    );
    if (!ok || !context.mounted) return;

    await LocalBootstrap.resetLocalData();
    resetAccountScopedState(ref);
    ref.read(authProvider.notifier).clearSessionState();
    await ref.read(modeProvider.notifier).resetMode();
    ref.invalidate(authProvider);

    if (context.mounted) context.go('/onboarding');
  }

  static Future<void> switchToLocalMode(
    WidgetRef ref,
    BuildContext context,
  ) async {
    final ok = await confirm(
      context,
      title: '切换使用方式',
      message:
          '即将切换回本地模式。本地模式的数据仅保存在当前设备。当前服务器账号会退出登录，但服务器上的账号和资料不会被删除。',
    );
    if (!ok || !context.mounted) return;

    await ref.read(authProvider.notifier).logout();
    resetAccountScopedState(ref);
    await ref.read(modeProvider.notifier).setLocalMode();
    ref.invalidate(authProvider);

    if (context.mounted) context.go('/local-startup');
  }

  static Future<void> serverLogout(
    WidgetRef ref,
    BuildContext context,
  ) async {
    await ref.read(authProvider.notifier).logout();
    resetAccountScopedState(ref);
    if (context.mounted) context.go('/login');
  }
}