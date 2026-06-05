import 'package:dio/dio.dart' show Options, ResponseType;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error_messages.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/document_provider.dart';

class DocumentViewerPage extends ConsumerStatefulWidget {
  final Document document;
  final String workspaceId;
  final String? highlightChunkId;

  const DocumentViewerPage({
    super.key,
    required this.document,
    required this.workspaceId,
    this.highlightChunkId,
  });

  @override
  ConsumerState<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends ConsumerState<DocumentViewerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _markdownContent;
  bool _loadingMarkdown = true;
  String? _markdownError;
  List<Map<String, dynamic>> _chunks = [];
  bool _loadingChunks = true;
  String? _chunksError;
  int _chunkPage = 1;
  int _chunkTotal = 0;
  final int _chunkPerPage = 50;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _chunkScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMarkdown();
    _loadChunks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _chunkScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMarkdown() async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get(
        '/workspaces/${widget.workspaceId}/documents/${widget.document.id}/markdown',
        options: Options(responseType: ResponseType.plain),
      );
      if (mounted) {
        setState(() {
          _markdownContent = resp.data.toString();
          _loadingMarkdown = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _markdownError = friendlyApiError(e, fallback: '无法加载文档内容');
          _loadingMarkdown = false;
        });
      }
    }
  }

  Future<void> _loadChunks({int page = 1}) async {
    setState(() => _loadingChunks = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get(
        '/workspaces/${widget.workspaceId}/documents/${widget.document.id}/chunks',
        queryParameters: {'page': page, 'per_page': _chunkPerPage},
      );
      final data = resp.data;
      if (mounted) {
        setState(() {
          _chunks = List<Map<String, dynamic>>.from(data['items'] ?? []);
          _chunkTotal = data['total'] ?? 0;
          _chunkPage = data['page'] ?? 1;
          _loadingChunks = false;
          _chunksError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chunksError = friendlyApiError(e, fallback: '无法加载文档分块');
          _loadingChunks = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredChunks {
    if (_searchQuery.isEmpty) return _chunks;
    final q = _searchQuery.toLowerCase();
    return _chunks
        .where((c) =>
            (c['content'] ?? '').toString().toLowerCase().contains(q) ||
            (c['heading_path'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.document.originalFilename,
                style: const TextStyle(fontSize: 16)),
            Text(
              '${widget.document.fileSizeFormatted}  |  ${widget.document.fileType.toUpperCase()}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '文档内容'),
            Tab(text: '分块索引'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMarkdownTab(),
          _buildChunksTab(),
        ],
      ),
    );
  }

  Widget _buildMarkdownTab() {
    if (_loadingMarkdown) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_markdownError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 12),
              Text('无法加载文档内容', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Text(_markdownError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.red)),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _loadingMarkdown = true;
                    _markdownError = null;
                  });
                  _loadMarkdown();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_markdownContent == null || _markdownContent!.isEmpty) {
      return Center(
        child: Text('文档内容为空', style: TextStyle(color: Colors.grey.shade500)),
      );
    }
    return Markdown(
      data: _markdownContent!,
      selectable: true,
      padding: const EdgeInsets.all(24),
    );
  }

  Widget _buildChunksTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索分块内容...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$_chunkTotal 个分块',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingChunks
              ? const Center(child: CircularProgressIndicator())
              : _chunksError != null
                  ? Center(child: Text('加载失败: $_chunksError'))
                  : _filteredChunks.isEmpty
                      ? Center(
                          child: Text('无匹配分块',
                              style: TextStyle(color: Colors.grey.shade500)))
                      : ListView.builder(
                          controller: _chunkScrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _filteredChunks.length,
                          itemBuilder: (context, index) =>
                              _buildChunkCard(_filteredChunks[index]),
                        ),
        ),
        if (_chunkTotal > _chunkPerPage)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _chunkPage > 1
                      ? () => _loadChunks(page: _chunkPage - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('第 $_chunkPage / ${(_chunkTotal / _chunkPerPage).ceil()} 页',
                    style: const TextStyle(fontSize: 13)),
                IconButton(
                  onPressed:
                      _chunkPage < (_chunkTotal / _chunkPerPage).ceil()
                          ? () => _loadChunks(page: _chunkPage + 1)
                          : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildChunkCard(Map<String, dynamic> chunk) {
    final isHighlighted = widget.highlightChunkId == chunk['id'];
    final headingPath = chunk['heading_path'] as String?;
    final content = chunk['content'] as String? ?? '';
    final chunkIndex = chunk['chunk_index'] as int? ?? 0;
    final pageStart = chunk['page_start'];
    final pageEnd = chunk['page_end'];
    final tokens = chunk['content_tokens'] as int?;
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isHighlighted
            ? BorderSide(color: cs.primary, width: 2)
            : BorderSide.none,
      ),
      color: isHighlighted ? cs.primaryContainer.withValues(alpha: 0.2) : null,
      child: ExpansionTile(
        leading: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${chunkIndex + 1}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: cs.primary,
            ),
          ),
        ),
        title: Text(
          headingPath ?? '分块 ${chunkIndex + 1}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Row(
          children: [
            if (pageStart != null) ...[
              Icon(Icons.description_outlined, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 2),
              Text(
                pageEnd != null && pageEnd != pageStart
                    ? 'p.$pageStart-$pageEnd'
                    : 'p.$pageStart',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(width: 8),
            ],
            if (tokens != null) ...[
              Icon(Icons.token_outlined, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 2),
              Text('$tokens tokens',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SelectableText(
              content,
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

