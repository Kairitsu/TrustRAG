import 'package:flutter_test/flutter_test.dart';
import 'package:client/core/services/local_bootstrap.dart';
import 'package:client/core/services/local_data_path_guard.dart';

void main() {
  group('LocalBootstrap.isDataDirSafeToDelete', () {
    test('allows TrustRAG accounts subdirectory', () {
      expect(
        LocalBootstrap.isDataDirSafeToDelete(
          '/home/user/.local/share/TrustRAG/accounts/local_trustrag_desktop',
        ),
        isTrue,
      );
    });

    test('rejects install-like paths', () {
      expect(
        LocalBootstrap.isDataDirSafeToDelete(r'C:\Program Files\TrustRAG'),
        isFalse,
      );
    });

    test('rejects paths without accounts segment', () {
      expect(
        LocalBootstrap.isDataDirSafeToDelete(r'C:\Users\me\AppData\TrustRAG'),
        isFalse,
      );
    });

    test('rejects empty or short paths', () {
      expect(LocalBootstrap.isDataDirSafeToDelete(''), isFalse);
      expect(LocalBootstrap.isDataDirSafeToDelete('/tmp'), isFalse);
    });

    test('LocalDataPathGuard matches LocalBootstrap delegate', () {
      const path =
          '/home/user/.local/share/TrustRAG/accounts/local@trustrag.desktop';
      expect(LocalDataPathGuard.isSafeToDelete(path), isTrue);
      expect(LocalBootstrap.isDataDirSafeToDelete(path), isTrue);
    });
  });
}