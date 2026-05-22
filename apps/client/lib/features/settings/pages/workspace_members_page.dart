import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/workspace_provider.dart';

class WorkspaceMember {
  final String id;
  final String userId;
  final String displayName;
  final String role;
  final String createdAt;

  WorkspaceMember({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.role,
    required this.createdAt,
  });

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) {
    return WorkspaceMember(
      id: json['id'],
      userId: json['user_id'],
      displayName: json['display_name'] ?? '',
      role: json['role'] ?? 'viewer',
      createdAt: json['created_at'] ?? '',
    );
  }
}

class WorkspaceMembersPage extends ConsumerStatefulWidget {
  const WorkspaceMembersPage({super.key});

  @override
  ConsumerState<WorkspaceMembersPage> createState() =>
      _WorkspaceMembersPageState();
}

class _WorkspaceMembersPageState extends ConsumerState<WorkspaceMembersPage> {
  List<WorkspaceMember> _members = [];
  bool _loading = true;
  String? _error;
  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/workspaces/${ws.id}/members');
      final data = resp.data as List;
      final members = data.map((j) => WorkspaceMember.fromJson(j)).toList();

      final currentUserId = ref.read(authProvider).user?['id'];
      String? myRole;
      for (final m in members) {
        if (m.userId == currentUserId) {
          myRole = m.role;
          break;
        }
      }

      setState(() {
        _members = members;
        _currentUserRole = myRole;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool get _canManage =>
      _currentUserRole == 'owner' || _currentUserRole == 'admin' || _currentUserRole == 'editor';

  Future<void> _inviteMember() async {
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;

    final emailController = TextEditingController();
    String selectedRole = 'viewer';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('邀请成员'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '邮箱地址',
                  hintText: 'user@example.com',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: const InputDecoration(
                  labelText: '角色',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'viewer', child: Text('查看者')),
                  DropdownMenuItem(value: 'editor', child: Text('编辑者')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedRole = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final email = emailController.text.trim();
                if (email.isNotEmpty && email.contains('@')) {
                  Navigator.pop(ctx, {'email': email, 'role': selectedRole});
                }
              },
              child: const Text('邀请'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();

    if (result == null) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('/workspaces/${ws.id}/members', data: result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已邀请 ${result['email']}')),
        );
      }
      _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('邀请失败: $e')),
        );
      }
    }
  }

  Future<void> _changeRole(WorkspaceMember member) async {
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;

    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('修改 ${member.displayName} 的角色'),
        children: [
          for (final role in ['owner', 'admin', 'editor', 'viewer'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, role),
              child: ListTile(
                leading: Icon(
                  member.role == role ? Icons.check_circle : Icons.circle_outlined,
                  color: member.role == role ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(_roleLabel(role)),
                subtitle: Text(_roleDescription(role)),
              ),
            ),
        ],
      ),
    );

    if (newRole == null || newRole == member.role) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.dio.put(
        '/workspaces/${ws.id}/members/${member.id}',
        data: {'role': newRole},
      );
      _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('修改失败: $e')),
        );
      }
    }
  }

  Future<void> _removeMember(WorkspaceMember member) async {
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除成员'),
        content: Text('确认将 ${member.displayName} 从工作区中移除？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.dio.delete('/workspaces/${ws.id}/members/${member.id}');
      _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移除失败: $e')),
        );
      }
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return '所有者';
      case 'editor':
        return '编辑者';
      case 'admin':
        return '管理员';
      default:
        return '查看者';
    }
  }

  String _roleDescription(String role) {
    switch (role) {
      case 'owner':
        return '完全控制权限，可管理成员、设置和 API 配置';
      case 'admin':
        return '可管理成员、LLM 配置和 API Key';
      case 'editor':
        return '可编辑文档和对话';
      default:
        return '仅可查看文档和对话，提交审核';
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'owner':
        return Colors.deepPurple;
      case 'editor':
        return Colors.blue;
      case 'admin':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(selectedWorkspaceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('成员管理${ws != null ? " — ${ws.name}" : ""}'),
        actions: [
          if (_canManage)
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: '邀请成员',
              onPressed: _inviteMember,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loadMembers,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text('加载失败: $_error'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _loadMembers, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_members.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('暂无成员', style: TextStyle(color: Colors.grey.shade500)),
            if (_canManage) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _inviteMember,
                icon: const Icon(Icons.person_add),
                label: const Text('邀请成员'),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _members.length,
      itemBuilder: (context, index) {
        final m = _members[index];
        final isSelf = m.userId == ref.read(authProvider).user?['id'];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _roleColor(m.role).withValues(alpha: 0.15),
              child: Text(
                m.displayName.isNotEmpty ? m.displayName[0].toUpperCase() : '?',
                style: TextStyle(
                    color: _roleColor(m.role), fontWeight: FontWeight.bold),
              ),
            ),
            title: Row(
              children: [
                Text(m.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                if (isSelf) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('我',
                        style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.primary)),
                  ),
                ],
              ],
            ),
            subtitle: Text(_roleLabel(m.role)),
            trailing: _canManage && !isSelf
                ? PopupMenuButton<String>(
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'role', child: Text('修改角色')),
                      const PopupMenuItem(
                          value: 'remove',
                          child:
                              Text('移除', style: TextStyle(color: Colors.red))),
                    ],
                    onSelected: (v) {
                      if (v == 'role') _changeRole(m);
                      if (v == 'remove') _removeMember(m);
                    },
                  )
                : Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _roleColor(m.role).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_roleLabel(m.role),
                        style: TextStyle(
                            fontSize: 12,
                            color: _roleColor(m.role),
                            fontWeight: FontWeight.w500)),
                  ),
          ),
        );
      },
    );
  }
}
