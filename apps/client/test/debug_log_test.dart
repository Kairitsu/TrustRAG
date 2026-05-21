import 'package:flutter_test/flutter_test.dart';
import 'package:client/core/providers/dev_mode_provider.dart';

void main() {
  setUp(() {
    DebugLogBuffer().clear();
  });

  group('DebugLogBuffer', () {
    test('starts empty', () {
      expect(DebugLogBuffer().logs, isEmpty);
    });

    test('add() appends a timestamped entry', () {
      DebugLogBuffer().add('hello');
      expect(DebugLogBuffer().logs.length, 1);
      expect(DebugLogBuffer().logs.first, contains('hello'));
      expect(DebugLogBuffer().logs.first, matches(RegExp(r'^\[\d{2}:\d{2}:\d{2}\.\d{3}\]')));
    });

    test('clear() empties the buffer', () {
      DebugLogBuffer().add('a');
      DebugLogBuffer().add('b');
      expect(DebugLogBuffer().logs.length, 2);
      DebugLogBuffer().clear();
      expect(DebugLogBuffer().logs, isEmpty);
    });

    test('respects maxLogs limit', () {
      for (var i = 0; i < 510; i++) {
        DebugLogBuffer().add('log-$i');
      }
      expect(DebugLogBuffer().logs.length, DebugLogBuffer.maxLogs);
      expect(DebugLogBuffer().logs.first, contains('log-10'));
      expect(DebugLogBuffer().logs.last, contains('log-509'));
    });

    test('singleton returns the same instance', () {
      final a = DebugLogBuffer();
      final b = DebugLogBuffer();
      a.add('from-a');
      expect(b.logs.length, 1);
      expect(identical(a, b), isTrue);
    });

    test('logs list is unmodifiable', () {
      DebugLogBuffer().add('x');
      expect(() => DebugLogBuffer().logs.add('y'), throwsUnsupportedError);
    });

    test('preserves insertion order', () {
      DebugLogBuffer().add('first');
      DebugLogBuffer().add('second');
      DebugLogBuffer().add('third');
      expect(DebugLogBuffer().logs[0], contains('first'));
      expect(DebugLogBuffer().logs[1], contains('second'));
      expect(DebugLogBuffer().logs[2], contains('third'));
    });

    test('ERROR prefix messages are captured correctly', () {
      DebugLogBuffer().add('ERROR DOC 上传失败: timeout');
      expect(DebugLogBuffer().logs.first, contains('ERROR DOC'));
    });
  });
}
