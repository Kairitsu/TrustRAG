import 'dart:io';

import 'package:path/path.dart' as p;

/// Guards for deleting TrustRAG per-account data directories on disk.
class LocalDataPathGuard {
  LocalDataPathGuard._();

  /// Only delete paths under TrustRAG account storage, never install dir.
  static bool isSafeToDelete(String dirPath) {
    if (dirPath.trim().isEmpty) return false;
    final normalized = p.normalize(p.absolute(dirPath));
    if (normalized.length < 12) return false;
    if (!normalized.contains('TrustRAG')) return false;

    final exeDir = p.normalize(p.dirname(Platform.resolvedExecutable));
    if (normalized.startsWith(exeDir)) return false;

    final segments = p.split(normalized);
    final accountsIdx = segments.indexOf('accounts');
    if (accountsIdx < 0 || accountsIdx >= segments.length - 1) return false;

    return true;
  }
}