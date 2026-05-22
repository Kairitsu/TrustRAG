import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/workspace_provider.dart';
import 'workspace_members_page.dart';

class TeamManagementPage extends ConsumerStatefulWidget {
  final Workspace workspace;

  const TeamManagementPage({super.key, required this.workspace});

  @override
  ConsumerState<TeamManagementPage> createState() => _TeamManagementPageState();
}

class _TeamManagementPageState extends ConsumerState<TeamManagementPage> {
  late Workspace _workspace;

  @override
  void initState() {
    super.initState();
    _workspace = widget.workspace;
  }

  Future<void> _regenerateInviteCode() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新生成邀请码'),
        content: const Text('重新生成后，旧邀请码将失效。确认继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.of(context).cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final newCode = await ref.read(workspaceProvider.notifier).regenerateInviteCode(_workspace.id);
    if (newCode != null && mounted) {
      setState(() {
        _workspace = Workspace(
          id: _workspace.id,
          name: _workspace.name,
          description: _workspace.description,
          type: _workspace.type,
          inviteCode: newCode,
          createdAt: _workspace.createdAt,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新邀请码: $newCode')),
      );
    }
  }

  void _copyInviteCode() {
    final code = _workspace.inviteCode;
    if (code == null) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('邀请码已复制'), duration: Duration(seconds: 2)),
    );
  }

  void _showTransferOwnershipDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('转让管理员'),
        content: const Text('此功能将在成员列表中选择新的管理员。转让后你将变为管理员角色。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(context).cancel)),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WorkspaceMembersPage()),
              );
            },
            child: const Text('前往成员管理'),
          ),
        ],
      ),
    );
  }

  void _showDisbandDialog() {
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散团队', style: TextStyle(color: Colors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('此操作不可撤销！团队中的所有文档、对话和审核记录将被永久删除。'),
            const SizedBox(height: 16),
            Text('请输入团队名称「${_workspace.name}」确认：', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              decoration: InputDecoration(
                hintText: _workspace.name,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(context).cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (confirmController.text.trim() != _workspace.name) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('团队名称不匹配')),
                );
                return;
              }
              try {
                final api = ref.read(apiClientProvider);
                await api.dio.delete('/workspaces/${_workspace.id}');
                await ref.read(workspaceProvider.notifier).loadWorkspaces();
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('团队已解散')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('解散失败: $e')),
                  );
                }
              }
            },
            child: const Text('确认解散'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${_workspace.name} — 团队设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                        child: Icon(Icons.groups, size: 28, color: theme.colorScheme.primary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_workspace.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                            if (_workspace.description != null)
                              Text(_workspace.description!, style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.vpn_key),
                  title: const Text('邀请码'),
                  subtitle: Text(
                    _workspace.inviteCode ?? '无',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: '复制邀请码',
                        onPressed: _workspace.inviteCode != null ? _copyInviteCode : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: '重新生成',
                        onPressed: _regenerateInviteCode,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('分享邀请'),
                  subtitle: const Text('将邀请码发送给团队成员'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    final code = _workspace.inviteCode ?? '';
                    Clipboard.setData(ClipboardData(
                      text: '邀请你加入 TrustRAG 团队「${_workspace.name}」\n邀请码: $code',
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('邀请信息已复制到剪贴板')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.group),
                  title: const Text('成员管理'),
                  subtitle: const Text('查看和管理团队成员'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WorkspaceMembersPage()),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            color: Colors.red.shade50,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.swap_horiz, color: Colors.orange.shade700),
                  title: Text('转让管理员', style: TextStyle(color: Colors.orange.shade700)),
                  subtitle: const Text('将团队所有权转让给其他成员'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showTransferOwnershipDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('解散团队', style: TextStyle(color: Colors.red)),
                  subtitle: const Text('永久删除团队及所有数据'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showDisbandDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
