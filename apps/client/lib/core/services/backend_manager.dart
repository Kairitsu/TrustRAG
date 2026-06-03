import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../providers/dev_mode_provider.dart';

class BackendManager {
  static final BackendManager _instance = BackendManager._();
  factory BackendManager() => _instance;
  BackendManager._();

  static const _channel = MethodChannel('com.trustrag.app/native');

  Process? _process;
  int? _port;
  bool _isRunning = false;
  bool _startAttempted = false;
  String? _startupError;
  Completer<void> _readyCompleter = Completer<void>();
  String? _currentAccountId;
  String? _currentDataDir;

  int? get port => _port;
  bool get isRunning => _isRunning;
  bool get startAttempted => _startAttempted;
  String? get startupError => _startupError;
  bool get hasFailed => _startupError != null;
  String get baseUrl => 'http://127.0.0.1:$_port';
  Future<void> get ready => _readyCompleter.future;
  String? get currentAccountId => _currentAccountId;
  String? get currentDataDir => _currentDataDir;

  /// Whether this platform should run an embedded backend.
  static bool get shouldRunEmbedded {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS || Platform.isAndroid;
  }

  Future<void> start({String? accountId}) async {
    if (!shouldRunEmbedded || _isRunning) return;

    _startAttempted = true;
    _currentAccountId = accountId;
    _port = await _findFreePort();
    final backendPath = await _findBackendBinary();

    if (backendPath == null) {
      _startupError = Platform.isAndroid
          ? 'Embedded backend binary not found. '
            'This may be caused by missing android:extractNativeLibs="true" '
            'in AndroidManifest.xml, or the APK was not built with the backend.'
          : 'Embedded backend binary not found. '
            'The backend executable may not be bundled with this build.';
      debugPrint('[BackendManager] $_startupError');
      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
      return;
    }

    final dataDir = await _getDataDir(accountId: accountId);
    _currentDataDir = dataDir;
    await Directory(dataDir).create(recursive: true);

    final dbPath = p.join(dataDir, 'trustrag.db');

    final env = {
      'TRUSTRAG__LISTEN_ADDR': '127.0.0.1:$_port',
      'TRUSTRAG__DATABASE_URL': 'sqlite://$dbPath?mode=rwc',
      'TRUSTRAG__DATA_DIR': dataDir,
      'TRUSTRAG__JWT_SECRET': _generateJwtSecret(),
      'TRUSTRAG__DOC_PROCESSOR_URL': 'http://127.0.0.1:0',
      'TRUSTRAG__MAX_UPLOAD_SIZE_MB': '100',
      'RUST_LOG': 'trustrag_backend=info',
    };

    debugPrint('[BackendManager] Starting backend on port $_port');
    debugPrint('[BackendManager] Data dir: $dataDir');
    debugPrint('[BackendManager] Account: ${accountId ?? "default"}');
    debugPrint('[BackendManager] Binary: $backendPath');
    DebugLogBuffer().add('BACKEND 启动中 port=$_port account=${accountId ?? "default"}');
    DebugLogBuffer().add('BACKEND 数据目录: $dataDir');

    final stderrLines = <String>[];

    try {
      _process = await Process.start(
        backendPath,
        [],
        environment: env,
        workingDirectory: Platform.isAndroid ? dataDir : p.dirname(backendPath),
      );

      _process!.stdout.listen((data) {
        final line = String.fromCharCodes(data).trim();
        if (line.isNotEmpty) debugPrint('[Backend] $line');
        if (line.contains('ready and listening')) {
          _isRunning = true;
          if (!_readyCompleter.isCompleted) _readyCompleter.complete();
        }
      });

      _process!.stderr.listen((data) {
        final line = String.fromCharCodes(data).trim();
        if (line.isNotEmpty) {
          debugPrint('[Backend:ERR] $line');
          stderrLines.add(line);
          DebugLogBuffer().add('BACKEND STDERR: $line');
        }
      });

      _process!.exitCode.then((code) {
        debugPrint('[BackendManager] Backend exited with code $code');
        _isRunning = false;
        _process = null;
        if (code != 0 && _startupError == null) {
          final lastLines = stderrLines.length > 5
              ? stderrLines.sublist(stderrLines.length - 5)
              : stderrLines;
          final detail = lastLines.isNotEmpty
              ? lastLines.join('\n')
              : 'No stderr output captured';
          _startupError = 'Backend exited with code $code.\n$detail';
          DebugLogBuffer().add('ERROR BACKEND 异常退出 code=$code');
          if (!_readyCompleter.isCompleted) _readyCompleter.complete();
        }
      });

      await _readyCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('[BackendManager] Backend startup timed out, will verify via health check');
          if (!_readyCompleter.isCompleted) _readyCompleter.complete();
        },
      );
    } catch (e) {
      _startupError = 'Failed to start embedded backend: $e';
      debugPrint('[BackendManager] $_startupError');
      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
    }

    if (!_isRunning && _startupError == null) {
      _isRunning = await _healthCheck();
      debugPrint('[BackendManager] Health check result: $_isRunning');
      DebugLogBuffer().add(_isRunning
          ? 'BACKEND 健康检查通过，端口 $_port'
          : 'ERROR BACKEND 健康检查失败');
      if (!_isRunning && _startupError == null) {
        final detail = stderrLines.isNotEmpty
            ? stderrLines.last
            : 'Health check failed after timeout';
        _startupError = 'Backend did not become ready.\n$detail';
      }
    }
  }

  /// Stop the current backend, then start a new one pointing to
  /// the given account's isolated data directory.
  Future<void> restart({String? accountId}) async {
    debugPrint('[BackendManager] Restarting for account: ${accountId ?? "default"}');
    DebugLogBuffer().add('BACKEND 重启中，切换账号: ${accountId ?? "default"}');
    await stop();
    _readyCompleter = Completer<void>();
    _startupError = null;
    _startAttempted = false;
    await start(accountId: accountId);
  }

  /// Get the data directory path for an account (without creating it).
  Future<String> getAccountDataDir(String accountId) async {
    return _getDataDir(accountId: accountId);
  }

  /// Delete the local data directory for a specific account.
  Future<bool> deleteAccountData(String accountId) async {
    final dir = Directory(await getAccountDataDir(accountId));
    if (await dir.exists()) {
      debugPrint('[BackendManager] Deleting data for account: $accountId');
      DebugLogBuffer().add('BACKEND 删除账号数据: $accountId');
      await dir.delete(recursive: true);
      return true;
    }
    return false;
  }

  /// HTTP health check to verify the backend is actually responding.
  Future<bool> _healthCheck() async {
    final url = Uri.parse('http://127.0.0.1:$_port/health');
    for (var i = 0; i < 3; i++) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        final request = await client.getUrl(url);
        final response = await request.close().timeout(
          const Duration(seconds: 3),
        );
        final body = await response.transform(utf8.decoder).join();
        client.close();
        if (response.statusCode == 200 && body.contains('ok')) {
          debugPrint('[BackendManager] Health check passed on attempt ${i + 1}');
          return true;
        }
      } catch (e) {
        debugPrint('[BackendManager] Health check attempt ${i + 1} failed: $e');
      }
      if (i < 2) await Future.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  Future<void> stop() async {
    if (_process != null) {
      debugPrint('[BackendManager] Stopping backend...');
      _process!.kill(ProcessSignal.sigterm);
      try {
        await _process!.exitCode.timeout(const Duration(seconds: 5));
      } catch (_) {
        _process!.kill(ProcessSignal.sigkill);
      }
      _process = null;
      _isRunning = false;
    }
  }

  Future<int> _findFreePort() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    return port;
  }

  Future<String?> _findBackendBinary() async {
    if (Platform.isAndroid) {
      return _findAndroidBinary();
    }

    final binaryName = Platform.isWindows
        ? 'trustrag-backend.exe'
        : 'trustrag-backend';

    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      p.join(exeDir, binaryName),
      p.join(exeDir, 'data', 'flutter_assets', binaryName),
      p.join(exeDir, '..', 'Resources', binaryName), // macOS .app bundle
      p.join(exeDir, '..', 'lib', binaryName),
      p.join(exeDir, 'backend', binaryName),
    ];

    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    return null;
  }

  Future<String?> _findAndroidBinary() async {
    const libName = 'libtrustrap_backend.so';

    // Primary: get native library directory via platform channel
    try {
      final nativeLibDir = await _channel.invokeMethod<String>('getNativeLibraryDir');
      if (nativeLibDir != null) {
        final path = p.join(nativeLibDir, libName);
        debugPrint('[BackendManager] Checking native lib path from channel: $path');
        if (await File(path).exists()) {
          debugPrint('[BackendManager] Found Android binary via MethodChannel: $path');
          return path;
        }
      }
    } catch (e) {
      debugPrint('[BackendManager] MethodChannel failed: $e');
    }

    // Fallback: common paths
    final appInfo = await getApplicationSupportDirectory();
    final dataDir = p.dirname(p.dirname(appInfo.path));
    final candidates = [
      p.join(dataDir, 'lib', libName),
      '/data/data/com.trustrag.app/lib/$libName',
    ];

    for (final candidate in candidates) {
      debugPrint('[BackendManager] Checking fallback path: $candidate');
      if (await File(candidate).exists()) {
        debugPrint('[BackendManager] Found Android binary at fallback: $candidate');
        return candidate;
      }
    }

    debugPrint('[BackendManager] Android binary NOT found in any path');
    return null;
  }

  Future<String> _getDataDir({String? accountId}) async {
    final appSupport = await getApplicationSupportDirectory();
    final base = p.join(appSupport.path, 'TrustRAG');
    if (accountId != null && accountId.isNotEmpty) {
      final safeId = accountId.replaceAll(RegExp(r'[^\w.@\-]'), '_');
      return p.join(base, 'accounts', safeId);
    }
    return base;
  }

  String _generateJwtSecret() {
    final hostname = Platform.isAndroid ? 'android-device' : Platform.localHostname;
    final seed = hostname + Platform.operatingSystem;
    return seed.hashCode.toRadixString(36).padLeft(32, 'x');
  }
}
