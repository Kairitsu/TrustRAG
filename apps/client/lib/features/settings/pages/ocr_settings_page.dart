import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/providers/auth_provider.dart';

class OcrSettingsPage extends ConsumerStatefulWidget {
  const OcrSettingsPage({super.key});

  @override
  ConsumerState<OcrSettingsPage> createState() => _OcrSettingsPageState();
}

class _OcrSettingsPageState extends ConsumerState<OcrSettingsPage> {
  Map<String, dynamic>? _ocrStatus;
  Map<String, dynamic>? _preflight;
  Map<String, dynamic>? _installOptions;
  Map<String, dynamic>? _ocrConfig;

  bool _loading = true;
  String? _error;

  // Install task state
  bool _installing = false;
  String? _activeTaskId;
  String _installLog = '';
  int _lastLogLine = 0;
  String? _taskStatus;
  String? _taskStage;
  String? _installMessage;
  List<String> _suggestions = [];
  bool _stallWarning = false;
  String? _logFilePath;
  String? _statusFilePath;
  String? _logsDir;
  List<int> _residualPids = [];
  List<String> _residualCommands = [];
  Timer? _pollTimer;

  // Log panel
  bool _logExpanded = true;
  bool _userScrolledUp = false;
  final ScrollController _logScrollController = ScrollController();

  // Install method selection
  String _installMode = 'auto'; // auto | manual | custom | portable
  Map<String, dynamic>? _selectedMethod;

  // Custom path controllers
  final _tesseractPathCtl = TextEditingController();
  final _tessdataDirCtl = TextEditingController();
  final _popplerBinCtl = TextEditingController();
  final _defaultLangCtl = TextEditingController(text: 'eng+chi_sim');
  bool _preferCustomPaths = false;
  bool _ocrEnabled = true;
  bool _savingConfig = false;
  Map<String, dynamic>? _verifyResult;

  static const _stages = [
    ('detecting_environment', '检测环境'),
    ('waiting_for_uac', '等待 UAC'),
    ('checking_chocolatey', '检查 Chocolatey'),
    ('executing_install', '执行安装'),
    ('waiting_for_output', '等待安装输出'),
    ('verifying_tesseract', '验证 Tesseract'),
    ('verifying_languages', '验证语言包'),
    ('verifying_poppler', '验证 Poppler'),
    ('refreshing_config', '刷新配置'),
    ('done', '完成'),
  ];

  @override
  void initState() {
    super.initState();
    _logScrollController.addListener(_onLogScroll);
    _loadAll();
  }

