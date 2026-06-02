import 'dart:async';

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
  String? _activeTaskId;
  Timer? _pollTimer;
  int _lastLogLine = 0;

  bool _verifying = false;
  bool? _verifySuccess;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
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

  String? _installMessage;
  int? _installExitCode;

  Future<void> _startInstall() async {
    if (_selectedMethod == null) return;
    setState(() {
      _installing = true;
      _installLog = '';
      _installSuccess = null;
      _installMessage = null;
      _installExitCode = null;
      _activeTaskId = null;
      _lastLogLine = 0;
    });
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post(
        '/system/ocr-install/start',
        data: {
          'engine': _selectedMethod!['engine'],
          'package_manager': _selectedMethod!['package_manager'].toString(),
        },
      );
      final data = resp.data as Map<String, dynamic>;
      final taskId = data['task_id'] as String?;

      if (taskId == null) {
        if (mounted) {
          setState(() {
            _installing = false;
            _installSuccess = false;
            _installMessage = '后端未返回 task_id';
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _activeTaskId = taskId;
        });
      }

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollStatus(taskId));
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _installing = false;
          _installSuccess = false;
          _installLog = e.message ?? e.toString();
          _installMessage = '安装请求异常';
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

  Future<void> _pollStatus(String taskId) async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get(
        '/system/ocr-install/status/$taskId',
        queryParameters: {'since_line': _lastLogLine},
      );
      final data = resp.data as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';
      final newLines = (data['new_lines'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final totalLines = data['total_lines'] as int? ?? _lastLogLine;

      if (!mounted) return;

      setState(() {
        if (newLines.isNotEmpty) {
          _installLog += ((_installLog.isNotEmpty ? '\n' : '') + newLines.join('\n'));
        }
        _lastLogLine = totalLines;

        if (status == 'completed' || status == 'failed' || status == 'cancelled') {
          _pollTimer?.cancel();
          _pollTimer = null;
          _installing = false;
          _installSuccess = status == 'completed';
          _installMessage = data['message']?.toString();
          _installExitCode = data['exit_code'] as int?;
          if (_installSuccess == true) {
            _currentStep = 3;
          }
        }
      });
    } catch (_) {
      // polling error, will retry on next interval
    }
  }

  Future<void> _cancelInstall() async {
    final taskId = _activeTaskId;
    if (taskId == null) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('/system/ocr-install/cancel/$taskId');
      _pollTimer?.cancel();
      _pollTimer = null;
      if (mounted) {
        setState(() {
          _installing = false;
          _installSuccess = false;
          _installMessage = '安装已被取消。';
          _installLog += '\n--- 安装已取消 ---';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('取消失败: $e')),
        );
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
    final pdfReady = _ocrStatus?['pdf_ocr_ready'] == true;
    final recommendation = _ocrStatus?['recommendation'] as String? ?? '';

    final Color bannerColor;
    final IconData bannerIcon;
    final String bannerTitle;
    if (pdfReady) {
      bannerColor = Colors.green;
      bannerIcon = Icons.check_circle;
      bannerTitle = 'OCR 组件已就绪，可处理扫描版 PDF';
    } else if (anyAvailable) {
      bannerColor = Colors.orange;
      bannerIcon = Icons.warning_amber;
      bannerTitle = 'OCR 部分就绪，扫描版 PDF 可能不可用';
    } else {
      bannerColor = Colors.orange;
      bannerIcon = Icons.warning_amber;
      bannerTitle = '未检测到 OCR 组件';
    }

    return Card(
      color: bannerColor.withAlpha(25),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(bannerIcon, color: bannerColor, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bannerTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16,
                      color: bannerColor.withAlpha(200),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(recommendation,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
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

  Widget _buildStep1DetectStatus(ThemeData theme) {
    final tools = (_ocrStatus?['tools'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...tools.map((t) {
          final available = t['available'] == true;
          final displayName = t['display_name'] as String? ?? t['name'] as String? ?? '';
          final version = t['version'] as String?;
          final path = t['path'] as String?;
          final missingHint = t['missing_hint'] as String?;
          final languages = (t['languages'] as List?)?.map((e) => e.toString()).toList();

          final subtitleParts = <String>[];
          if (available) {
            if (version != null && version.isNotEmpty) subtitleParts.add('版本: $version');
            if (path != null) subtitleParts.add('路径: $path');
            if (languages != null && languages.isNotEmpty) {
              subtitleParts.add('语言包: ${languages.join(", ")}');
            }
          } else if (missingHint != null) {
            subtitleParts.add(missingHint);
          } else {
            subtitleParts.add('未安装');
          }

          return Card(
            child: ListTile(
              leading: Icon(
                available ? Icons.check_circle : Icons.cancel,
                color: available ? Colors.green : Colors.grey,
              ),
              title: Text(displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(subtitleParts.join('\n'),
                  style: TextStyle(fontSize: 12, color: available ? Colors.grey.shade600 : Colors.orange.shade700)),
              isThreeLine: subtitleParts.length > 1,
              trailing: available
                  ? _chip('可用', Colors.green)
                  : _chip('缺失', Colors.orange),
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
            if (_ocrStatus?['pdf_ocr_ready'] != true)
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
                  Card(
                    color: Colors.amber.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.admin_panel_settings, size: 20, color: Colors.amber.shade700),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            '此操作需要管理员权限。Windows 下会弹出 UAC 权限确认窗口，请点击"是"以继续安装。\n'
                            '如果安装卡住，可能是权限不足。建议手动以管理员身份运行命令。',
                            style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
                          )),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_installing)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('正在安装，实时日志如下...')),
                  OutlinedButton.icon(
                    onPressed: _cancelInstall,
                    icon: const Icon(Icons.stop_circle_outlined, size: 16, color: Colors.red),
                    label: const Text('取消安装', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red.shade200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
              ),
              if (_installLog.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 250),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: SelectableText(
                      _installLog,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          )
        else if (_installSuccess == true)
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_installMessage ?? '安装成功！')),
                  ]),
                ],
              ),
            ),
          )
        else if (_installSuccess == false)
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_installMessage ?? '安装失败，请查看日志或手动安装。')),
                  ]),
                  if (_installExitCode != null) ...[
                    const SizedBox(height: 4),
                    Text('退出码: $_installExitCode',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade300, fontFamily: 'monospace')),
                  ],
                ],
              ),
            ),
          ),
        if (_installLog.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            title: const Text('安装日志', style: TextStyle(fontSize: 13)),
            initiallyExpanded: _installSuccess == false,
            children: [
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 300),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _installLog,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _installLog));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('日志已复制到剪贴板'), duration: Duration(seconds: 1)),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('复制日志', style: TextStyle(fontSize: 12)),
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

  Widget _buildStep4Verify(ThemeData theme) {
    final pdfReady = _ocrStatus?['pdf_ocr_ready'] == true;
    final tools = (_ocrStatus?['tools'] as List?) ?? [];

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                color: pdfReady ? Colors.green.shade50 : Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        pdfReady ? Icons.check_circle : Icons.warning_amber,
                        color: pdfReady ? Colors.green : Colors.orange,
                        size: 48,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        pdfReady ? '安装验证通过！' : 'OCR 部分可用',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(pdfReady
                        ? 'OCR 组件已就绪，可以处理扫描版 PDF 文档。'
                        : _ocrStatus?['recommendation'] as String? ?? '部分依赖缺失，请查看下方详情。',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...tools.map((t) {
                final ok = t['available'] == true;
                final name = t['display_name'] as String? ?? t['name'] as String? ?? '';
                final hint = t['missing_hint'] as String?;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Icon(ok ? Icons.check : Icons.close,
                        size: 16, color: ok ? Colors.green : Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      ok ? name : '$name — ${hint ?? "缺失"}',
                      style: TextStyle(
                        fontSize: 13,
                        color: ok ? Colors.grey.shade700 : Colors.red.shade700,
                      ),
                    )),
                  ]),
                );
              }),
            ],
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
