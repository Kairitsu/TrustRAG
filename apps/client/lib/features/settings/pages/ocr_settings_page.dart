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
  Map<String, dynamic>? _status;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/system/ocr-status');
      if (mounted) {
        setState(() {
          _status = resp.data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
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
            onPressed: _loadStatus,
            tooltip: '刷新状态',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                      const SizedBox(height: 12),
                      Text('加载失败: $_error',
                          style: TextStyle(color: Colors.grey.shade600)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _loadStatus, child: const Text('重试')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildStatusBanner(theme),
                    const SizedBox(height: 16),
                    _buildToolCards(theme),
                    const SizedBox(height: 16),
                    _buildInstallGuide(theme),
                  ],
                ),
    );
  }

  Widget _buildStatusBanner(ThemeData theme) {
    final anyAvailable = _status?['any_available'] == true;
    return Card(
      color: anyAvailable ? Colors.green.shade50 : Colors.orange.shade50,
      child: ListTile(
        leading: Icon(
          anyAvailable ? Icons.check_circle : Icons.warning_amber,
          color: anyAvailable ? Colors.green : Colors.orange,
          size: 32,
        ),
        title: Text(
          anyAvailable ? 'OCR 组件已就绪' : '未检测到 OCR 组件',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: anyAvailable ? Colors.green.shade800 : Colors.orange.shade800,
          ),
        ),
        subtitle: Text(
          anyAvailable
              ? '可以处理扫描版 PDF 文档'
              : '安装 OCR 组件后可处理扫描版 PDF 文档',
          style: TextStyle(
            color: anyAvailable ? Colors.green.shade600 : Colors.orange.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildToolCards(ThemeData theme) {
    final tools = (_status?['tools'] as List?) ?? [];
    if (tools.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('已检测的 OCR 工具',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...tools.map((t) {
          final available = t['available'] == true;
          final name = t['name'] as String? ?? '';
          final version = t['version'] as String?;
          final displayName = _toolDisplayName(name);

          return Card(
            child: ListTile(
              leading: Icon(
                available ? Icons.check_circle : Icons.cancel,
                color: available ? Colors.green : Colors.grey,
              ),
              title: Text(displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: available
                  ? Text('版本: ${version ?? "未知"}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
                  : Text('未安装',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              trailing: available
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: const Text('可用',
                          style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
                    )
                  : null,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildInstallGuide(ThemeData theme) {
    final recommendation = _status?['recommendation'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('安装指南',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recommendation, style: const TextStyle(fontSize: 13, height: 1.6)),
                const SizedBox(height: 16),
                const Text('推荐: Tesseract OCR',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                _installStep('macOS', 'brew install tesseract tesseract-lang'),
                const SizedBox(height: 6),
                _installStep('Ubuntu/Debian', 'sudo apt install tesseract-ocr tesseract-ocr-chi-sim'),
                const SizedBox(height: 6),
                _installStep('Windows', '从 GitHub 下载安装包:\nhttps://github.com/UB-Mannheim/tesseract/wiki'),
                const SizedBox(height: 16),
                const Text('备选: PaddleOCR',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                _installStep('所有平台', 'pip install paddleocr paddlepaddle'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _loadStatus,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('安装后重新检测'),
                ),
              ],
            ),
          ),
        ),
      ],
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
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(command,
                style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey.shade800)),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: command));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
              );
            },
            child: Icon(Icons.copy, size: 16, color: Colors.grey.shade400),
          ),
        ],
      ),
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
}