  void _onLogScroll() {
    if (!_logScrollController.hasClients) return;
    final max = _logScrollController.position.maxScrollExtent;
    final current = _logScrollController.offset;
    _userScrolledUp = max - current > 80;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _logScrollController.dispose();
    _tesseractPathCtl.dispose();
    _tessdataDirCtl.dispose();
    _popplerBinCtl.dispose();
    _defaultLangCtl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.dio.get('/system/ocr-status'),
        api.dio.get('/system/ocr-preflight'),
        api.dio.get('/system/ocr-install-options'),
        api.dio.get('/system/ocr-config'),
      ]);
      if (!mounted) return;
      setState(() {
        _ocrStatus = results[0].data as Map<String, dynamic>;
        _preflight = results[1].data as Map<String, dynamic>;
        _installOptions = results[2].data as Map<String, dynamic>;
        _ocrConfig = results[3].data as Map<String, dynamic>;
        _applyConfigToFields(_ocrConfig!);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _applyConfigToFields(Map<String, dynamic> cfg) {
    _tesseractPathCtl.text = cfg['tesseract_path']?.toString() ?? '';
    _tessdataDirCtl.text = cfg['tessdata_dir']?.toString() ?? '';
    _popplerBinCtl.text = cfg['poppler_bin_dir']?.toString() ?? '';
    _defaultLangCtl.text = cfg['default_language']?.toString() ?? 'eng+chi_sim';
    _preferCustomPaths = cfg['prefer_custom_paths'] == true;
    _ocrEnabled = cfg['ocr_enabled'] != false;
  }

  Future<void> _saveCustomPaths() async {
    setState(() => _savingConfig = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post('/system/ocr-config/paths', data: {
        'tesseract_path': _tesseractPathCtl.text.trim(),
        'tessdata_dir': _tessdataDirCtl.text.trim(),
        'poppler_bin_dir': _popplerBinCtl.text.trim(),
        'default_language': _defaultLangCtl.text.trim(),
        'prefer_custom_paths': _preferCustomPaths,
        'ocr_enabled': _ocrEnabled,
      });
      if (!mounted) return;
      final data = resp.data as Map<String, dynamic>;
      setState(() {
        _ocrConfig = data['config'] as Map<String, dynamic>?;
        _verifyResult = data['verification'] as Map<String, dynamic>?;
        _savingConfig = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message']?.toString() ?? '配置已保存')),
      );
      await _loadAll();
    } catch (e) {
      if (mounted) {
        setState(() => _savingConfig = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _verifyOcr() async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post('/system/ocr-verify');
      if (!mounted) return;
      setState(() {
        _verifyResult = resp.data as Map<String, dynamic>?;
      });
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('验证失败: $e')),
        );
      }
    }
  }

  Future<void> _startInstall() async {
    if (_selectedMethod == null && _installMode == 'auto') return;

    setState(() {
      _installing = true;
      _installLog = '';
      _lastLogLine = 0;
      _taskStatus = null;
      _taskStage = null;
      _installMessage = null;
      _suggestions = [];
      _stallWarning = false;
      _residualPids = [];
      _residualCommands = [];
      _logExpanded = true;
      _userScrolledUp = false;
    });

    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post('/system/ocr-install/start', data: {
        'engine': _selectedMethod?['engine'] ?? 'tesseract',
        'package_manager': _selectedMethod?['package_manager'] ?? 'choco',
      });
      final data = resp.data as Map<String, dynamic>;
      final taskId = data['task_id'] as String?;
      if (taskId == null) {
        setState(() { _installing = false; _installMessage = '后端未返回 task_id'; });
        return;
      }
      setState(() {
        _activeTaskId = taskId;
        _logFilePath = data['log_file_path']?.toString();
        _logsDir = data['logs_dir']?.toString();
        _taskStatus = data['status']?.toString() ?? 'running';
      });
      _pollTimer?.cancel();
      _pollStatus(taskId);
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _pollStatus(taskId),
      );
    } on DioException catch (e) {
      setState(() {
        _installing = false;
        _installLog = e.message ?? e.toString();
      });
    }
  }

  Future<void> _pollStatus(String taskId) async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get(
        '/system/ocr-install/status/$taskId',
        queryParameters: {'since_line': _lastLogLine},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );
      final data = resp.data as Map<String, dynamic>;
      final status = data['status']?.toString() ?? '';
      final stage = data['stage']?.toString() ?? '';
      final newLines = (data['new_lines'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final totalLines = data['total_lines'] as int? ?? _lastLogLine;

      if (!mounted) return;
      setState(() {
        if (newLines.isNotEmpty) {
          _installLog += ((_installLog.isNotEmpty ? '\n' : '') + newLines.join('\n'));
        }
        _lastLogLine = totalLines;
        _taskStatus = status;
        _taskStage = stage;
        _installMessage = data['message']?.toString();
        _logFilePath = data['log_file_path']?.toString() ?? _logFilePath;
        _statusFilePath = data['status_file_path']?.toString();
        _logsDir = data['logs_dir']?.toString() ?? _logsDir;
        _stallWarning = data['stall_warning'] == true;
        _suggestions = (data['suggestions'] as List?)?.map((e) => e.toString()).toList() ?? [];
        _residualPids = (data['residual_pids'] as List?)?.map((e) => e as int).toList() ?? [];
        _residualCommands = (data['residual_command_lines'] as List?)?.map((e) => e.toString()).toList() ?? [];

        final terminal = {
          'success', 'failed', 'cancelled', 'cancel_failed',
          'elevation_cancelled', 'timeout',
        };
        if (terminal.contains(status)) {
          _pollTimer?.cancel();
          _pollTimer = null;
          _installing = false;
          if (status == 'failed') _logExpanded = true;
          if (status == 'success') _verifyOcr();
        } else if (status == 'cancelling') {
          _installing = true;
        }
      });
      if (!_userScrolledUp) _scrollLogToBottom();
    } catch (_) {}
  }

  Future<void> _cancelInstall() async {
    final taskId = _activeTaskId;
    if (taskId == null) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post(
        '/system/ocr-install/cancel/$taskId',
        options: Options(receiveTimeout: const Duration(seconds: 2)),
      );
      if (mounted) {
        setState(() {
          _taskStatus = 'cancelling';
          _installMessage = '正在取消安装...';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('取消请求失败: $e')),
        );
      }
    }
  }

  void _scrollLogToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients && !_userScrolledUp) {
        _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _pickFile(TextEditingController ctl, {bool directory = false}) async {
    if (kIsWeb) return;
    if (directory) {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path != null) ctl.text = path;
    } else {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        ctl.text = result.files.single.path!;
      }
    }
    setState(() {});
  }

  Future<void> _openPath(String? path) async {
    if (path == null || path.isEmpty) return;
    final uri = Uri.file(path);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openLogsDir() async {
    final dir = _logsDir;
    if (dir == null) return;
    final uri = Uri.directory(dir);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR 组件管理'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll, tooltip: '刷新'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('加载失败: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildStatusBanner(),
                    const SizedBox(height: 20),
                    _buildSectionTitle('环境检测'),
                    _buildPreflightTable(),
                    const SizedBox(height: 20),
                    _buildSectionTitle('安装方式'),
                    _buildInstallMethods(),
                    const SizedBox(height: 20),
                    _buildSectionTitle('安装任务'),
                    _buildInstallTask(),
                    const SizedBox(height: 20),
                    _buildSectionTitle('验证'),
                    _buildVerification(),
                  ],
                ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStatusBanner() {
    final overall = _ocrStatus?['overall_status']?.toString() ?? 'not_installed';
    final tessPath = _ocrStatus?['tesseract_path']?.toString();
    final popplerPath = _ocrStatus?['poppler_path']?.toString();
    final recommendation = _ocrStatus?['recommendation']?.toString() ?? '';

    Color color;
    IconData icon;
    String title;
    switch (overall) {
      case 'available':
        color = Colors.green; icon = Icons.check_circle; title = 'OCR 可用';
        break;
      case 'partial_tesseract':
        color = Colors.orange; icon = Icons.warning_amber; title = '部分可用（缺 Poppler）';
        break;
      case 'partial_poppler':
        color = Colors.orange; icon = Icons.warning_amber; title = '部分可用（缺 Tesseract）';
        break;
      case 'config_error':
        color = Colors.red; icon = Icons.error; title = '配置错误';
        break;
      case 'partial':
        color = Colors.orange; icon = Icons.warning_amber; title = '部分可用';
        break;
      default:
        color = Colors.orange; icon = Icons.warning_amber; title = '未安装';
    }

    return Card(
      color: color.withAlpha(25),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color.withAlpha(200)))),
            ]),
            const SizedBox(height: 8),
            Text(recommendation, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            if (tessPath != null) ...[
              const SizedBox(height: 4),
              Text('Tesseract: $tessPath', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            ],
            if (popplerPath != null) ...[
              const SizedBox(height: 2),
              Text('Poppler: $popplerPath', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreflightTable() {
    final items = (_preflight?['items'] as List?) ?? [];
    final isAdmin = _preflight?['is_admin'] == true;
    final osName = _preflight?['os_name'] ?? _preflight?['os_version'] ?? '';
    final logsDir = _preflight?['logs_dir']?.toString() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('系统: $osName  |  管理员: ${isAdmin ? "是" : "否"}  |  日志: $logsDir',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            ...items.map((item) {
              final passed = item['passed'] == true;
              return ListTile(
                dense: true,
                leading: Icon(passed ? Icons.check_circle : Icons.cancel,
                    color: passed ? Colors.green : Colors.orange, size: 18),
                title: Text(item['display_name']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  [item['detail'], if (item['suggestion'] != null) '建议: ${item['suggestion']}']
                      .whereType<String>()
                      .join('\n'),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                isThreeLine: item['suggestion'] != null,
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重新检测'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstallMethods() {
    final methods = (_installOptions?['methods'] as List?) ?? [];
    final isAdmin = _preflight?['is_admin'] == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'auto', label: Text('自动安装'), icon: Icon(Icons.download)),
                ButtonSegment(value: 'manual', label: Text('手动安装'), icon: Icon(Icons.terminal)),
                ButtonSegment(value: 'custom', label: Text('已有路径'), icon: Icon(Icons.folder_open)),
                ButtonSegment(value: 'portable', label: Text('便携组件'), icon: Icon(Icons.archive)),
              ],
              selected: {_installMode},
              onSelectionChanged: (s) => setState(() => _installMode = s.first),
            ),
            const SizedBox(height: 12),
            if (_installMode == 'auto') ...[
              if (!isAdmin &&
                  !kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.windows)
                Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      '自动安装需要管理员权限。点击「开始自动安装」后 Windows 将弹出 UAC 确认窗口。\n'
                      '若 UAC 未弹出，请以管理员身份运行 TrustRAG 或使用「已有路径」方式。',
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                    ),
                  ),
                ),
              ...methods.map((m) {
                final isSelected = _selectedMethod == m;
                return ListTile(
                  selected: isSelected,
                  title: Text('${m['engine']} (via ${m['package_manager']})'),
                  subtitle: Text(m['description']?.toString() ?? ''),
                  trailing: m['needs_sudo'] == true ? const Chip(label: Text('需管理员')) : null,
                  onTap: () => setState(() => _selectedMethod = Map<String, dynamic>.from(m)),
                );
              }),
              if (_selectedMethod != null) _commandBlock(_selectedMethod!['command']?.toString() ?? ''),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _installing ? null : _startInstall,
                icon: const Icon(Icons.play_arrow),
                label: const Text('开始自动安装'),
              ),
            ],
            if (_installMode == 'manual') ...[
              const Text('管理员 PowerShell 命令（可复制）:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              _commandBlock('choco install tesseract poppler -y --no-progress'),
              const SizedBox(height: 8),
              const Text('验证命令:', style: TextStyle(fontWeight: FontWeight.w600)),
              _commandBlock('tesseract --version\ntesseract --list-langs\npdftoppm -v\npdfinfo -v'),
              const SizedBox(height: 8),
              const Text('macOS: brew install tesseract tesseract-lang poppler'),
              const Text('Ubuntu: sudo apt install -y tesseract-ocr tesseract-ocr-chi-sim poppler-utils'),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _loadAll, child: const Text('安装完成后重新检测')),
            ],
            if (_installMode == 'custom') ...[
              _pathField('Tesseract 可执行文件', _tesseractPathCtl, file: true),
              _pathField('tessdata 目录', _tessdataDirCtl, directory: true),
              _pathField('Poppler bin 目录', _popplerBinCtl, directory: true),
              TextField(
                controller: _defaultLangCtl,
                decoration: const InputDecoration(labelText: '默认 OCR 语言', isDense: true),
              ),
              SwitchListTile(
                title: const Text('启用 OCR'),
                value: _ocrEnabled,
                onChanged: (v) => setState(() => _ocrEnabled = v),
              ),
              SwitchListTile(
                title: const Text('优先使用自定义路径'),
                value: _preferCustomPaths,
                onChanged: (v) => setState(() => _preferCustomPaths = v),
              ),
              FilledButton(
                onPressed: _savingConfig ? null : _saveCustomPaths,
                child: _savingConfig
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('保存并验证路径'),
              ),
            ],
            if (_installMode == 'portable') ...[
              Card(
                color: Colors.blue.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '便携 OCR 组件（ocr-runtime）架构已预留。\n'
                    '可将 Tesseract/Poppler 放到 TrustRAG 数据目录下的 ocr-runtime/，无需修改系统 PATH。\n'
                    '完整便携下载功能将在后续版本提供。目前请使用「已有路径」方式指向便携版目录。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pathField(String label, TextEditingController ctl, {bool file = false, bool directory = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctl,
              decoration: InputDecoration(labelText: label, isDense: true),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.folder_open, size: 20),
              onPressed: () => _pickFile(ctl, directory: directory || !file),
            ),
        ],
      ),
    );
  }

  Widget _buildInstallTask() {
    final stageIdx = _stages.indexWhere((s) => s.$1 == _taskStage);
    final activeIdx = stageIdx < 0 ? 0 : stageIdx;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_taskStatus != null)
              Text('任务状态: $_taskStatus', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (_installing || _taskStatus == 'cancelling')
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            if (_installing || _activeTaskId != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _stages.length,
                  separatorBuilder: (_, _) => const Icon(Icons.chevron_right, size: 16),
                  itemBuilder: (_, i) {
                    final (key, label) = _stages[i];
                    final done = i < activeIdx;
                    final active = key == _taskStage || (i == activeIdx && _installing);
                    return Chip(
                      avatar: Icon(
                        done ? Icons.check : (active ? Icons.more_horiz : Icons.circle_outlined),
                        size: 14,
                        color: done ? Colors.green : (active ? Colors.blue : Colors.grey),
                      ),
                      label: Text(label, style: const TextStyle(fontSize: 10)),
                      backgroundColor: active ? Colors.blue.shade50 : null,
                    );
                  },
                ),
              ),
            ],
            if (_installMessage != null) ...[
              const SizedBox(height: 6),
              Text(_installMessage!, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
            if (_stallWarning)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '长时间无输出：可能正在等待 UAC、网络下载或 Chocolatey 锁。',
                  style: TextStyle(fontSize: 11, color: Colors.amber.shade800),
                ),
              ),
            if (_suggestions.isNotEmpty)
              ..._suggestions.map((s) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $s', style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
                  )),
            if (_residualPids.isNotEmpty)
              Text('残留 PID: ${_residualPids.join(", ")}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            if (_residualCommands.isNotEmpty)
              ..._residualCommands.map((c) => _commandBlock(c)),
            const SizedBox(height: 8),
            _buildLogPanel(),
            if (_installing || _taskStatus == 'cancelling' || _taskStatus == 'running' || _taskStatus == 'waiting_for_uac')
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _cancelInstall,
                    icon: const Icon(Icons.stop_circle_outlined, color: Colors.red, size: 16),
                    label: const Text('取消安装', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _logExpanded = !_logExpanded),
          child: Row(
            children: [
              Icon(_logExpanded ? Icons.expand_less : Icons.expand_more, size: 20),
              const Text('  安装实时日志', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_installing) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
        if (_logFilePath != null)
          Text('日志: $_logFilePath', style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey.shade600)),
        if (_statusFilePath != null)
          Text('状态: $_statusFilePath', style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey.shade600)),
        if (_logExpanded) ...[
          Container(
            width: double.infinity,
            height: 260,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SingleChildScrollView(
              controller: _logScrollController,
              child: SelectableText(
                _installLog.isEmpty
                    ? (_installing ? '等待安装输出...' : '暂无日志')
                    : _installLog,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white70, height: 1.4),
              ),
            ),
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: _installLog.isEmpty ? null : () {
                  Clipboard.setData(ClipboardData(text: _installLog));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日志已复制')));
                },
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('复制全部', style: TextStyle(fontSize: 11)),
              ),
              TextButton.icon(
                onPressed: () => setState(() { _installLog = ''; _lastLogLine = 0; }),
                icon: const Icon(Icons.clear, size: 14),
                label: const Text('清空显示', style: TextStyle(fontSize: 11)),
              ),
              if (_logFilePath != null)
                TextButton.icon(
                  onPressed: () => _openPath(_logFilePath),
                  icon: const Icon(Icons.description, size: 14),
                  label: const Text('打开日志', style: TextStyle(fontSize: 11)),
                ),
              if (_logsDir != null)
                TextButton.icon(
                  onPressed: _openLogsDir,
                  icon: const Icon(Icons.folder_open, size: 14),
                  label: const Text('打开目录', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildVerification() {
    final verification = _verifyResult?['verification'] as Map<String, dynamic>?;
    final items = (verification?['items'] as List?) ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (verification != null) ...[
              Text(
                verification['all_passed'] == true ? '验证通过' : '验证未全部通过',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: verification['all_passed'] == true ? Colors.green : Colors.orange,
                ),
              ),
              if (verification['path_refresh_needed'] == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('PATH 可能未刷新，请重启 TrustRAG 或手动配置路径。',
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade800)),
                ),
              ...items.map((item) {
                final ok = item['passed'] == true;
                return ListTile(
                  dense: true,
                  leading: Icon(ok ? Icons.check : Icons.close, color: ok ? Colors.green : Colors.red, size: 18),
                  title: Text(item['name']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                  subtitle: Text(item['detail']?.toString() ?? '', style: const TextStyle(fontSize: 11)),
                );
              }),
            ] else
              const Text('点击「重新验证」检查 Tesseract 和 Poppler 是否可用。'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _verifyOcr,
              icon: const Icon(Icons.verified, size: 16),
              label: const Text('重新验证'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _commandBlock(String command) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(command, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey.shade800)),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: command));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
            },
            child: Icon(Icons.copy, size: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}