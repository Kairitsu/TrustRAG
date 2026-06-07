import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../providers/dev_mode_provider.dart';
import 'diagnostic_logger.dart';
import 'local_data_path_guard.dart';

class DirectoryDeleteResult {
  final bool success;
  final String message;

  const DirectoryDeleteResult({
    required this.success,
    required this.message,
  });
}

class BackendManager {
  static final BackendManager _instance = BackendManager._();
  factory BackendManager() => _instance;
  BackendManager._();

  static const _channel = MethodChannel('com.trustrag.app/native');

  Process? _process;
  int? _port;
  bool _isRunning = false;
  bool _ownsProcess = false;
  bool _startAttempted = false;
  String? _startupError;
  static const _attachPorts = [8080];
  Completer<void> _readyCompleter = Completer<void>();
  String? _currentAccountId;
  String? _currentDataDir;

  int? get port => _port;
  bool get isRunning => _isRunning;
  bool get startAttempted => _startAttempted;
  bool get ownsProcess => _ownsProcess;
  String? get startupError => _startupError;
  bool get hasFailed => _startupError != null;
  String get baseUrl => 'http://127.0.0.1:$_port';
  Future<void> get ready => _readyCompleter.future;
  String? get currentAccountId => _currentAccountId;
  String? get currentDataDir => _currentDataDir;

  /// Whether this platform should run an embedded backend.
  static bool get shouldRunEmbedded {
    if (kIsWeb) return false;
    return Platform.isWindows ||
        Platform.isLinux ||
        Platform.isMacOS ||
        Platform.isAndroid;
  }

  /// Clears startup failure state before a new start/restart attempt.
  void resetLifecycle() {
    _startupError = null;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
    _readyCompleter = Completer<void>();
    if (_process == null) {
      _isRunning = false;
      _port = null;
      _ownsProcess = false;
    }
  }

