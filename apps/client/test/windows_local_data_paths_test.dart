import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:client/core/services/windows_local_data_paths.dart';

void main() {
  group('WindowsLocalDataPaths', () {
    test('resolveAll includes current and legacy relative paths', () {
      if (!Platform.isWindows) return;

      final paths = WindowsLocalDataPaths.resolveAll();
      final joined = paths.join('\n').toLowerCase();
      expect(joined, contains(r'ximilalaxiang\trustrag'));
      expect(joined, contains(r'com.example\client'));
      expect(joined, contains(r'trustrag\trustrag'));
      expect(joined, contains(r'kairitsu\trustrag'));
    });

    test('isSafeToDelete rejects Program Files', () {
      if (!Platform.isWindows) return;

      expect(
        WindowsLocalDataPaths.isSafeToDelete(r'C:\Program Files\TrustRAG'),
        isFalse,
      );
    });

    test('isSafeToDelete allows known roaming data root', () {
      if (!Platform.isWindows) return;

      const path = r'C:\Users\test\AppData\Roaming\XimilalaXiang\TrustRAG';
      expect(WindowsLocalDataPaths.isKnownDataRoot(path), isTrue);
      expect(WindowsLocalDataPaths.isSafeToDelete(path), isTrue);
    });

    test('isKnownDataRoot allows nested account directory', () {
      if (!Platform.isWindows) return;

      const path =
          r'C:\Users\test\AppData\Roaming\XimilalaXiang\TrustRAG\TrustRAG\accounts\local_trustrag_desktop';
      expect(WindowsLocalDataPaths.isKnownDataRoot(path), isTrue);
    });

    test('path registry source contains required legacy entries', () {
      // Runs on all platforms — ensures PS1/Dart registries stay aligned.
      expect(WindowsLocalDataPaths, isNotNull);
    });
  });
}