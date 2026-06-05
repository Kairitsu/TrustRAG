import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/settings/providers/server_config_provider.dart';
import '../../main.dart' show rootNavigatorKey;
import '../api/api_client.dart';
import '../services/backend_manager.dart';
import '../services/diagnostic_logger.dart';
import '../services/local_bootstrap.dart';
import '../services/mode_manager.dart';
import '../services/session_reset.dart';

/// Mode switches and local library deletion (await-before-navigate).
class AccountModeService {
  AccountModeService._();

  static BuildContext? _navContext(BuildContext? fallback) {
    final root = rootNavigatorKey.currentContext;
    if (root != null && root.mounted) return root;
    if (fallback != null && fallback.mounted) return fallback;
    return null;
  }

  static void _snack(BuildContext ctx, String message, {bool isError = false}) {
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
        duration: Duration(seconds: isError ? 5 : 3),
      ),
    );
  }

  static Future<T?> _withLoading<T>(
    BuildContext ctx,
    Future<T> Function() action,
  ) async {
    if (!ctx.mounted) return null;
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dCtx) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('处理中…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    try {
      return await action();
    } finally {
      if (ctx.mounted) {
        Navigator.of(ctx, rootNavigator: true).pop();
      }
    }
  }

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
    await DiagnosticLogger.info('MODE tap switch to server');
    var navCtx = _navContext(context);
    if (navCtx == null) {
      await DiagnosticLogger.error('MODE no navigator context for switch');
      return;
    }

    final ok = await confirm(
      navCtx,
      title: '切换到服务器账号',
      message:
          '即将切换到服务器账号模式。本机资料库仍会保留在当前设备，可稍后切回本地模式继续使用。',
    );
    if (!ok) {
      await DiagnosticLogger.info('MODE switch cancelled');
      return;
    }

    await DiagnosticLogger.info('MODE switch confirmed');

    navCtx = _navContext(context);
    if (navCtx == null || !navCtx.mounted) {
      await DiagnosticLogger.error('MODE navigator lost after confirm');
      return;
    }
    final ctx = navCtx;

    try {
      await _withLoading(ctx, () async {
        if (BackendManager.shouldRunEmbedded) {
          await DiagnosticLogger.info('MODE stopping embedded backend');
          try {
            await BackendManager().stop();
          } catch (e) {
            await DiagnosticLogger.warn('MODE backend stop: $e');
          }
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

        await DiagnosticLogger.info('MODE persisting server mode url=$url');
        final api = ref.read(apiClientProvider);
        await ref.read(modeProvider.notifier).setServerMode(url);
        api.dio.options.baseUrl = url;
        ref.invalidate(authProvider);

        await DiagnosticLogger.info('MODE navigate to /login');
        if (ctx.mounted) {
          ctx.go('/login');
          _snack(ctx, '已切换到服务器模式，请登录服务器账号');
        }
      });
    } catch (e, st) {
      await DiagnosticLogger.error('MODE switch failed: $e\n$st');
      final errCtx = _navContext(context);
      if (errCtx != null && errCtx.mounted) {
        _snack(errCtx, '切换到服务器模式失败：$e', isError: true);
      }
    }
  }

  static Future<void> deleteLocalLibrary(
    WidgetRef ref,
    BuildContext context,
  ) async {
    await DiagnosticLogger.info('MODE tap delete local library');
    var navCtx = _navContext(context);
    if (navCtx == null) {
      await DiagnosticLogger.error('MODE no navigator context for delete');
      return;
    }

    final ok = await confirm(
      navCtx,
      title: '删除本机资料库',
      message:
          '删除后，当前设备上的所有本机资料库数据都会被永久删除，包括上传文档、知识库、工作区、对话记录、索引、引用审核记录等。此操作不可恢复。',
      confirmLabel: '永久删除',
      isDanger: true,
    );
    if (!ok) {
      await DiagnosticLogger.info('MODE delete cancelled');
      return;
    }

    await DiagnosticLogger.info('MODE delete confirmed');

    navCtx = _navContext(context);
    if (navCtx == null || !navCtx.mounted) {
      await DiagnosticLogger.error('MODE navigator lost after delete confirm');
      return;
    }
    final ctx = navCtx;

    try {
      await _withLoading(ctx, () async {
        final resetResult = await LocalBootstrap.resetLocalData();
        await DiagnosticLogger.info(
          'MODE resetLocalData success=${resetResult.success} paths=${resetResult.deletedPaths}',
        );
        if (!resetResult.success) {
          throw Exception(resetResult.message);
        }

        resetAccountScopedState(ref);
        ref.read(authProvider.notifier).clearSessionState();
        await ref.read(modeProvider.notifier).resetMode();
        ref.invalidate(authProvider);

        await DiagnosticLogger.info('MODE navigate to /onboarding after delete');
        if (ctx.mounted) {
          ctx.go('/onboarding');
          _snack(ctx, '本机资料库已删除，应用将重新初始化');
        }
      });
    } catch (e, st) {
      await DiagnosticLogger.error('MODE delete failed: $e\n$st');
      final errCtx = _navContext(context);
      if (errCtx != null && errCtx.mounted) {
        _snack(errCtx, '删除本机资料库失败：$e', isError: true);
      }
    }
  }

  static Future<void> switchToLocalMode(
    WidgetRef ref,
    BuildContext context,
  ) async {
    await DiagnosticLogger.info('MODE tap switch to local');
    var navCtx = _navContext(context);
    if (navCtx == null) return;

    final ok = await confirm(
      navCtx,
      title: '切换使用方式',
      message:
          '即将切换回本地模式。本地模式的数据仅保存在当前设备。当前服务器账号会退出登录，但服务器上的账号和资料不会被删除。',
    );
    if (!ok) return;

    navCtx = _navContext(context);
    if (navCtx == null || !navCtx.mounted) return;
    final ctx = navCtx;

    try {
      await _withLoading(ctx, () async {
        await ref.read(authProvider.notifier).logout();
        resetAccountScopedState(ref);
        await ref.read(modeProvider.notifier).setLocalMode();
        ref.invalidate(authProvider);
        if (ctx.mounted) {
          ctx.go('/local-startup');
          _snack(ctx, '已切换为本地模式');
        }
      });
    } catch (e, st) {
      await DiagnosticLogger.error('MODE switch to local failed: $e\n$st');
      final errCtx = _navContext(context);
      if (errCtx != null && errCtx.mounted) {
        _snack(errCtx, '切换本地模式失败：$e', isError: true);
      }
    }
  }

  static Future<void> serverLogout(
    WidgetRef ref,
    BuildContext context,
  ) async {
    final navCtx = _navContext(context);
    if (navCtx == null) return;

    try {
      await _withLoading(navCtx, () async {
        await ref.read(authProvider.notifier).logout();
        resetAccountScopedState(ref);
        if (navCtx.mounted) navCtx.go('/login');
      });
    } catch (e, st) {
      await DiagnosticLogger.error('MODE logout failed: $e\n$st');
      final errCtx = _navContext(context);
      if (errCtx != null && errCtx.mounted) {
        _snack(errCtx, '退出登录失败：$e', isError: true);
      }
    }
  }
}