  Future<void> start({
    String? accountId,
    bool allowAttachExisting = true,
    bool forceRestart = false,
  }) async {
    if (!shouldRunEmbedded) return;

    if (forceRestart && (_isRunning || _process != null)) {
      await stop();
    }

    resetLifecycle();
    _startAttempted = true;

    if (_isRunning && _process != null) return;

    if (allowAttachExisting && !forceRestart && await _tryAttachExistingBackend()) {
      _currentAccountId = accountId;
      return;
    }

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
        workingDirectory:
            Platform.isAndroid ? dataDir : p.dirname(backendPath),
      );
      _ownsProcess = true;

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
        _ownsProcess = false;
        _process = null;
        if (code != 0 && _startupError == null) {
          final lastLines = stderrLines.length > 5
              ? stderrLines.sublist(stderrLines.length - 5)
              : stderrLines;
          final detail = lastLines.isNotEmpty
              ? lastLines.join('\n')
              : _diagnoseExitCode(code, backendPath);
          _startupError = 'Backend exited with code $code.\n$detail';
          DebugLogBuffer().add('ERROR BACKEND 异常退出 code=$code');
          if (!_readyCompleter.isCompleted) _readyCompleter.complete();
        }
      });

      await _readyCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint(
              '[BackendManager] Backend startup timed out, will verify via health check');
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
  Future<void> restart({
    String? accountId,
    bool allowAttachExisting = false,
  }) async {
    debugPrint(
        '[BackendManager] Restarting for account: ${accountId ?? "default"}');
    DebugLogBuffer().add('BACKEND 重启中，切换账号: ${accountId ?? "default"}');
    await DiagnosticLogger.info('BACKEND restart account=${accountId ?? "default"}');
    await stop();
    _startAttempted = false;
    await start(
      accountId: accountId,
      allowAttachExisting: allowAttachExisting,
      forceRestart: true,
    );
  }

  /// Get the data directory path for an account (without creating it).
  Future<String> getAccountDataDir(String accountId) async {
    return _getDataDir(accountId: accountId);
  }

  /// Delete the local data directory for a specific account.
  Future<DirectoryDeleteResult> deleteAccountData(String accountId) async {
    final dir = await getAccountDataDir(accountId);
    return deleteDataDirectory(dir);
  }

  /// Stops owned backend if needed, then deletes [dirPath] with retries.
  Future<DirectoryDeleteResult> deleteDataDirectory(String dirPath) async {
    if (!LocalDataPathGuard.isSafeToDelete(dirPath)) {
      return DirectoryDeleteResult(
        success: false,
        message: '拒绝删除：路径不安全 ($dirPath)',
      );
    }

    if (_isRunning && !_ownsProcess) {
      return const DirectoryDeleteResult(
        success: false,
        message:
            '无法删除本机资料库：检测到外部 trustrag-backend 进程（例如端口 8080）仍可能占用数据库文件。\n'
            '请关闭该进程后重试，或从任务管理器结束 trustrag-backend.exe。',
      );
    }

    if (_ownsProcess || _process != null) {
      await stop();
      if (_isRunning) {
        return DirectoryDeleteResult(
          success: false,
          message:
              '无法删除本机资料库：本机后端未能完全退出，可能仍占用 $dirPath 下的 trustrag.db。\n'
              '请完全退出 TrustRAG，在任务管理器中结束 trustrag-backend.exe 后重试。',
        );
      }
    }

    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return const DirectoryDeleteResult(
        success: true,
        message: '目录不存在，无需删除',
      );
    }

    const delays = [Duration.zero, Duration(milliseconds: 300),
        Duration(milliseconds: 600), Duration(milliseconds: 1000)];
    Object? lastError;

    for (final delay in delays) {
      if (delay > Duration.zero) await Future.delayed(delay);
      try {
        await dir.delete(recursive: true);
        return DirectoryDeleteResult(
          success: true,
          message: '已删除 $dirPath',
        );
      } catch (e) {
        lastError = e;
      }
    }

    return DirectoryDeleteResult(
      success: false,
      message: _formatDeleteFailure(dirPath, lastError),
    );
  }

  static String _formatDeleteFailure(String dirPath, Object? error) {
    final buf = StringBuffer()
      ..writeln('无法删除本机资料库目录：')
      ..writeln(dirPath)
      ..writeln()
      ..writeln('可能原因：trustrag-backend.exe 或 TrustRAG.exe 仍占用 trustrag.db。')
      ..writeln('建议操作：')
      ..writeln('1. 完全退出 TrustRAG')
      ..writeln('2. 打开任务管理器，结束 trustrag-backend.exe')
      ..writeln('3. 重启电脑后再次尝试删除');
    if (error != null) {
      buf.writeln();
      buf.writeln('系统错误：$error');
    }
    return buf.toString().trim();
  }

  /// HTTP health check to verify the backend is actually responding.
  Future<bool> _healthCheck() async {
    final port = _port;
    if (port == null) return false;
    for (var i = 0; i < 3; i++) {
      if (await _healthCheckOnPort(port)) {
        debugPrint('[BackendManager] Health check passed on attempt ${i + 1}');
        return true;
      }
      debugPrint('[BackendManager] Health check attempt ${i + 1} failed');
      if (i < 2) await Future.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  Future<void> stop() async {
    if (_process != null && _ownsProcess) {
      debugPrint('[BackendManager] Stopping owned backend...');
      await DiagnosticLogger.info('BACKEND stopping owned process');
      final proc = _process!;
      proc.kill(ProcessSignal.sigterm);
      try {
        await proc.exitCode.timeout(const Duration(seconds: 10));
      } catch (_) {
        proc.kill(ProcessSignal.sigkill);
        try {
          await proc.exitCode.timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
      _process = null;
      _ownsProcess = false;
      _isRunning = false;
      _port = null;
    } else if (_isRunning && !_ownsProcess) {
      debugPrint('[BackendManager] Detaching from external backend (not killed)');
      await DiagnosticLogger.info('BACKEND detach external on port $_port');
      _isRunning = false;
      _port = null;
    }

    _startAttempted = false;
    resetLifecycle();
    _currentAccountId = null;
    _currentDataDir = null;
  }

  /// Reuse a healthy backend already listening (e.g. user-started on 8080).
  Future<bool> _tryAttachExistingBackend() async {
    for (final port in _attachPorts) {
      if (await _healthCheckOnPort(port)) {
        _port = port;
        _isRunning = true;
        _ownsProcess = false;
        debugPrint('[BackendManager] Attached to existing backend on port $port');
        DebugLogBuffer().add('BACKEND 复用已有进程 port=$port');
        await DiagnosticLogger.info('BACKEND attached existing port=$port');
        if (!_readyCompleter.isCompleted) _readyCompleter.complete();
        return true;
      }
    }
    return false;
  }

  Future<bool> _healthCheckOnPort(int port) async {
    final url = Uri.parse('http://127.0.0.1:$port/health');
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      final body = await response.transform(utf8.decoder).join();
      client.close();
      return response.statusCode == 200 && body.contains('ok');
    } catch (e) {
      debugPrint('[BackendManager] Attach health check port $port: $e');
      return false;
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

    try {
      final nativeLibDir =
          await _channel.invokeMethod<String>('getNativeLibraryDir');
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
    final hostname =
        Platform.isAndroid ? 'android-device' : Platform.localHostname;
    final seed = hostname + Platform.operatingSystem;
    return seed.hashCode.toRadixString(36).padLeft(32, 'x');
  }

  /// Provide actionable diagnostics when the backend crashes without stderr.
  static String _diagnoseExitCode(int code, String binaryPath) {
    final buf = StringBuffer();

    if (Platform.isWindows &&
        (code == -1 || code == 0xC0000135 || code == 0xC000007B)) {
      buf.writeln('可能原因: 缺少 Visual C++ 运行时库 (VCRUNTIME140.dll)');
      buf.writeln('请安装 Microsoft Visual C++ Redistributable:');
      buf.writeln('https://aka.ms/vs/17/release/vc_redist.x64.exe');
      buf.writeln('');
      buf.writeln('或者尝试在 cmd 中手动运行:');
      buf.writeln('  $binaryPath');
      buf.writeln('查看 Windows 的具体错误提示。');
    } else if (code == -1 || code == 255) {
      buf.writeln('后端进程异常终止 (信号或依赖缺失)。');
      buf.writeln('请在终端中手动运行后端查看详细错误:');
      buf.writeln('  $binaryPath');
    } else if (code == 101) {
      buf.writeln('后端发生 Rust panic，请检查日志。');
    } else {
      buf.writeln('后端异常退出，未捕获到错误输出。');
      buf.writeln('请在终端中手动运行后端查看详细错误。');
    }

    return buf.toString().trim();
  }
}