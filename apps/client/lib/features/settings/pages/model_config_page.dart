import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ai_icon_helper.dart';
import '../providers/model_config_provider.dart';
import '../providers/embedding_config_provider.dart';
import '../providers/rerank_config_provider.dart';

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
    _tabController = TabController(length: 3, vsync: this);
    ref.read(modelConfigProvider.notifier).loadConfigs();
    ref.read(embeddingConfigProvider.notifier).load();
    ref.read(rerankConfigProvider.notifier).load();
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
            Tab(icon: Icon(Icons.sort), text: 'Rerank 模型'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          switch (_tabController.index) {
            case 0:
              _showLlmDialog();
              break;
            case 1:
              _showEmbeddingDialog();
              break;
            case 2:
              _showRerankDialog();
              break;
          }
        },
        child: const Icon(Icons.add),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLlmTab(),
          _buildEmbeddingTab(),
          _buildRerankTab(),
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

  // ── Rerank Tab ──

  Widget _buildRerankTab() {
    final configs = ref.watch(rerankConfigProvider);
    return configs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (list) {
        if (list.isEmpty) {
          return Column(
            children: [
              _buildRerankInfoCard(),
              Expanded(
                child: _buildEmptyState('Rerank 模型', () => _showRerankDialog()),
              ),
            ],
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return _buildRerankInfoCard();
            return _buildRerankCard(list[i - 1]);
          },
        );
      },
    );
  }

  Widget _buildRerankInfoCard() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        elevation: 0,
        color: cs.primaryContainer.withAlpha(30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.primaryContainer, width: 1),
        ),
        child: ExpansionTile(
          leading: Icon(Icons.info_outline, color: cs.primary, size: 20),
          title: Text(
            'Rerank 模型是什么？',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
          initiallyExpanded: false,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _buildInfoSection(
              icon: Icons.architecture,
              title: '两阶段检索架构',
              content: 'TrustRAG 使用「粗召回 + 精排序」两阶段检索：\n'
                  '1. 嵌入模型（Embedding）负责从知识库中快速召回候选文档\n'
                  '2. 重排模型（Rerank）对候选文档重新打分，将最相关的结果排到最前面',
            ),
            const SizedBox(height: 12),
            _buildInfoSection(
              icon: Icons.compare_arrows,
              title: 'Embedding vs Rerank 区别',
              content: 'Embedding 模型：将文本转为向量，通过向量相似度快速检索，速度快但精度有限\n'
                  'Rerank 模型：逐对比较查询与文档的语义相关性，精度更高但速度较慢\n'
                  '两者配合使用效果最佳：先快速召回 30 篇，再精排保留 Top 5',
            ),
            const SizedBox(height: 12),
            _buildInfoSection(
              icon: Icons.lightbulb_outline,
              title: '推荐配置',
              content: 'Jina Reranker v2：多语言支持好，推荐中文场景使用\n'
                  'Cohere Rerank v3.5：英文效果出色，API 稳定\n'
                  'BAAI/bge-reranker-v2-m3：开源模型，可本地部署\n\n'
                  '如不配置 Rerank，系统将仅使用嵌入模型检索，功能不受影响',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection({
    required IconData icon,
    required String title,
    required String content,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.primary.withAlpha(180)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              )),
              const SizedBox(height: 4),
              Text(content, style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: cs.onSurface.withAlpha(180),
              )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRerankCard(RerankConfig cfg) {
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
            '${cfg.provider} · 召回 ${cfg.initialRecallK} → 保留 ${cfg.topN} · ${cfg.timeoutSecs}s${cfg.fallbackEnabled ? ' · 降级' : ''}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: '测试连接',
              onPressed: () => _testRerankConnection(cfg),
            ),
            if (!cfg.isDefault)
              IconButton(
                icon: const Icon(Icons.star_outline, size: 20),
                tooltip: '设为默认',
                onPressed: () => ref
                    .read(rerankConfigProvider.notifier)
                    .setDefault(cfg.id),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showRerankDialog(config: cfg),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () =>
                  ref.read(rerankConfigProvider.notifier).delete(cfg.id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testRerankConnection(RerankConfig cfg) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('正在测试 Rerank 连接...'),
          duration: Duration(seconds: 30)),
    );
    final result =
        await ref.read(rerankConfigProvider.notifier).testConnection(cfg.id);
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
        _showErrorDialog('Rerank 模型连接测试失败', message);
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

  // ── Rerank Dialog ──

  String _rerankEndpointHint(String provider) {
    switch (provider) {
      case 'jina':
        return 'https://api.jina.ai/v1';
      case 'cohere':
        return 'https://api.cohere.ai/v1';
      case 'openai':
        return 'https://api.openai.com/v1';
      default:
        return 'https://your-rerank-api.com/v1';
    }
  }

  String _rerankModelHint(String provider) {
    switch (provider) {
      case 'jina':
        return '如 jina-reranker-v2-base-multilingual';
      case 'cohere':
        return '如 rerank-v3.5';
      case 'openai':
        return '如 gpt-4o-mini (chat-based rerank)';
      default:
        return '如 BAAI/bge-reranker-v2-m3';
    }
  }

  void _showRerankDialog({RerankConfig? config}) {
    String selectedProvider = config?.provider ?? 'jina';
    final modelCtl = TextEditingController(text: config?.modelName ?? '');
    final endpointCtl =
        TextEditingController(text: config?.apiBaseUrl ?? '');
    final apiKeyCtl = TextEditingController();
    final topNCtl = TextEditingController(
        text: config?.topN.toString() ?? '5');
    final recallKCtl = TextEditingController(
        text: config?.initialRecallK.toString() ?? '30');
    final timeoutCtl = TextEditingController(
        text: config?.timeoutSecs.toString() ?? '30');
    bool fallbackEnabled = config?.fallbackEnabled ?? true;
    bool isDefault = config?.isDefault ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(config == null ? '添加 Rerank 模型' : '编辑 Rerank 模型'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedProvider,
                    decoration: const InputDecoration(labelText: 'Provider'),
                    items: ['jina', 'cohere', 'openai', 'custom']
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) {
                      setDialogState(() => selectedProvider = v ?? 'jina');
                      if (endpointCtl.text.isEmpty) {
                        endpointCtl.text =
                            _rerankEndpointHint(selectedProvider);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: modelCtl,
                    decoration: InputDecoration(
                      labelText: '模型名称',
                      hintText: _rerankModelHint(selectedProvider),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: endpointCtl,
                    decoration: InputDecoration(
                      labelText: 'API Endpoint',
                      hintText: _rerankEndpointHint(selectedProvider),
                      helperText: '兼容 /v1/rerank 或 /rerank 接口',
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiKeyCtl,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: config != null ? '留空则不修改' : 'your-api-key',
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('检索参数', style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    )),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: recallKCtl,
                          decoration: const InputDecoration(
                            labelText: '初始召回数',
                            helperText: '嵌入检索候选数（默认 30）',
                            helperMaxLines: 2,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: topNCtl,
                          decoration: const InputDecoration(
                            labelText: '重排保留数',
                            helperText: '重排后保留 Top N（默认 5）',
                            helperMaxLines: 2,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: timeoutCtl,
                    decoration: const InputDecoration(
                      labelText: '超时时间（秒）',
                      helperText: 'Rerank API 请求超时（默认 30 秒）',
                      helperMaxLines: 2,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('失败自动降级'),
                    subtitle: const Text(
                      'Rerank 调用失败时自动回退到嵌入检索',
                      style: TextStyle(fontSize: 11),
                    ),
                    contentPadding: EdgeInsets.zero,
                    value: fallbackEnabled,
                    onChanged: (v) => setDialogState(() => fallbackEnabled = v),
                  ),
                  SwitchListTile(
                    title: const Text('设为默认'),
                    contentPadding: EdgeInsets.zero,
                    value: isDefault,
                    onChanged: (v) => setDialogState(() => isDefault = v),
                  ),
                ],
              ),
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
                  'top_n': (int.tryParse(topNCtl.text) ?? 5).clamp(1, 100),
                  'initial_recall_k': (int.tryParse(recallKCtl.text) ?? 30).clamp(5, 200),
                  'timeout_secs': (int.tryParse(timeoutCtl.text) ?? 30).clamp(5, 300),
                  'fallback_enabled': fallbackEnabled,
                  'is_default': isDefault,
                };
                if (apiKeyCtl.text.isNotEmpty) {
                  data['api_key'] = apiKeyCtl.text;
                }
                bool ok;
                if (config == null) {
                  ok = await ref
                      .read(rerankConfigProvider.notifier)
                      .create(data);
                } else {
                  ok = await ref
                      .read(rerankConfigProvider.notifier)
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
