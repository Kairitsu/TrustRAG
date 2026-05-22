import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backend_manager.dart';
import '../../chat/providers/chat_provider.dart';
import '../../dashboard/providers/workspace_provider.dart';
import '../providers/document_provider.dart';
import 'document_viewer_page.dart';

const _desktopSupportedExtensions = {'txt', 'md', 'html', 'htm', 'pdf'};

class DocumentsPage extends ConsumerStatefulWidget {
  const DocumentsPage({super.key});

  @override
  ConsumerState<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends ConsumerState<DocumentsPage> {
  Timer? _refreshTimer;
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;
  String? _activeFolder;

  @override
  void initState() {
    super.initState();
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws != null) {
      ref.read(documentProvider.notifier).loadDocuments(ws.id);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh(List<Document> docs) {
    _refreshTimer?.cancel();
    final hasProcessing = docs.any((d) =>
        d.processingStatus == 'processing' ||
        d.processingStatus == 'chunking' ||
        d.processingStatus == 'embedding' ||
        d.processingStatus == 'pending');
    if (hasProcessing) {
      _refreshTimer = Timer(const Duration(seconds: 3), () {
        final ws = ref.read(selectedWorkspaceProvider);
        if (ws != null && mounted) {
          ref.read(documentProvider.notifier).loadDocuments(ws.id);
        }
      });
    }
  }

  bool get _isDesktopEmbedded =>
      !kIsWeb && BackendManager.shouldRunEmbedded;

  Future<void> _uploadFile() async {
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;

    final allowedExts = _isDesktopEmbedded
        ? _desktopSupportedExtensions.toList()
        : ['pdf', 'docx', 'txt', 'md', 'html'];

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExts,
      allowMultiple: true,
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      int successCount = 0;
      for (final file in result.files) {
        if (file.bytes != null) {
          final ok = await ref
              .read(documentProvider.notifier)
              .uploadDocument(ws.id, file.bytes!, file.name);
          if (ok) successCount++;
        }
      }
      if (mounted && successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功上传 $successCount 个文件')),
        );
      }
    }
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确认删除 ${_selectedIds.length} 个文档？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    for (final id in _selectedIds.toList()) {
      await ref.read(documentProvider.notifier).deleteDocument(ws.id, id);
    }
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('批量删除完成')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(selectedWorkspaceProvider);
    final docs = ref.watch(documentProvider);

    if (ws == null) {
      return Center(
        child: Text('请先选择工作区', style: TextStyle(color: Colors.grey.shade500)),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
          ),
          child: Row(
            children: [
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('资料库',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(ws.name,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(width: 8),
                  _buildWorkspaceSwitch(ws),
                ],
              ),
              const Spacer(),
              if (_selectionMode) ...[
                Text('已选 ${_selectedIds.length} 项',
                    style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _batchDelete,
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  label: const Text('批量删除', style: TextStyle(color: Colors.red)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _selectionMode = false;
                    _selectedIds.clear();
                  }),
                  child: const Text('取消'),
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: () => setState(() => _selectionMode = true),
                  icon: const Icon(Icons.checklist, size: 18),
                  label: const Text('选择'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _uploadFile,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('上传文档'),
                ),
                if (_isDesktopEmbedded) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: '桌面模式支持 TXT/MD/HTML/PDF\n'
                        'DOCX 需要部署服务器模式',
                    child: Icon(Icons.info_outline,
                        size: 18, color: Colors.orange.shade600),
                  ),
                ],
              ],
            ],
          ),
        ),
        Expanded(
          child: docs.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败: $e')),
            data: (allDocs) {
              _startAutoRefresh(allDocs);
              final folders = _extractFolders(allDocs);
              final list = _activeFolder == null
                  ? allDocs
                  : allDocs.where((d) => d.tags.contains(_activeFolder)).toList();
              if (allDocs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.upload_file,
                          size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('暂无文档',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: Colors.grey)),
                      const SizedBox(height: 8),
                      Text(
                          _isDesktopEmbedded
                              ? '点击"上传文档"添加 PDF、TXT、MD 或 HTML 文件'
                              : '点击"上传文档"添加 PDF、DOCX 或 TXT 文件',
                          style: TextStyle(color: Colors.grey.shade500)),
                      if (_isDesktopEmbedded) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.orange.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16,
                                  color: Colors.orange.shade700),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '桌面模式暂不支持 PDF/DOCX 解析，'
                                  '如需解析这些格式请部署服务器模式',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  if (folders.isNotEmpty) _buildFolderBar(folders, ws),
                  if (_activeFolder != null && list.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text('文件夹 "$_activeFolder" 中暂无文档',
                            style: TextStyle(color: Colors.grey.shade500)),
                      ),
                    )
                  else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                  final doc = list[index];
                  final isSelected = _selectedIds.contains(doc.id);
                  return Card(
                    child: ListTile(
                      onTap: _selectionMode
                          ? () => setState(() {
                                if (isSelected) {
                                  _selectedIds.remove(doc.id);
                                } else {
                                  _selectedIds.add(doc.id);
                                }
                              })
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DocumentViewerPage(
                                    document: doc,
                                    workspaceId: ws.id,
                                  ),
                                ),
                              );
                            },
                      onLongPress: () {
                        if (!_selectionMode) {
                          setState(() {
                            _selectionMode = true;
                            _selectedIds.add(doc.id);
                          });
                        }
                      },
                      selected: isSelected,
                      leading: _selectionMode
                          ? Checkbox(
                              value: isSelected,
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _selectedIds.add(doc.id);
                                } else {
                                  _selectedIds.remove(doc.id);
                                }
                              }),
                            )
                          : _fileIcon(doc.fileType),
                      title: Text(doc.originalFilename,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(doc.fileSizeFormatted),
                              const SizedBox(width: 12),
                              _statusChip(doc.processingStatus),
                              if (doc.chunkCount != null) ...[
                                const SizedBox(width: 12),
                                Text('${doc.chunkCount} 分块',
                                    style: TextStyle(
                                        color: Colors.grey.shade600, fontSize: 12)),
                              ],
                            ],
                          ),
                          if (doc.tags.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: doc.tags
                                    .map((t) => Padding(
                                          padding: const EdgeInsets.only(right: 4),
                                          child: Chip(
                                            label: Text(t, style: const TextStyle(fontSize: 10)),
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                                            padding: EdgeInsets.zero,
                                            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ),
                          if (doc.processingStatus == 'failed' && doc.processingError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                doc.processingError!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: Colors.red.shade400),
                              ),
                            ),
                        ],
                      ),
                      trailing: PopupMenuButton(
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                              value: 'move_folder', child: Text('移动到文件夹')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('删除')),
                        ],
                        onSelected: (value) async {
                          if (value == 'delete') {
                            await ref
                                .read(documentProvider.notifier)
                                .deleteDocument(ws.id, doc.id);
                          } else if (value == 'move_folder') {
                            _showMoveFolderDialog(doc, ws);
                          }
                        },
                      ),
                    ),
                  );
                },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceSwitch(dynamic ws) {
    final workspaces = ref.watch(workspaceProvider);
    return workspaces.when(
      data: (list) {
        if (list.length <= 1) return const SizedBox.shrink();
        return PopupMenuButton<String>(
          tooltip: '切换工作区/资料库',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_horiz, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                Text('切换', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
              ],
            ),
          ),
          onSelected: (id) {
            final target = list.firstWhere((w) => w.id == id);
            ref.read(selectedWorkspaceProvider.notifier).state = target;
            saveLastWorkspaceId(target.id);
            ref.read(documentProvider.notifier).loadDocuments(target.id);
            ref.read(conversationProvider.notifier).loadConversations(target.id);
            ref.read(selectedConversationProvider.notifier).state = null;
            ref.read(messagesProvider.notifier).state = [];
          },
          itemBuilder: (_) => list
              .map((w) => PopupMenuItem<String>(
                    value: w.id,
                    child: Row(
                      children: [
                        Icon(
                          w.id == ws.id ? Icons.check_circle : Icons.circle_outlined,
                          size: 16,
                          color: w.id == ws.id
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(w.name),
                        if (w.description != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              w.description!,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ))
              .toList(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _fileIcon(String fileType) {
    IconData icon;
    Color color;
    switch (fileType.toLowerCase()) {
      case 'pdf':
        icon = Icons.picture_as_pdf;
        color = Colors.red;
        break;
      case 'docx':
        icon = Icons.description;
        color = Colors.blue;
        break;
      default:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
    }
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.1),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Set<String> _extractFolders(List<Document> docs) {
    final folders = <String>{};
    for (final d in docs) {
      folders.addAll(d.tags);
    }
    return folders;
  }

  Widget _buildFolderBar(Set<String> folders, dynamic ws) {
    final sortedFolders = folders.toList()..sort();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _folderChip('全部', null),
                  ...sortedFolders.map((f) => _folderChip(f, f)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            tooltip: '新建文件夹',
            onPressed: () => _showCreateFolderDialog(ws),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _folderChip(String label, String? folder) {
    final isActive = _activeFolder == folder;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: isActive,
        onSelected: (_) => setState(() => _activeFolder = folder),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Future<void> _showCreateFolderDialog(dynamic ws) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '文件夹名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) {
      setState(() => _activeFolder = name);
    }
  }

  Future<void> _showMoveFolderDialog(Document doc, dynamic ws) async {
    final docs = ref.read(documentProvider).value ?? [];
    final existingFolders = _extractFolders(docs).toList()..sort();
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移动到文件夹'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (doc.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('当前文件夹: ${doc.tags.join(", ")}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ),
              if (existingFolders.isNotEmpty) ...[
                const Text('选择已有文件夹:', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ActionChip(
                      label: const Text('无文件夹'),
                      onPressed: () => Navigator.pop(ctx, '__none__'),
                    ),
                    ...existingFolders.map((f) => ActionChip(
                          label: Text(f),
                          onPressed: () => Navigator.pop(ctx, f),
                        )),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('或输入新文件夹:', style: TextStyle(fontSize: 13)),
              ] else
                const Text('输入文件夹名称:', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: '新文件夹名',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null || result.isEmpty) return;

    final newTags = result == '__none__' ? <String>[] : [result];
    await ref.read(documentProvider.notifier).updateTags(ws.id, doc.id, newTags);
  }

  Widget _statusChip(String status) {
    Color color;
    String label;
    bool isLoading = false;
    switch (status) {
      case 'ready':
        color = Colors.green;
        label = '就绪';
        break;
      case 'processing':
        color = Colors.orange;
        label = '解析中';
        isLoading = true;
        break;
      case 'chunking':
        color = Colors.orange;
        label = '分块中';
        isLoading = true;
        break;
      case 'embedding':
        color = Colors.blue;
        label = '向量化中';
        isLoading = true;
        break;
      case 'failed':
        color = Colors.red;
        label = '失败';
        break;
      default:
        color = Colors.grey;
        label = '等待';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading) ...[
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
