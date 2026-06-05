import 'package:flutter_test/flutter_test.dart';
import 'package:client/core/providers/dev_mode_provider.dart';
import 'package:client/core/services/diagnostic_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DebugLogBuffer().clear());

  group('DiagnosticLogger', () {
    test('info mirrors to DebugLogBuffer', () async {
      await DiagnosticLogger.info('MODE test line');
      expect(DebugLogBuffer().logs.last, contains('MODE test line'));
      expect(DebugLogBuffer().logs.last, contains('INFO'));
    });

    test('exportRecent includes session buffer', () async {
      await DiagnosticLogger.info('export test');
      final text = await DiagnosticLogger.exportRecent(maxLines: 10);
      expect(text, contains('TrustRAG Client Diagnostics'));
      expect(text, contains('export test'));
    });
  });
}