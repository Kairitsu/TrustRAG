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
  final _readyCompleter = Completer<void>();

  int? get port => _port;
  bool get isRunning => _isRunning;
  bool get startAttempted => _startAttempted;
  String? get startupError => _startupError;
  bool get hasFailed => _startupError != null;
  String get baseUrl => 'http://127.0.0.1:$_port';
  Future<void> get ready => _readyCompleter.future;

  /// Whether this platform should run an embedded backend.
  static bool get shouldRunEmbedded {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS || Platform.isAndroid;
  }

  Future<void> start() async {
    if (!shouldRunEmbedded || _isRunning) return;

    _startAttempted = true;
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

    final dataDir = await _getDataDir();
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
    debugPrint('[BackendManager] Binary: $backendPath');
    DebugLogBuffer().add('BACKEND 启动中 port=$_port');
    DebugLogBuffer().add('BACKEND 数据目录: $dataDir');

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
        if (line.isNotEmpty) debugPrint('[Backend:ERR] $line');
      });

      _process!.exitCode.then((code) {
        debugPrint('[BackendManager] Backend exited with code $code');
        _isRunning = false;
        _process = null;
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

    if (!_isRunning) {
      _isRunning = await _healthCheck();
      debugPrint('[BackendManager] Health check result: $_isRunning');
      DebugLogBuffer().add(_isRunning
          ? 'BACKEND 健康检查通过，端口 $_port'
          : 'ERROR BACKEND 健康检查失败');
    }
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

  Future<String> _getDataDir() async {
    final appSupport = await getApplicationSupportDirectory();
    return p.join(appSupport.path, 'TrustRAG');
  }

  String _generateJwtSecret() {
    final hostname = Platform.isAndroid ? 'android-device' : Platform.localHostname;
    final seed = hostname + Platform.operatingSystem;
    return seed.hashCode.toRadixString(36).padLeft(32, 'x');
  }
}
