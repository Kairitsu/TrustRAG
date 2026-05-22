import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/dev_mode_provider.dart';
import '../../../core/services/backend_manager.dart';
import '../../../core/services/update_checker.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart';
import '../../auth/providers/auth_provider.dart';
import '../../settings/widgets/update_dialog.dart';
import '../../chat/pages/chat_page.dart';
import '../../documents/pages/documents_page.dart';
import '../../review/pages/review_list_page.dart';
import '../../search/pages/workspace_search_page.dart';
import '../../search/pages/knowledge_graph_page.dart';
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
  bool _checkingUpdate = false;

  static const _navIcons = <({IconData icon, IconData selectedIcon})>[
    (icon: Icons.chat_outlined, selectedIcon: Icons.chat),
    (icon: Icons.folder_outlined, selectedIcon: Icons.folder),
    (icon: Icons.rate_review_outlined, selectedIcon: Icons.rate_review),
    (icon: Icons.workspaces_outlined, selectedIcon: Icons.workspaces),
    (icon: Icons.search_outlined, selectedIcon: Icons.search),
    (icon: Icons.hub_outlined, selectedIcon: Icons.hub),
    (icon: Icons.settings_outlined, selectedIcon: Icons.settings),
  ];

  List<String> _navLabels(BuildContext context) {
    final s = S.of(context);
    return [s.navChat, s.navDocuments, s.navReview, s.navWorkspaces, s.navSearch, s.navKnowledgeGraph, s.navSettings];
  }

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
          destinations: List.generate(_navIcons.length, (i) => NavigationDestination(
                    icon: Icon(_navIcons[i].icon),
                    selectedIcon: Icon(_navIcons[i].selectedIcon),
                    label: _navLabels(context)[i],
                  )),
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
                    tooltip: S.of(context).logout,
                    onPressed: () {
                      ref.read(authProvider.notifier).logout();
                      context.go('/login');
                    },
                  ),
                ),
              ),
            ),
            destinations: List.generate(_navIcons.length, (i) => NavigationRailDestination(
                      icon: Icon(_navIcons[i].icon),
                      selectedIcon: Icon(_navIcons[i].selectedIcon),
                      label: Text(_navLabels(context)[i]),
                    )),
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
        return const KnowledgeGraphPage();
      case 6:
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
          S.of(context).workspaces,
          actions: [
            FilledButton.icon(
              onPressed: () => _showCreateWorkspaceDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: Text(S.of(context).createNew),
            ),
          ],
        ),
        Expanded(
          child: workspaces.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(S.of(context).loadFailed(e.toString()))),
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
                        S.of(context).noWorkspaces,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.grey,
                                ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _showCreateWorkspaceDialog(),
                        icon: const Icon(Icons.add),
                        label: Text(S.of(context).createFirstWorkspace),
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
                      subtitle: Text(ws.description ?? S.of(context).noDescription),
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
        _buildHeader(S.of(context).settings),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.model_training),
                  title: Text(S.of(context).modelConfig),
                  subtitle: Text(S.of(context).modelConfigSubtitle),
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
                  title: Text(S.of(context).teamMembers),
                  subtitle: Text(S.of(context).teamMembersSubtitle),
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
                  title: Text(S.of(context).accountInfo),
                  subtitle: Text(
                      ref.watch(authProvider).user?['email'] ?? S.of(context).unknown),
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
                  title: Text(S.of(context).appearance),
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
                child: ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(S.of(context).language),
                  subtitle: Text(_currentLanguageLabel(context)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showLanguagePicker(),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: SwitchListTile(
                  secondary: Icon(
                    Icons.developer_mode,
                    color: ref.watch(devModeProvider) ? Colors.orange : null,
                  ),
                  title: Text(S.of(context).developerMode),
                  subtitle: Text(ref.watch(devModeProvider)
                      ? S.of(context).devModeOn
                      : S.of(context).devModeOff),
                  value: ref.watch(devModeProvider),
                  onChanged: (_) => ref.read(devModeProvider.notifier).toggle(),
                ),
              ),
              if (ref.watch(devModeProvider)) ...[
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.terminal, color: Colors.orange),
                    title: Text(S.of(context).debugLog),
                    subtitle: Text(S.of(context).debugLogSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showDebugLogPanel(),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline, color: Colors.orange),
                    title: Text(S.of(context).runtimeEnv),
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
                          SnackBar(content: Text(S.of(context).envInfoCopied), duration: const Duration(seconds: 2)),
                        );
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: _checkingUpdate
                      ? const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update_alt_rounded),
                  title: Text(S.of(context).checkUpdate),
                  subtitle: Text(S.of(context).currentVersion(appVersion)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _checkingUpdate ? null : () => _manualCheckUpdate(),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(S.of(context).about),
                  subtitle: Text('TrustRAG v$appVersion'),
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

  String _currentLanguageLabel(BuildContext context) {
    final locale = ref.watch(localeProvider);
    if (locale == null) return S.of(context).themeSystem;
    switch (locale.languageCode) {
      case 'zh': return S.of(context).languageZh;
      case 'en': return S.of(context).languageEn;
      case 'ja': return S.of(context).languageJa;
      default: return locale.languageCode;
    }
  }

  void _showLanguagePicker() {
    final s = S.of(context);
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(s.language),
        children: [
          SimpleDialogOption(
            onPressed: () { Navigator.pop(ctx); setAppLocale(ref, null); },
            child: ListTile(
              leading: const Icon(Icons.brightness_auto),
              title: Text(s.themeSystem),
              dense: true,
              selected: ref.read(localeProvider) == null,
            ),
          ),
          SimpleDialogOption(
            onPressed: () { Navigator.pop(ctx); setAppLocale(ref, const Locale('zh')); },
            child: ListTile(
              title: Text(s.languageZh),
              dense: true,
              selected: ref.read(localeProvider)?.languageCode == 'zh',
            ),
          ),
          SimpleDialogOption(
            onPressed: () { Navigator.pop(ctx); setAppLocale(ref, const Locale('en')); },
            child: ListTile(
              title: Text(s.languageEn),
              dense: true,
              selected: ref.read(localeProvider)?.languageCode == 'en',
            ),
          ),
          SimpleDialogOption(
            onPressed: () { Navigator.pop(ctx); setAppLocale(ref, const Locale('ja')); },
            child: ListTile(
              title: Text(s.languageJa),
              dense: true,
              selected: ref.read(localeProvider)?.languageCode == 'ja',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _manualCheckUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      final release = await UpdateChecker().checkForUpdate(appVersion, force: true);
      if (!mounted) return;
      if (release != null) {
        UpdateDialog.show(context, release: release, currentVersion: appVersion);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).alreadyLatest),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).checkUpdateFailed(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
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
            Text(S.of(context).debugLogTitle),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                DebugLogBuffer().clear();
                Navigator.pop(ctx);
                _showDebugLogPanel();
              },
              icon: const Icon(Icons.delete_sweep, size: 16),
              label: Text(S.of(context).clearLog),
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: logs.isEmpty
              ? Center(
                  child: Text(S.of(context).noLogs, style: const TextStyle(color: Colors.grey)),
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
                SnackBar(content: Text(S.of(context).logCopied), duration: const Duration(seconds: 2)),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: Text(S.of(context).copyAll),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).close),
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
        title: Text(S.of(context).accountInfoTitle),
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
            _infoRow(S.of(context).username, user?['display_name'] ?? S.of(context).unknown),
            const SizedBox(height: 8),
            _infoRow(S.of(context).email, user?['email'] ?? S.of(context).unknown),
            const SizedBox(height: 8),
            _infoRow(S.of(context).role, user?['role'] ?? 'user'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).close),
          ),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) {
    final s = S.of(context);
    switch (mode) {
      case ThemeMode.light:
        return s.themeLight;
      case ThemeMode.dark:
        return s.themeDark;
      case ThemeMode.system:
        return s.themeSystem;
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
            Text(S.of(context).aboutTrustRAG),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.of(context).trustragDescription,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _infoRow(S.of(context).version, 'v$appVersion'),
            const SizedBox(height: 4),
            _infoRow(S.of(context).backend, 'Rust (Axum)'),
            const SizedBox(height: 4),
            _infoRow(S.of(context).frontend, 'Flutter'),
            const SizedBox(height: 4),
            _infoRow(S.of(context).database, 'PostgreSQL + pgvector'),
            const SizedBox(height: 4),
            _infoRow(S.of(context).storage, 'MinIO (S3-compatible)'),
            const SizedBox(height: 12),
            Text(
              S.of(context).aboutDescription,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).close),
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
        title: Text(S.of(context).createWorkspace),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: S.of(context).nameLabel),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: InputDecoration(labelText: S.of(context).descriptionLabel),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).cancel),
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
            child: Text(S.of(context).create),
          ),
        ],
      ),
    );
  }
}
