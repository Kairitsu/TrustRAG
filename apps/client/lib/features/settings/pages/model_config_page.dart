import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ai_icon_helper.dart';
import '../providers/model_config_provider.dart';
import '../providers/embedding_config_provider.dart';

class ModelConfigPage extends ConsumerStatefulWidget {
  const ModelConfigPage({super.key});

  @override
  ConsumerState<ModelConfigPage> createState() => _ModelConfigPageState();
}

class _ModelConfigPageState extends ConsumerState<ModelConfigPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    ref.read(modelConfigProvider.notifier).loadConfigs();
    ref.read(embeddingConfigProvider.notifier).load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('模型配置'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.smart_toy), text: 'LLM 模型'),
            Tab(icon: Icon(Icons.data_array), text: '嵌入模型'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            _showLlmDialog();
          } else {
            _showEmbeddingDialog();
          }
        },
        child: const Icon(Icons.add),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLlmTab(),
          _buildEmbeddingTab(),
        ],
      ),
    );
  }

  // ── LLM Tab ──

  Widget _buildLlmTab() {
    final configs = ref.watch(modelConfigProvider);
    return configs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (list) {
        if (list.isEmpty) {
          return _buildEmptyState('LLM 模型', () => _showLlmDialog());
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, i) => _buildLlmCard(list[i]),
        );
      },
    );
  }

  Widget _buildLlmCard(ModelConfig cfg) {
    return Card(
      child: ListTile(
        leading: AIIconHelper.buildProviderAvatar(
          cfg.modelName.isNotEmpty ? cfg.modelName : cfg.provider,
          radius: 20,
          isDefault: cfg.isDefault,
        ),
        title: Row(children: [
          Text(cfg.modelName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (cfg.isDefault) ...[
            const SizedBox(width: 8),
            _defaultBadge(),
          ],
        ]),
        subtitle: Text('${cfg.provider} · ${cfg.apiBaseUrl}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: '测试连接',
              onPressed: () => _testLlmConnection(cfg),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showLlmDialog(config: cfg),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () =>
                  ref.read(modelConfigProvider.notifier).deleteConfig(cfg.id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testLlmConnection(ModelConfig cfg) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('正在测试连接...'), duration: Duration(seconds: 30)),
    );
    final result = await ref
        .read(modelConfigProvider.notifier)
        .testConnectionDetailed(cfg.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final success = result['success'] == true;
      final message = result['message'] ?? '未知结果';
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ));
      } else {
        _showErrorDialog('LLM 连接测试失败', message);
      }
    }
  }

  // ── Embedding Tab ──

  Widget _buildEmbeddingTab() {
    final configs = ref.watch(embeddingConfigProvider);
    return configs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (list) {
        if (list.isEmpty) {
          return _buildEmptyState('嵌入模型', () => _showEmbeddingDialog());
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, i) => _buildEmbeddingCard(list[i]),
        );
      },
    );
  }

  Widget _buildEmbeddingCard(EmbeddingConfig cfg) {
    return Card(
      child: ListTile(
        leading: AIIconHelper.buildProviderAvatar(
          cfg.modelName.isNotEmpty ? cfg.modelName : cfg.provider,
          radius: 20,
          isDefault: cfg.isDefault,
        ),
        title: Row(children: [
          Text(cfg.modelName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (cfg.isDefault) ...[
            const SizedBox(width: 8),
            _defaultBadge(),
          ],
        ]),
        subtitle: Text(
            '${cfg.provider} · ${cfg.apiBaseUrl ?? ''} · dim: ${cfg.dimensions} · batch: ${cfg.batchSize}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: '测试连接',
              onPressed: () => _testEmbeddingConnection(cfg),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showEmbeddingDialog(config: cfg),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () =>
                  ref.read(embeddingConfigProvider.notifier).delete(cfg.id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testEmbeddingConnection(EmbeddingConfig cfg) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('正在测试嵌入连接...'),
          duration: Duration(seconds: 30)),
    );
    final result =
        await ref.read(embeddingConfigProvider.notifier).testConnection(cfg.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final success = result['success'] == true;
      final message = result['message'] ?? '未知结果';
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ));
      } else {
        _showErrorDialog('嵌入模型连接测试失败', message);
      }
    }
  }

  // ── Error Dialog ──

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  message,
                  style: TextStyle(fontSize: 13, color: Colors.red.shade900, height: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('错误信息已复制到剪贴板'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制错误信息'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // ── Shared Widgets ──

  Widget _defaultBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('默认',
          style: TextStyle(
              fontSize: 11,
              color: Colors.green,
              fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildEmptyState(String type, VoidCallback onAdd) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.model_training, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('暂无$type配置',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text('添加$type'),
          ),
        ],
      ),
    );
  }

  // ── LLM Dialog ──

  String _endpointHint(String provider) {
    switch (provider) {
      case 'openai':
        return 'https://api.openai.com/v1';
      case 'anthropic':
        return 'https://api.anthropic.com/v1';
      case 'ollama':
        return 'http://localhost:11434/v1';
      default:
        return 'https://your-api.com/v1';
    }
  }

  void _showLlmDialog({ModelConfig? config}) {
    String selectedProvider = config?.provider ?? 'openai';
    final modelCtl = TextEditingController(text: config?.modelName ?? '');
    final endpointCtl =
        TextEditingController(text: config?.apiBaseUrl ?? '');
    final apiKeyCtl = TextEditingController();
    bool isDefault = config?.isDefault ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(config == null ? '添加 LLM 模型' : '编辑 LLM 模型'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedProvider,
                  decoration: const InputDecoration(labelText: 'Provider'),
                  items: ['openai', 'anthropic', 'ollama', 'custom']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) {
                    setDialogState(() => selectedProvider = v ?? 'openai');
                    if (endpointCtl.text.isEmpty) {
                      endpointCtl.text = _endpointHint(selectedProvider);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelCtl,
                  decoration: InputDecoration(
                    labelText: '模型名称',
                    hintText: selectedProvider == 'openai'
                        ? '如 gpt-4o, gpt-4o-mini'
                        : selectedProvider == 'ollama'
                            ? '如 qwen2.5:7b'
                            : '如 claude-3-5-sonnet',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: endpointCtl,
                  decoration: InputDecoration(
                    labelText: 'API Endpoint',
                    hintText: _endpointHint(selectedProvider),
                    helperText: '填写到 /v1 即可，无需加 /chat/completions',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKeyCtl,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: config != null
                        ? '留空则不修改'
                        : selectedProvider == 'ollama'
                            ? '本地无需填写'
                            : 'sk-...',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('设为默认'),
                  contentPadding: EdgeInsets.zero,
                  value: isDefault,
                  onChanged: (v) => setDialogState(() => isDefault = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final data = <String, dynamic>{
                  'name': '${modelCtl.text} ($selectedProvider)',
                  'provider': selectedProvider,
                  'model_name': modelCtl.text,
                  'api_base_url': endpointCtl.text,
                  'is_default': isDefault,
                };
                if (apiKeyCtl.text.isNotEmpty) {
                  data['api_key'] = apiKeyCtl.text;
                }
                bool ok;
                if (config == null) {
                  ok = await ref
                      .read(modelConfigProvider.notifier)
                      .createConfig(data);
                } else {
                  ok = await ref
                      .read(modelConfigProvider.notifier)
                      .updateConfig(config.id, data);
                }
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(config == null ? '创建' : '保存'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Embedding Dialog ──

  void _showEmbeddingDialog({EmbeddingConfig? config}) {
    String selectedProvider = config?.provider ?? 'openai';
    final modelCtl = TextEditingController(text: config?.modelName ?? '');
    final endpointCtl =
        TextEditingController(text: config?.apiBaseUrl ?? '');
    final apiKeyCtl = TextEditingController();
    final dimensionsCtl = TextEditingController(
        text: config?.dimensions.toString() ?? '1536');
    final batchSizeCtl = TextEditingController(
        text: config?.batchSize.toString() ?? '10');
    bool isDefault = config?.isDefault ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(config == null ? '添加嵌入模型' : '编辑嵌入模型'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedProvider,
                  decoration: const InputDecoration(labelText: 'Provider'),
                  items: ['openai', 'ollama', 'local', 'custom']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) {
                    setDialogState(() => selectedProvider = v ?? 'openai');
                    if (endpointCtl.text.isEmpty) {
                      endpointCtl.text = _endpointHint(selectedProvider);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelCtl,
                  decoration: InputDecoration(
                    labelText: '模型名称',
                    hintText: selectedProvider == 'openai'
                        ? '如 text-embedding-3-small'
                        : selectedProvider == 'ollama'
                            ? '如 nomic-embed-text'
                            : selectedProvider == 'local'
                                ? '如 nomic-embed-text'
                                : '如 Qwen3-Embedding-0.6B',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: endpointCtl,
                  decoration: InputDecoration(
                    labelText: 'API Endpoint',
                    hintText: _endpointHint(selectedProvider),
                    helperText: '兼容 OpenAI /v1/embeddings 接口即可',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKeyCtl,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: config != null
                        ? '留空则不修改'
                        : (selectedProvider == 'local' || selectedProvider == 'ollama')
                            ? '本地无需填写'
                            : 'sk-...',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dimensionsCtl,
                  decoration: const InputDecoration(
                    labelText: '向量维度',
                    helperText: 'OpenAI text-embedding-3-small 为 1536',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: batchSizeCtl,
                  decoration: const InputDecoration(
                    labelText: '批处理大小',
                    helperText: '每次请求的最大文本数量，默认 10（兼容大多数 API）',
                    helperMaxLines: 2,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('设为默认'),
                  contentPadding: EdgeInsets.zero,
                  value: isDefault,
                  onChanged: (v) => setDialogState(() => isDefault = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final data = <String, dynamic>{
                  'name':
                      '${modelCtl.text} ($selectedProvider)',
                  'provider': selectedProvider,
                  'model_name': modelCtl.text,
                  'api_base_url': endpointCtl.text,
                  'dimensions':
                      int.tryParse(dimensionsCtl.text) ?? 1536,
                  'batch_size':
                      (int.tryParse(batchSizeCtl.text) ?? 10).clamp(1, 2048),
                  'is_default': isDefault,
                };
                if (apiKeyCtl.text.isNotEmpty) {
                  data['api_key'] = apiKeyCtl.text;
                }
                bool ok;
                if (config == null) {
                  ok = await ref
                      .read(embeddingConfigProvider.notifier)
                      .create(data);
                } else {
                  ok = await ref
                      .read(embeddingConfigProvider.notifier)
                      .update(config.id, data);
                }
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(config == null ? '创建' : '保存'),
            ),
          ],
        ),
      ),
    );
  }
}
