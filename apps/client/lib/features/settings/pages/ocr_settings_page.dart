import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';

class OcrSettingsPage extends ConsumerStatefulWidget {
  const OcrSettingsPage({super.key});

  @override
  ConsumerState<OcrSettingsPage> createState() => _OcrSettingsPageState();
}

class _OcrSettingsPageState extends ConsumerState<OcrSettingsPage> {
  int _currentStep = 0;

  Map<String, dynamic>? _ocrStatus;
  Map<String, dynamic>? _installOptions;
  bool _loadingStatus = true;
  bool _loadingOptions = false;
  String? _error;

  String? _selectedEngine;
  Map<String, dynamic>? _selectedMethod;

  bool _installing = false;
  String _installLog = '';
  bool? _installSuccess;

  bool _verifying = false;
  bool? _verifySuccess;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await _loadStatus();
    if (_ocrStatus != null && _ocrStatus!['any_available'] == true) {
      _currentStep = 0;
    }
    await _loadInstallOptions();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loadingStatus = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/system/ocr-status');
      if (mounted) {
        setState(() {
          _ocrStatus = resp.data;
          _loadingStatus = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loadingStatus = false;
        });
      }
    }
  }

  Future<void> _loadInstallOptions() async {
    setState(() => _loadingOptions = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/system/ocr-install-options');
      if (mounted) {
        setState(() {
          _installOptions = resp.data;
          _loadingOptions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingOptions = false);
      }
    }
  }

  Future<void> _startInstall() async {
    if (_selectedMethod == null) return;
    setState(() {
      _installing = true;
      _installLog = '';
      _installSuccess = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post(
        '/system/ocr-install',
        data: {
          'engine': _selectedMethod!['engine'],
          'package_manager': _selectedMethod!['package_manager'].toString(),
        },
        options: Options(receiveTimeout: const Duration(minutes: 5)),
      );
      if (mounted) {
        final data = resp.data as Map<String, dynamic>;
        setState(() {
          _installing = false;
          _installSuccess = data['success'] == true;
          _installLog = data['output']?.toString() ?? '';
          if (_installSuccess == true) {
            _currentStep = 3;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _installing = false;
          _installSuccess = false;
          _installLog = e.toString();
        });
      }
    }
  }

  Future<void> _verifyInstall() async {
    setState(() {
      _verifying = true;
      _verifySuccess = null;
    });
    await _loadStatus();
    if (mounted) {
      setState(() {
        _verifying = false;
        _verifySuccess = _ocrStatus?['any_available'] == true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR 组件管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
            tooltip: '刷新状态',
          ),
        ],
      ),
      body: _loadingStatus
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildStatusBanner(theme),
                    const SizedBox(height: 20),
                    _buildWizardStepper(theme),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Text('加载失败: $_error',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _loadAll, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(ThemeData theme) {
    final anyAvailable = _ocrStatus?['any_available'] == true;
    final tools = (_ocrStatus?['tools'] as List?) ?? [];
    final installed = tools.where((t) => t['available'] == true).toList();

    return Card(
      color: anyAvailable ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              anyAvailable ? Icons.check_circle : Icons.warning_amber,
              color: anyAvailable ? Colors.green : Colors.orange,
              size: 36,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    anyAvailable ? 'OCR 组件已就绪' : '未检测到 OCR 组件',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: anyAvailable
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (anyAvailable)
                    Text(
                      '已安装: ${installed.map((t) => _toolDisplayName(t['name'] ?? '')).join(', ')}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.green.shade600),
                    )
                  else
                    Text(
                      '按照下方向导安装 OCR 组件',
                      style: TextStyle(
                          fontSize: 13, color: Colors.orange.shade600),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWizardStepper(ThemeData theme) {
    return Stepper(
      currentStep: _currentStep,
      onStepTapped: (step) {
        if (step <= _currentStep || _ocrStatus?['any_available'] == true) {
          setState(() => _currentStep = step);
        }
      },
      controlsBuilder: (context, details) => const SizedBox.shrink(),
      steps: [
        Step(
          title: const Text('检测当前状态'),
          subtitle: _ocrStatus != null
              ? Text(_ocrStatus!['any_available'] == true
                  ? '已检测到 OCR 工具'
                  : '未检测到 OCR 工具')
              : null,
          content: _buildStep1DetectStatus(theme),
          isActive: _currentStep >= 0,
          state: _ocrStatus?['any_available'] == true
              ? StepState.complete
              : (_currentStep > 0 ? StepState.complete : StepState.indexed),
        ),
        Step(
          title: const Text('选择 OCR 引擎'),
          subtitle: _selectedEngine != null
              ? Text(_toolDisplayName(_selectedEngine!))
              : null,
          content: _buildStep2SelectEngine(theme),
          isActive: _currentStep >= 1,
          state: _selectedMethod != null && _currentStep > 1
              ? StepState.complete
              : StepState.indexed,
        ),
        Step(
          title: const Text('安装'),
          subtitle: _installSuccess == true
              ? const Text('安装成功')
              : (_installing ? const Text('安装中...') : null),
          content: _buildStep3Install(theme),
          isActive: _currentStep >= 2,
          state: _installSuccess == true
              ? StepState.complete
              : StepState.indexed,
        ),
        Step(
          title: const Text('验证安装'),
          subtitle: _verifySuccess == true
              ? const Text('验证通过')
              : null,
          content: _buildStep4Verify(theme),
          isActive: _currentStep >= 3,
          state: _verifySuccess == true
              ? StepState.complete
              : StepState.indexed,
        ),
      ],
    );
  }

  // Step 1: Detect current status
  Widget _buildStep1DetectStatus(ThemeData theme) {
    final tools = (_ocrStatus?['tools'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...tools.map((t) {
          final available = t['available'] == true;
          final name = t['name'] as String? ?? '';
          final version = t['version'] as String?;
          final path = t['path'] as String?;
          return Card(
            child: ListTile(
              leading: Icon(
                available ? Icons.check_circle : Icons.cancel,
                color: available ? Colors.green : Colors.grey,
              ),
              title: Text(_toolDisplayName(name),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: available
                  ? Text('版本: ${version ?? "未知"}${path != null ? '\n路径: $path' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
                  : Text('未安装',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              trailing: available
                  ? _chip('可用', Colors.green)
                  : _chip('未安装', Colors.grey),
            ),
          );
        }),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _loadStatus,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重新检测'),
            ),
            const SizedBox(width: 12),
            if (_ocrStatus?['any_available'] != true)
              FilledButton(
                onPressed: () => setState(() => _currentStep = 1),
                child: const Text('开始安装'),
              ),
          ],
        ),
      ],
    );
  }

  // Step 2: Select engine and install method
  Widget _buildStep2SelectEngine(ThemeData theme) {
    if (_loadingOptions) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final methods = (_installOptions?['methods'] as List?) ?? [];
    final platform = _installOptions?['platform'] as String? ?? 'unknown';
    final managers = (_installOptions?['available_package_managers'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.computer, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '平台: ${_platformDisplayName(platform)}  |  '
                    '包管理器: ${managers.map((m) => m.toString()).join(", ")}',
                    style: TextStyle(fontSize: 13, color: Colors.blue.shade800),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (methods.isEmpty)
          Card(
            color: Colors.red.shade50,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('未找到可用的自动安装方式，请参考下方手动安装指南。'),
            ),
          )
        else
          ...methods.map((m) {
            final engine = m['engine'] as String? ?? '';
            final pm = m['package_manager'] as String? ?? '';
            final command = m['command'] as String? ?? '';
            final desc = m['description'] as String? ?? '';
            final needsSudo = m['needs_sudo'] == true;
            final isSelected = _selectedMethod == m;

            return Card(
              elevation: isSelected ? 2 : 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: isSelected ? theme.colorScheme.primary : Colors.grey.shade300,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() {
                  _selectedEngine = engine;
                  _selectedMethod = Map<String, dynamic>.from(m);
                }),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Radio<String>(
                            value: '$engine-$pm',
                            groupValue: _selectedMethod != null
                                ? '${_selectedMethod!['engine']}-${_selectedMethod!['package_manager']}'
                                : null,
                            onChanged: (_) => setState(() {
                              _selectedEngine = engine;
                              _selectedMethod = Map<String, dynamic>.from(m);
                            }),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_toolDisplayName(engine)} (via $pm)',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          if (needsSudo)
                            Tooltip(
                              message: '需要管理员权限',
                              child: Chip(
                                label: const Text('sudo', style: TextStyle(fontSize: 10)),
                                backgroundColor: Colors.amber.shade100,
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _commandBlock(command),
                    ],
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 12),
        _buildManualInstallGuide(theme),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _currentStep = 0),
              child: const Text('上一步'),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _selectedMethod != null
                  ? () => setState(() => _currentStep = 2)
                  : null,
              child: const Text('下一步'),
            ),
          ],
        ),
      ],
    );
  }

  // Step 3: Install
  Widget _buildStep3Install(ThemeData theme) {
    if (_selectedMethod == null) {
      return const Text('请先选择安装方式');
    }
    final engine = _selectedMethod!['engine'] ?? '';
    final pm = _selectedMethod!['package_manager'] ?? '';
    final command = _selectedMethod!['command'] ?? '';
    final needsSudo = _selectedMethod!['needs_sudo'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('即将安装: ${_toolDisplayName(engine)} (via $pm)',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _commandBlock(command),
                if (needsSudo) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.warning_amber, size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 6),
                      Text('此操作需要管理员权限 (sudo)',
                          style: TextStyle(fontSize: 12, color: Colors.amber.shade700)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_installing)
          const Column(
            children: [
              LinearProgressIndicator(),
              SizedBox(height: 8),
              Text('正在安装，请稍候...'),
            ],
          )
        else if (_installSuccess == true)
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('安装成功！')),
                ],
              ),
            ),
          )
        else if (_installSuccess == false)
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('安装失败，请查看日志或手动安装。')),
                ],
              ),
            ),
          ),
        if (_installLog.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            title: const Text('安装日志', style: TextStyle(fontSize: 13)),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  _installLog,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton(
              onPressed: _installing ? null : () => setState(() => _currentStep = 1),
              child: const Text('上一步'),
            ),
            const SizedBox(width: 12),
            if (_installSuccess != true)
              FilledButton(
                onPressed: _installing ? null : _startInstall,
                child: Text(_installSuccess == false ? '重试安装' : '开始安装'),
              ),
            if (_installSuccess == true) ...[
              FilledButton(
                onPressed: () => setState(() => _currentStep = 3),
                child: const Text('验证安装'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // Step 4: Verify
  Widget _buildStep4Verify(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('检查 OCR 工具是否已正确安装并可以使用。'),
        const SizedBox(height: 12),
        if (_verifying)
          const Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('正在验证...'),
            ],
          )
        else if (_verifySuccess == true)
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 48),
                  const SizedBox(height: 8),
                  const Text('安装验证通过！',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('OCR 组件已就绪，可以处理扫描版 PDF 文档。'),
                ],
              ),
            ),
          )
        else if (_verifySuccess == false)
          Card(
            color: Colors.red.shade50,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(Icons.error, color: Colors.red, size: 48),
                  SizedBox(height: 8),
                  Text('验证失败',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 4),
                  Text('未检测到 OCR 工具。请确认安装是否成功，或尝试重新安装。'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _currentStep = 2),
              child: const Text('返回安装'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _verifying ? null : _verifyInstall,
              icon: const Icon(Icons.verified, size: 16),
              label: Text(_verifySuccess != null ? '重新验证' : '开始验证'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildManualInstallGuide(ThemeData theme) {
    return ExpansionTile(
      title: const Text('手动安装指南', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tesseract OCR (推荐)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                _installStep('macOS', 'brew install tesseract tesseract-lang'),
                const SizedBox(height: 6),
                _installStep(
                    'Ubuntu/Debian', 'sudo apt install tesseract-ocr tesseract-ocr-chi-sim'),
                const SizedBox(height: 6),
                _installStep(
                    'Windows', '从 GitHub 下载安装包:\nhttps://github.com/UB-Mannheim/tesseract/wiki'),
                const SizedBox(height: 16),
                const Text('PaddleOCR (中文效果好)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                _installStep('所有平台', 'pip install paddleocr paddlepaddle'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _commandBlock(String command) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              command,
              style: TextStyle(
                  fontSize: 12, fontFamily: 'monospace', color: Colors.grey.shade800),
            ),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: command));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
              );
            },
            child: Icon(Icons.copy, size: 16, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _installStep(String platform, String command) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(platform,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade700)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(command,
                style: TextStyle(
                    fontSize: 12, fontFamily: 'monospace', color: Colors.grey.shade800)),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: command));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
              );
            },
            child: Icon(Icons.copy, size: 16, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(76)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  String _toolDisplayName(String name) {
    switch (name) {
      case 'tesseract':
        return 'Tesseract OCR';
      case 'paddleocr':
        return 'PaddleOCR';
      default:
        return name;
    }
  }

  String _platformDisplayName(String platform) {
    switch (platform) {
      case 'linux':
        return 'Linux';
      case 'mac_os':
        return 'macOS';
      case 'windows':
        return 'Windows';
      default:
        return platform;
    }
  }
}
