import 'dart:io';

import 'package:path/path.dart' as p;

/// Central registry of TrustRAG Windows user-data directories (current + legacy).
class WindowsLocalDataPaths {
  WindowsLocalDataPaths._();

  static const _roamingRelative = [
    r'XimilalaXiang\TrustRAG',
    r'XimilalaXiang\TrustRAG\TrustRAG',
    r'com.example\client',
    r'com.example\client\TrustRAG',
    r'com.example\TrustRAG',
    r'com.trustrag',
    r'com.trustrag\TrustRAG',
    r'com.trustrag.client',
    r'com.trustrag.client\TrustRAG',
    r'com.trustrag.app',
    r'TrustRAG',
    r'trustrag',
    r'Kairitsu\TrustRAG',
  ];

  static const _localRelative = [
    r'trustrag\TrustRAG',
    r'trustrag\TrustRAG\data',
    r'trustrag\TrustRAG\config',
    r'trustrag\TrustRAG\cache',
    r'com.trustrag\TrustRAG',
    r'com.trustrag\TrustRAG\data',
    r'TrustRAG',
    r'trustrag',
    r'XimilalaXiang\TrustRAG',
    r'Kairitsu\TrustRAG',
  ];

  /// Resolves all known TrustRAG data directories for the current user.
  static List<String> resolveAll() {
    if (!Platform.isWindows) return const [];

    final appData = Platform.environment['APPDATA'];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (appData == null || localAppData == null) return const [];

    final paths = <String>{};
    for (final rel in _roamingRelative) {
      paths.add(p.normalize(p.join(appData, rel)));
    }
    for (final rel in _localRelative) {
      paths.add(p.normalize(p.join(localAppData, rel)));
    }
    return paths.toList()..sort();
  }

  /// Returns true when [dirPath] is a known TrustRAG data root (safe for wipe).
  static bool isKnownDataRoot(String dirPath) {
    if (!Platform.isWindows || dirPath.trim().isEmpty) return false;
    final normalized = p.normalize(p.absolute(dirPath));
    return resolveAll().any(
      (known) => p.equals(normalized, known) || normalized.startsWith('$known${p.separator}'),
    );
  }

  /// Never delete install directory or unrelated vendor roots.
  static bool isSafeToDelete(String dirPath) {
    if (!isKnownDataRoot(dirPath)) return false;

    final normalized = p.normalize(p.absolute(dirPath));
    final programFiles = Platform.environment['ProgramFiles'];
    if (programFiles != null &&
        normalized.startsWith(p.normalize(programFiles))) {
      return false;
    }

    final pf86 = Platform.environment['ProgramFiles(x86)'];
    if (pf86 != null && normalized.startsWith(p.normalize(pf86))) {
      return false;
    }

    return true;
  }
}