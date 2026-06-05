import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/account/account_display_helper.dart';
import '../../../core/account/account_mode_service.dart';
import '../../../core/api/api_client.dart';
import '../../../core/services/session_reset.dart';
import '../auth/providers/auth_provider.dart';
import '../dashboard/providers/workspace_provider.dart';

class ServerModeAccountSheet extends ConsumerStatefulWidget {
  final String currentEmail;

  const ServerModeAccountSheet({super.key, required this.currentEmail});

  @override
  ConsumerState<ServerModeAccountSheet> createState() =>
      _ServerModeAccountSheetState();
}

class _ServerModeAccountSheetState extends ConsumerState<ServerModeAccountSheet> {
  List<String> _savedAccounts = [];
  Set<String> _accountsWithToken = {};

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await ApiClient.getSavedAccounts();
    final withToken = <String>{};
    for (final email in accounts) {
      if (await ApiClient.hasTokenForAccount(email)) {
        withToken.add(email);
      }
    }
    if (mounted) {
      setState(() {
        _savedAccounts = accounts;
        _accountsWithToken = withToken;
      });
    }
  }

  Future<void> _switchAccount(String email) async {
    final nav = Navigator.of(context);
    nav.pop();
    final result = await ApiClient.switchToAccount(email);
    if (!mounted) return;
    switch (result) {
      case ApiClient.switchOk:
        resetAccountScopedState(ref);
        ref.invalidate(authProvider);
        await ref.read(authProvider.notifier).checkAuthStatus();
        ref.read(workspaceProvider.notifier).loadWorkspaces();
      case ApiClient.switchNeedLogin:
        await ApiClient.setLastLoginEmail(email);
        if (!mounted) return;
        context.go('/login?email=${Uri.encodeComponent(email)}');
      case ApiClient.switchFailed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('切换账号失败，已回滚到原账号'),
            duration: Duration(seconds: 3),
          ),
        );
    }
  }

  void _showSwitchAccountList() {
    final others = _savedAccounts
        .where((e) =>
            e != widget.currentEmail &&
            !AccountDisplayHelper.isInternalLocalAccount(e))
        .toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('切换账号', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (others.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无其他已登录过的服务器账号'),
              )
            else
              ...others.map((email) => ListTile(
                    title: Text(email),
                    subtitle: Text(
                      _accountsWithToken.contains(email)
                          ? '可切换'
                          : '需重新登录',
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _switchAccount(email);
                    },
                  )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountFlow() async {
    Navigator.pop(context);
    final currentEmail = widget.currentEmail;

    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除账号'),
        content: const Text(
          '彻底删除账号会删除你在服务器上的账号资料。删除后，你将无法再使用该账号和密码登录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (step1 != true || !mounted) return;

    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final emailMatch = emailController.text.trim().toLowerCase() ==
              currentEmail.trim().toLowerCase();
          return AlertDialog(
            title: const Text('确认删除账号'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '此操作不可逆。服务器上的账号、工作区、上传文档、知识库、对话记录、索引、引用审核记录等资料将被删除。删除后你将无法继续使用该账号和密码登录，只能重新注册账号或使用其他账号。',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: '输入当前账号邮箱以确认',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    decoration: const InputDecoration(labelText: '当前密码'),
                    obscureText: true,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: emailMatch && passwordController.text.isNotEmpty
                    ? () => Navigator.pop(ctx, true)
                    : null,
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('永久删除'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) {
      emailController.dispose();
      passwordController.dispose();
      return;
    }

    final password = passwordController.text;
    final confirmEmail = emailController.text;
    emailController.dispose();
    passwordController.dispose();

    final err = await ref.read(authProvider.notifier).deleteServerAccount(
          password: password,
          confirmEmail: confirmEmail,
        );

    if (!mounted) return;

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
      return;
    }

    resetAccountScopedState(ref);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('账号已彻底删除')),
    );
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final email = widget.currentEmail;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withAlpha(60),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    email.isNotEmpty ? email[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    email,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(Icons.logout, color: Colors.red.shade400),
            title: Text('退出登录', style: TextStyle(color: Colors.red.shade400)),
            onTap: () {
              Navigator.pop(context);
              AccountModeService.serverLogout(ref, context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('切换账号'),
            onTap: _showSwitchAccountList,
          ),
          ListTile(
            leading: const Icon(Icons.computer_outlined),
            title: const Text('切换使用方式'),
            onTap: () {
              Navigator.pop(context);
              AccountModeService.switchToLocalMode(ref, context);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
            title: Text(
              '彻底删除账号',
              style: TextStyle(color: Colors.red.shade700),
            ),
            onTap: _showDeleteAccountFlow,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}