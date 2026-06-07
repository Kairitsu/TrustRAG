import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/backend_manager.dart';
import '../../../core/services/diagnostic_logger.dart';
import '../../../core/services/local_bootstrap.dart';
import '../../../core/services/local_data_wipe.dart';
import '../../auth/providers/auth_provider.dart';

class DataManagementPage extends ConsumerStatefulWidget {
  const DataManagementPage({super.key});

  @override
  ConsumerState<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends ConsumerState<DataManagementPage> {
  Map<String, dynamic>? _dbInfo;
  bool _loading = false;
  String? _lastMessage;

  @override
  void initState() {
    super.initState();
    _loadDbInfo();
  }

  Future<void> _loadDbInfo() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/system/db-info');
      setState(() {
        _dbInfo = Map<String, dynamic>.from(resp.data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _dbInfo = null;
        _loading = false;
        _lastMessage = '无法获取数据库信息: $e';
      });
    }
  }

  Future<void> _backupDb() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post('/system/backup-db');
      final path = resp.data['backup_path'] ?? '未知路径';
      setState(() {
        _loading = false;
        _lastMessage = '备份成功: $path';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _lastMessage = '备份失败: $e';
      });
    }
  }

  Future<void> _resetDb() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('确认重置数据库'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('此操作将：', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('1. 自动备份当前数据库'),
            Text('2. 删除现有数据库'),
            Text('3. 创建全新的空数据库'),
            Text('4. 清除当前登录状态'),
            SizedBox(height: 12),
            Text(
              '所有工作区、文档、对话记录和模型配置都将丢失。备份文件会保留在应用数据目录中。',
              style: TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('/system/reset-db');
      setState(() {
        _loading = false;
        _lastMessage = '数据库已重置。请重新登录。';
      });
      if (mounted) {
        await ref.read(authProvider.notifier).logout();
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _lastMessage = '重置失败: $e';
      });
    }
  }

  Future<void> _resetLoginState() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置登录状态'),
        content: const Text('将清除所有账号的登录状态（Token），您需要重新登录。\n账号数据目录不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ApiClient.clearAllAccountData();
    final accounts = await ApiClient.getSavedAccounts();
    for (final email in accounts) {
      await ApiClient.removeAccount(email);
    }
    if (mounted) {
      ref.read(authProvider.notifier).logout();
      context.go('/login');
    }
  }

  Future<void> _wipeAllLocalDataAndReinit() async {
    final backup = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除本机全部数据'),
        content: const Text(
          '是否在清除前备份当前数据库到「文档/TrustRAG_backups」目录？\n\n'
          '建议选择「备份并清除」。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('不备份，直接清除')),
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('备份并清除'),
          ),
        ],
      ),
    );
    if (backup == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red.shade900, size: 24),
            const SizedBox(width: 8),
            const Text('确认清除本机全部数据'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('此操作将删除：', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('· 本地资料库、上传文件与向量索引'),
            Text('· 聊天记录'),
            Text('· 模型配置'),
            Text('· API Key / Token / Session'),
            Text('· 本地账号和工作区信息'),
            Text('· 缓存和日志'),
            SizedBox(height: 12),
            Text(
              '完成后将重新初始化本地模式。此操作不可恢复（备份文件除外）。',
              style: TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade900),
            child: const Text('确认清除并重新初始化'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    final result = await LocalDataWipe.wipeAllLocalData(backupFirst: backup);
    if (!mounted) return;

    if (result.success) {
      final bootstrap = await LocalBootstrap.bootstrap(
        ref.read(apiClientProvider),
        widgetRef: ref,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lastMessage = bootstrap.isSuccess
            ? '${result.message}\n本地模式已重新初始化。'
            : '${result.message}\n重新初始化未完成：${bootstrap.message}';
      });
      if (bootstrap.isSuccess) {
        context.go('/dashboard');
      } else {
        context.go('/onboarding');
      }
    } else {
      setState(() {
        _loading = false;
        _lastMessage = result.message;
      });
    }
  }

  Future<void> _clearAllAccounts() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red.shade900, size: 24),
            const SizedBox(width: 8),
            const Text('清除所有账号数据'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('此操作将：', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('1. 停止本地后端'),
            Text('2. 删除所有账号的本地数据目录'),
            Text('3. 清除所有登录状态和账号记录'),
            SizedBox(height: 12),
            Text(
              '所有账号的文档、对话记录、数据库都将被删除，且无法恢复。',
              style: TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade900),
            child: const Text('确认清除全部'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      if (BackendManager.shouldRunEmbedded) {
        await BackendManager().stop();
      }
      final accounts = await ApiClient.getSavedAccounts();
      for (final email in accounts) {
        if (BackendManager.shouldRunEmbedded) {
          await BackendManager().deleteAccountData(email);
        }
        await ApiClient.removeAccount(email);
      }
      await ApiClient.clearAllAccountData();
      setState(() {
        _loading = false;
        _lastMessage = '所有账号数据已清除。';
      });
      if (mounted) {
        ref.read(authProvider.notifier).logout();
        context.go('/login');
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _lastMessage = '清除失败: $e';
      });
    }
  }

  Future<void> _openLogDirectory() async {
    if (kIsWeb) {
      setState(() => _lastMessage = '日志目录仅在桌面客户端可用');
      return;
    }
    try {
      final dir = await DiagnosticLogger.logDirectory;
      await Directory(dir).create(recursive: true);
      if (Platform.isWindows) {
        await Process.run('explorer', [dir]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [dir]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dir]);
      }
      setState(() => _lastMessage = '已打开日志目录：$dir');
    } catch (e) {
      setState(() => _lastMessage = '打开日志目录失败: $e');
    }
  }

  Future<void> _copyDiagnosticLog() async {
    try {
      final text = await DiagnosticLogger.exportRecent();
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('诊断日志已复制到剪贴板'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      setState(() => _lastMessage = '复制诊断日志失败: $e');
    }
  }

  Future<void> _validateToken() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/system/validate-token');
      final valid = resp.data['valid'] == true;
      setState(() {
        _loading = false;
        _lastMessage = valid ? 'Token 有效，用户状态正常' : 'Token 无效或用户不存在，建议重新登录';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _lastMessage = 'Token 校验失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('本地数据管理'),
      ),
      body: _loading && _dbInfo == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_lastMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _lastMessage!.contains('失败') || _lastMessage!.contains('无效')
                            ? Colors.red.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _lastMessage!.contains('失败') || _lastMessage!.contains('无效')
                              ? Colors.red.shade200
                              : Colors.green.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _lastMessage!,
                              style: TextStyle(
                                fontSize: 13,
                                color: _lastMessage!.contains('失败') || _lastMessage!.contains('无效')
                                    ? Colors.red.shade800
                                    : Colors.green.shade800,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _lastMessage!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                              );
                            },
                            tooltip: '复制信息',
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() => _lastMessage = null),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  Text('数据库信息', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  if (_dbInfo != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _infoRow('Schema 版本', '${_dbInfo!['schema_version'] ?? '未知'}'),
                            _infoRow('数据库路径', '${_dbInfo!['db_path'] ?? '未知'}'),
                            _infoRow('用户数', '${_dbInfo!['user_count'] ?? '?'}'),
                            _infoRow('工作区数', '${_dbInfo!['workspace_count'] ?? '?'}'),
                            _infoRow('文档数', '${_dbInfo!['document_count'] ?? '?'}'),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _loadDbInfo,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('刷新'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '无法连接到本地后端或此功能仅在桌面模式可用',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),
                  Text('诊断工具', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  _actionCard(
                    icon: Icons.verified_user,
                    title: '校验登录状态',
                    subtitle: '检查当前 Token 与数据库用户是否一致',
                    onTap: _validateToken,
                    color: Colors.blue,
                  ),

                  const SizedBox(height: 8),

                  _actionCard(
                    icon: Icons.folder_open,
                    title: '打开日志目录',
                    subtitle: '查看 client-YYYY-MM-DD.log 等诊断文件',
                    onTap: _openLogDirectory,
                    color: Colors.indigo,
                  ),

                  const SizedBox(height: 8),

                  _actionCard(
                    icon: Icons.content_copy,
                    title: '复制诊断日志',
                    subtitle: '合并文件日志与当前会话日志，便于反馈问题',
                    onTap: _copyDiagnosticLog,
                    color: Colors.blueGrey,
                  ),

                  const SizedBox(height: 8),

                  _actionCard(
                    icon: Icons.backup,
                    title: '备份数据库',
                    subtitle: '创建当前数据库的备份副本',
                    onTap: _backupDb,
                    color: Colors.teal,
                  ),

                  const SizedBox(height: 24),
                  Text('危险操作', style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold, color: Colors.red,
                  )),
                  const SizedBox(height: 12),

                  _actionCard(
                    icon: Icons.delete_forever,
                    title: '重置数据库',
                    subtitle: '清除所有本地数据并重新初始化（会先自动备份）',
                    onTap: _resetDb,
                    color: Colors.red,
                  ),

                  if (BackendManager.shouldRunEmbedded) ...[
                    const SizedBox(height: 8),
                    _actionCard(
                      icon: Icons.delete_sweep,
                      title: '清除本机全部数据并重新初始化',
                      subtitle: '删除所有本地资料库、配置、登录状态，并重建默认工作区',
                      onTap: _wipeAllLocalDataAndReinit,
                      color: Colors.red.shade900,
                    ),
                    const SizedBox(height: 8),
                    _actionCard(
                      icon: Icons.restart_alt,
                      title: '重置登录状态',
                      subtitle: '清除所有账号登录状态，重新开始',
                      onTap: _resetLoginState,
                      color: Colors.deepOrange,
                    ),
                    const SizedBox(height: 8),
                    _actionCard(
                      icon: Icons.cleaning_services,
                      title: '清除所有账号数据',
                      subtitle: '删除所有账号的本地数据目录和登录信息',
                      onTap: _clearAllAccounts,
                      color: Colors.red.shade900,
                    ),
                  ],

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: _loading ? null : onTap,
      ),
    );
  }
}
