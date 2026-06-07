import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import 'backend_manager.dart';
import 'diagnostic_logger.dart';
import 'local_bootstrap.dart';
import 'windows_local_data_paths.dart';

class LocalDataWipeResult {
  final bool success;
  final String message;
  final List<String> deletedPaths;
  final String? backupPath;

  const LocalDataWipeResult({
    required this.success,
    required this.message,
    this.deletedPaths = const [],
    this.backupPath,
  });
}

/// Wipes all TrustRAG local state on disk and in SharedPreferences.
class LocalDataWipe {
  LocalDataWipe._();

  static Future<LocalDataWipeResult> wipeAllLocalData({
    bool backupFirst = true,
  }) async {
    await DiagnosticLogger.info('WIPE all local data started backup=$backupFirst');
    final deletedPaths = <String>[];
    String? backupPath;

    if (!BackendManager.shouldRunEmbedded) {
      return const LocalDataWipeResult(
        success: false,
        message: '当前环境不支持清除本机全部数据',
      );
    }

    try {
      final bm = BackendManager();

      if (backupFirst && bm.isRunning) {
        backupPath = await _tryBackupDatabase();
      }

      await DiagnosticLogger.info('WIPE stopping backend');
      await bm.stop();
      if (bm.isRunning) {
        return const LocalDataWipeResult(
          success: false,
          message:
              '无法停止本机后端。请完全退出 TrustRAG，在任务管理器中结束 trustrag-backend.exe 后重试。',
        );
      }

      final targets = await _collectDeleteTargets();
      Object? lastError;

      for (final dirPath in targets) {
        if (!await _deleteDirectory(dirPath)) {
          lastError = '无法删除 $dirPath';
          break;
        }
        deletedPaths.add(dirPath);
      }

      if (lastError != null) {
        await DiagnosticLogger.error('WIPE delete failed: $lastError');
        return LocalDataWipeResult(
          success: false,
          message: '$lastError\n可能仍有进程占用数据库文件。',
          deletedPaths: deletedPaths,
          backupPath: backupPath,
        );
      }

      await _clearAllPreferences();
      bm.resetLifecycle();

      await DiagnosticLogger.info('WIPE completed deleted=${deletedPaths.length}');
      return LocalDataWipeResult(
        success: true,
        message: backupPath != null
            ? '本机全部数据已清除。数据库备份：$backupPath'
            : '本机全部数据已清除。',
        deletedPaths: deletedPaths,
        backupPath: backupPath,
      );
    } catch (e, st) {
      await DiagnosticLogger.error('WIPE failed: $e\n$st');
      debugPrint('[LocalDataWipe] $e\n$st');
      return LocalDataWipeResult(
        success: false,
        message: '清除本机数据失败：$e',
        deletedPaths: deletedPaths,
        backupPath: backupPath,
      );
    }
  }

  static Future<List<String>> _collectDeleteTargets() async {
    final paths = <String>{};

    if (Platform.isWindows) {
      paths.addAll(WindowsLocalDataPaths.resolveAll());
    }

    try {
      final appSupport = await getApplicationSupportDirectory();
      final trustragRoot = p.normalize(p.join(appSupport.path, 'TrustRAG'));
      paths.add(trustragRoot);
      final accountsDir = Directory(p.join(trustragRoot, 'accounts'));
      if (await accountsDir.exists()) {
        await for (final entity in accountsDir.list()) {
          if (entity is Directory) {
            paths.add(p.normalize(entity.path));
          }
        }
      }
    } catch (_) {}

    try {
      final appDoc = await getApplicationDocumentsDirectory();
      paths.add(p.normalize(p.join(appDoc.path, 'TrustRAG')));
    } catch (_) {}

    final safe = paths.where((path) {
      if (Platform.isWindows) {
        return WindowsLocalDataPaths.isSafeToDelete(path);
      }
      return LocalBootstrap.isDataDirSafeToDelete(path);
    }).toList()
      ..sort();

    return safe;
  }

  static Future<String?> _tryBackupDatabase() async {
    try {
      final dataDir = await BackendManager().getAccountDataDir(
        LocalBootstrap.localAccountId,
      );
      final dbFile = File(p.join(dataDir, 'trustrag.db'));
      if (!await dbFile.exists()) return null;

      final docs = await getApplicationDocumentsDirectory();
      final backupDir = p.join(docs.path, 'TrustRAG_backups');
      await Directory(backupDir).create(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final dest = p.join(backupDir, 'trustrag-backup-$stamp.db');
      await dbFile.copy(dest);
      return dest;
    } catch (e) {
      await DiagnosticLogger.warn('WIPE backup skipped: $e');
      return null;
    }
  }

  static Future<bool> _deleteDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return true;

    const delays = [
      Duration.zero,
      Duration(milliseconds: 300),
      Duration(milliseconds: 600),
      Duration(milliseconds: 1000),
    ];

    for (final delay in delays) {
      if (delay > Duration.zero) await Future.delayed(delay);
      try {
        await dir.delete(recursive: true);
        return true;
      } catch (_) {}
    }
    return false;
  }

  static Future<void> _clearAllPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList();
    for (final key in keys) {
      await prefs.remove(key);
    }

    final accounts = await ApiClient.getSavedAccounts();
    for (final email in accounts) {
      await ApiClient.removeAccount(email);
    }
    await ApiClient.clearAllAccountData();
  }
}