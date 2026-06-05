import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../providers/dev_mode_provider.dart';

/// Persistent client diagnostics for release builds (AppData/logs).
class DiagnosticLogger {
  DiagnosticLogger._();

  static String? _cachedLogDir;

  static Future<String> get logDirectory async {
    if (_cachedLogDir != null) return _cachedLogDir!;
    final appSupport = await getApplicationSupportDirectory();
    _cachedLogDir = p.join(appSupport.path, 'TrustRAG', 'logs');
    return _cachedLogDir!;
  }

  static Future<void> info(String message) => _write('INFO', message);

  static Future<void> warn(String message) => _write('WARN', message);

  static Future<void> error(String message) => _write('ERROR', message);

  static Future<void> _write(String level, String message) async {
    final line = '[${_timestamp()}] $level $message';
    DebugLogBuffer().add('$level $message');
    if (kIsWeb) {
      debugPrint(line);
      return;
    }
    try {
      final dir = await logDirectory;
      await Directory(dir).create(recursive: true);
      final file = File(_logFilePath(dir));
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('[DiagnosticLogger] write failed: $e — $line');
    }
  }

  static String _logFilePath(String dir) {
    final day = DateTime.now().toIso8601String().substring(0, 10);
    return p.join(dir, 'client-$day.log');
  }

  static String _timestamp() {
    final now = DateTime.now();
    return now.toIso8601String().substring(0, 23);
  }

  /// Recent on-disk log lines plus in-memory buffer (newest last).
  static Future<String> exportRecent({int maxLines = 200}) async {
    final buf = StringBuffer('=== TrustRAG Client Diagnostics ===\n');
    buf.writeln('exported: ${DateTime.now().toIso8601String()}');

    if (!kIsWeb) {
      try {
        final dir = await logDirectory;
        buf.writeln('log_dir: $dir\n');
        final file = File(_logFilePath(dir));
        if (await file.exists()) {
          final lines = await file.readAsLines();
          final tail = lines.length > maxLines
              ? lines.sublist(lines.length - maxLines)
              : lines;
          buf.writeln('--- file log (tail) ---');
          for (final line in tail) {
            buf.writeln(line);
          }
          buf.writeln();
        }
      } catch (e) {
        buf.writeln('log_dir: (unavailable — $e)\n');
      }
    } else {
      buf.writeln();
    }

    buf.writeln('--- session buffer ---');
    final mem = DebugLogBuffer().logs;
    final memTail = mem.length > maxLines
        ? mem.sublist(mem.length - maxLines)
        : mem;
    for (final line in memTail) {
      buf.writeln(line);
    }
    return buf.toString();
  }
}