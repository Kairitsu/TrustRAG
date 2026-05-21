import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/dev_mode_provider.dart';
import '../../../core/services/backend_manager.dart';
import '../../../main.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/pages/chat_page.dart';
import '../../documents/pages/documents_page.dart';
import '../../review/pages/review_list_page.dart';
import '../../search/pages/workspace_search_page.dart';
import '../../settings/pages/model_config_page.dart';
import '../../settings/pages/workspace_members_page.dart';
import '../providers/workspace_provider.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  int _selectedIndex = 0;

  static const _navItems = <({IconData icon, IconData selectedIcon, String label})>[
    (icon: Icons.chat_outlined, selectedIcon: Icons.chat, label: '对话'),
    (icon: Icons.folder_outlined, selectedIcon: Icons.folder, label: '资料库'),
    (icon: Icons.rate_review_outlined, selectedIcon: Icons.rate_review, label: '审核'),
    (icon: Icons.workspaces_outlined, selectedIcon: Icons.workspaces, label: '工作区'),
    (icon: Icons.search_outlined, selectedIcon: Icons.search, label: '搜索'),
    (icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final authState = ref.watch(authProvider);

    if (authState.status == AuthStatus.unauthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/login');
      });
    }

    final contentArea = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(
        key: ValueKey<int>(_selectedIndex),
        child: _buildContent(),
      ),
    );

    // <600px: bottom navigation (mobile)
    if (width < 600) {
      return Scaffold(
        body: contentArea,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) => setState(() => _selectedIndex = i),
          destinations: _navItems
              .map((n) => NavigationDestination(
                    icon: Icon(n.icon),
                    selectedIcon: Icon(n.selectedIcon),
                    label: n.label,
                  ))
              .toList(),
        ),
      );
    }

    // ≥600px: side navigation rail
    final extended = width >= 900;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_stories_rounded,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                  if (extended) ...[
                    const SizedBox(width: 8),
                    Text(
                      'TrustRAG',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: '退出登录',
                    onPressed: () {
                      ref.read(authProvider.notifier).logout();
                      context.go('/login');
                    },
                  ),
                ),
              ),
            ),
            destinations: _navItems
                .map((n) => NavigationRailDestination(
                      icon: Icon(n.icon),
                      selectedIcon: Icon(n.selectedIcon),
                      label: Text(n.label),
                    ))
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: contentArea),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildChatView();
      case 1:
        return _buildDocumentsView();
      case 2:
        return const ReviewListPage();
      case 3:
        return _buildWorkspacesView();
      case 4:
        return const WorkspaceSearchPage();
      case 5:
        return _buildSettingsView();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildChatView() {
    return const ChatPage();
  }

  Widget _buildDocumentsView() {
    return const DocumentsPage();
  }

  Widget _buildWorkspacesView() {
    final workspaces = ref.watch(workspaceProvider);
    final selectedWs = ref.watch(selectedWorkspaceProvider);

    return Column(
      children: [
        _buildHeader(
          '工作区',
          actions: [
            FilledButton.icon(
              onPressed: () => _showCreateWorkspaceDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建'),
            ),
          ],
        ),
        Expanded(
          child: workspaces.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败: $e')),
            data: (list) {
              if (list.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.workspaces_outlined,
                          size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        '还没有工作区',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.grey,
                                ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _showCreateWorkspaceDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('创建第一个工作区'),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final ws = list[index];
                  final isSelected = selectedWs?.id == ws.id;
                  return Card(
                    color: isSelected
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08)
                        : null,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade300,
                        child: Icon(
                          Icons.workspaces,
                          color: isSelected ? Colors.white : Colors.grey,
                          size: 20,
                        ),
                      ),
                      title: Text(ws.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(ws.description ?? '无描述'),
                      trailing: isSelected
                          ? Icon(Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () {
                        ref.read(selectedWorkspaceProvider.notifier).state = ws;
                        saveLastWorkspaceId(ws.id);
                        setState(() => _selectedIndex = 0);
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsView() {
    return Column(
      children: [
        _buildHeader('设置'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.model_training),
                  title: const Text('模型配置'),
                  subtitle: const Text('管理 LLM 和 Embedding 模型'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const ModelConfigPage()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.group),
                  title: const Text('团队成员'),
                  subtitle: const Text('管理工作区的成员和权限'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const WorkspaceMembersPage()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('账户信息'),
                  subtitle: Text(
                      ref.watch(authProvider).user?['email'] ?? '未知'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showAccountDialog(),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: Icon(
                    ref.watch(themeModeProvider) == ThemeMode.dark
                        ? Icons.dark_mode
                        : ref.watch(themeModeProvider) == ThemeMode.light
                            ? Icons.light_mode
                            : Icons.brightness_auto,
                  ),
                  title: const Text('外观'),
                  subtitle: Text(_themeLabel(ref.watch(themeModeProvider))),
                  trailing: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 16)),
                      ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto, size: 16)),
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 16)),
                    ],
                    selected: {ref.watch(themeModeProvider)},
                    onSelectionChanged: (s) {
                      ref.read(themeModeProvider.notifier).state = s.first;
                    },
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: SwitchListTile(
                  secondary: Icon(
                    Icons.developer_mode,
                    color: ref.watch(devModeProvider) ? Colors.orange : null,
                  ),
                  title: const Text('开发者模式'),
                  subtitle: Text(ref.watch(devModeProvider)
                      ? '已开启 — 显示调试工具'
                      : '开启后可查看日志、API 请求等调试信息'),
                  value: ref.watch(devModeProvider),
                  onChanged: (_) => ref.read(devModeProvider.notifier).toggle(),
                ),
              ),
              if (ref.watch(devModeProvider)) ...[
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.terminal, color: Colors.orange),
                    title: const Text('调试日志'),
                    subtitle: const Text('查看运行时日志和 API 请求记录'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showDebugLogPanel(),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline, color: Colors.orange),
                    title: const Text('运行环境'),
                    subtitle: Text(
                      'Backend: ${BackendManager().baseUrl}\n'
                      'Embedded: ${BackendManager.shouldRunEmbedded}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(
                          text: 'Backend: ${BackendManager().baseUrl}\n'
                              'Embedded: ${BackendManager.shouldRunEmbedded}',
                        ));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('环境信息已复制'), duration: Duration(seconds: 2)),
                        );
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于'),
                  subtitle: const Text('TrustRAG v0.2.1'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showAboutDialog(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(String title,
      {String? subtitle, List<Widget>? actions}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border:
            Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                ),
            ],
          ),
          const Spacer(),
          if (actions != null) ...actions,
        ],
      ),
    );
  }

  void _showDebugLogPanel() {
    final logs = DebugLogBuffer().logs;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.terminal, color: Colors.orange, size: 22),
            const SizedBox(width: 8),
            const Text('调试日志'),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                DebugLogBuffer().clear();
                Navigator.pop(ctx);
                _showDebugLogPanel();
              },
              icon: const Icon(Icons.delete_sweep, size: 16),
              label: const Text('清空'),
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: logs.isEmpty
              ? const Center(
                  child: Text('暂无日志', style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  reverse: true,
                  itemCount: logs.length,
                  itemBuilder: (_, i) {
                    final log = logs[logs.length - 1 - i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: SelectableText(
                        log,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: log.contains('ERROR')
                              ? Colors.red
                              : log.contains('WARN')
                                  ? Colors.orange
                                  : Colors.grey.shade700,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: logs.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已复制到剪贴板'), duration: Duration(seconds: 2)),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制全部'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showAccountDialog() {
    final user = ref.read(authProvider).user;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('账户信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 36,
              child: Text(
                (user?['display_name'] ?? 'U')[0].toUpperCase(),
                style: const TextStyle(fontSize: 28),
              ),
            ),
            const SizedBox(height: 16),
            _infoRow('用户名', user?['display_name'] ?? '未知'),
            const SizedBox(height: 8),
            _infoRow('邮箱', user?['email'] ?? '未知'),
            const SizedBox(height: 8),
            _infoRow('角色', user?['role'] ?? 'user'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        Text('$label: ',
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: Colors.grey)),
        Expanded(child: Text(value)),
      ],
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.auto_stories_rounded,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('关于 TrustRAG'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TrustRAG - 可信赖的 RAG 知识工作台',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _infoRow('版本', 'v0.2.0'),
            const SizedBox(height: 4),
            _infoRow('后端', 'Rust (Axum)'),
            const SizedBox(height: 4),
            _infoRow('前端', 'Flutter Web'),
            const SizedBox(height: 4),
            _infoRow('数据库', 'PostgreSQL + pgvector'),
            const SizedBox(height: 4),
            _infoRow('存储', 'MinIO (S3-compatible)'),
            const SizedBox(height: 12),
            const Text(
              '基于文档检索增强生成（RAG）技术，提供带引用溯源的可信赖 AI 问答。',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showCreateWorkspaceDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建工作区'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '名称'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: '描述（可选）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              final ws = await ref
                  .read(workspaceProvider.notifier)
                  .createWorkspace(
                    nameController.text.trim(),
                    descController.text.trim().isEmpty
                        ? null
                        : descController.text.trim(),
                  );
              if (ws != null && ctx.mounted) {
                ref.read(selectedWorkspaceProvider.notifier).state = ws;
                saveLastWorkspaceId(ws.id);
                Navigator.pop(ctx);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}
