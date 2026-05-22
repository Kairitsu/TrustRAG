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
import '../../settings/pages/team_management_page.dart';
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
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
                  const SizedBox(height: 12),
                  _buildWorkspaceSwitcher(extended),
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
            OutlinedButton.icon(
              onPressed: () => _showJoinTeamDialog(),
              icon: const Icon(Icons.login, size: 18),
              label: const Text('加入团队'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _showCreateTeamDialog(),
              icon: const Icon(Icons.group_add, size: 18),
              label: const Text('创建团队'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
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

              final personal = list.where((w) => w.isPersonal).toList();
              final teams = list.where((w) => w.isTeam).toList();

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (personal.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('个人空间', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey)),
                    ),
                    ...personal.map((ws) => _buildWorkspaceCard(ws, selectedWs)),
                    const SizedBox(height: 16),
                  ],
                  if (teams.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('团队空间', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey)),
                    ),
                    ...teams.map((ws) => _buildWorkspaceCard(ws, selectedWs)),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceCard(Workspace ws, Workspace? selectedWs) {
    final isSelected = selectedWs?.id == ws.id;
    return Card(
      color: isSelected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
          : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade300,
          child: Icon(
            ws.isTeam ? Icons.groups : Icons.person,
            color: isSelected ? Colors.white : Colors.grey,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(ws.name, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (ws.isTeam)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('团队', style: TextStyle(fontSize: 10, color: Colors.blue)),
              ),
          ],
        ),
        subtitle: Text(ws.description ?? S.of(context).noDescription),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ws.isTeam)
              IconButton(
                icon: const Icon(Icons.settings, size: 18),
                tooltip: '团队设置',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TeamManagementPage(workspace: ws),
                    ),
                  );
                },
              ),
            if (isSelected)
              Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
          ],
        ),
        onTap: () {
          ref.read(selectedWorkspaceProvider.notifier).state = ws;
          saveLastWorkspaceId(ws.id);
          setState(() => _selectedIndex = 0);
        },
      ),
    );
  }

  Widget _buildSettingsView() {
    final selectedWs = ref.watch(selectedWorkspaceProvider);
    final isTeamWs = selectedWs?.isTeam == true;

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
              if (isTeamWs) ...[
                Card(
                  child: ListTile(
                    leading: Icon(Icons.groups, color: Theme.of(context).colorScheme.primary),
                    title: const Text('团队设置'),
                    subtitle: Text('管理「${selectedWs!.name}」团队'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TeamManagementPage(workspace: selectedWs),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
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
      case 'ko': return S.of(context).languageKo;
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
          SimpleDialogOption(
            onPressed: () { Navigator.pop(ctx); setAppLocale(ref, const Locale('ko')); },
            child: ListTile(
              title: Text(s.languageKo),
              dense: true,
              selected: ref.read(localeProvider)?.languageCode == 'ko',
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

  Widget _buildWorkspaceSwitcher(bool extended) {
    final workspaces = ref.watch(workspaceProvider);
    final selectedWs = ref.watch(selectedWorkspaceProvider);

    return workspaces.when(
      loading: () => const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => IconButton(
        icon: const Icon(Icons.error_outline, color: Colors.red),
        onPressed: () => ref.read(workspaceProvider.notifier).loadWorkspaces(),
        tooltip: S.of(context).loadFailed(''),
      ),
      data: (list) {
        if (!extended) {
          return PopupMenuButton<String>(
            tooltip: S.of(context).workspaces,
            icon: Icon(
              selectedWs?.isTeam == true ? Icons.groups : Icons.person,
              color: Theme.of(context).colorScheme.primary,
            ),
            onSelected: (id) {
              if (id == '__create_team__') {
                _showCreateTeamDialog();
              } else if (id == '__join_team__') {
                _showJoinTeamDialog();
              } else {
                final ws = list.firstWhere((w) => w.id == id);
                ref.read(selectedWorkspaceProvider.notifier).state = ws;
                saveLastWorkspaceId(ws.id);
              }
            },
            itemBuilder: (_) {
              final items = <PopupMenuEntry<String>>[];
              final personal = list.where((w) => w.isPersonal).toList();
              final teams = list.where((w) => w.isTeam).toList();

              if (personal.isNotEmpty) {
                items.add(const PopupMenuItem(enabled: false, child: Text('── 个人空间 ──', style: TextStyle(fontSize: 11, color: Colors.grey))));
                for (final ws in personal) {
                  items.add(PopupMenuItem(
                    value: ws.id,
                    child: Row(children: [
                      Icon(Icons.person, size: 16, color: selectedWs?.id == ws.id ? Theme.of(context).colorScheme.primary : null),
                      const SizedBox(width: 8),
                      Expanded(child: Text(ws.name, overflow: TextOverflow.ellipsis)),
                      if (selectedWs?.id == ws.id) Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
                    ]),
                  ));
                }
              }
              if (teams.isNotEmpty) {
                items.add(const PopupMenuDivider());
                items.add(const PopupMenuItem(enabled: false, child: Text('── 团队空间 ──', style: TextStyle(fontSize: 11, color: Colors.grey))));
                for (final ws in teams) {
                  items.add(PopupMenuItem(
                    value: ws.id,
                    child: Row(children: [
                      Icon(Icons.groups, size: 16, color: selectedWs?.id == ws.id ? Theme.of(context).colorScheme.primary : null),
                      const SizedBox(width: 8),
                      Expanded(child: Text(ws.name, overflow: TextOverflow.ellipsis)),
                      if (selectedWs?.id == ws.id) Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
                    ]),
                  ));
                }
              }
              items.add(const PopupMenuDivider());
              items.add(const PopupMenuItem(value: '__create_team__', child: Row(children: [Icon(Icons.add, size: 16), SizedBox(width: 8), Text('创建团队')])));
              items.add(const PopupMenuItem(value: '__join_team__', child: Row(children: [Icon(Icons.login, size: 16), SizedBox(width: 8), Text('加入团队')])));
              return items;
            },
          );
        }

        return Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: selectedWs?.id,
              hint: Text(S.of(context).workspaces, style: const TextStyle(fontSize: 13)),
              icon: const Icon(Icons.unfold_more, size: 16),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              items: [
                ...list.map((ws) => DropdownMenuItem(
                  value: ws.id,
                  child: Row(children: [
                    Icon(ws.isTeam ? Icons.groups : Icons.person, size: 14, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(ws.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                  ]),
                )),
              ],
              onChanged: (id) {
                if (id == null) return;
                final ws = list.firstWhere((w) => w.id == id);
                ref.read(selectedWorkspaceProvider.notifier).state = ws;
                saveLastWorkspaceId(ws.id);
              },
            ),
          ),
        );
      },
    );
  }

  void _showCreateTeamDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建团队'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '团队名称', border: OutlineInputBorder()),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: '团队描述（可选）', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(context).cancel)),
          FilledButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              final ws = await ref.read(workspaceProvider.notifier).createWorkspace(
                nameController.text.trim(),
                descController.text.trim().isEmpty ? null : descController.text.trim(),
                type: 'team',
              );
              if (ws != null && ctx.mounted) {
                ref.read(selectedWorkspaceProvider.notifier).state = ws;
                saveLastWorkspaceId(ws.id);
                Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('团队「${ws.name}」创建成功！邀请码: ${ws.inviteCode ?? "N/A"}')),
                  );
                }
              }
            },
            child: Text(S.of(context).create),
          ),
        ],
      ),
    );
  }

  void _showJoinTeamDialog() {
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('加入团队'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: '邀请码',
                hintText: '输入 8 位邀请码',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(context).cancel)),
          FilledButton(
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.isEmpty) return;
              final ws = await ref.read(workspaceProvider.notifier).joinWorkspace(code);
              if (ws != null && ctx.mounted) {
                ref.read(selectedWorkspaceProvider.notifier).state = ws;
                saveLastWorkspaceId(ws.id);
                Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已加入团队「${ws.name}」！')),
                  );
                }
              } else if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('加入失败，请检查邀请码是否正确')),
                );
              }
            },
            child: const Text('加入'),
          ),
        ],
      ),
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
