import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/backend_manager.dart';
import '../../../core/services/mode_manager.dart';
import '../../auth/providers/auth_provider.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _urlController = TextEditingController();
  bool _showServerForm = false;
  bool _testingConnection = false;
  bool _connectionOk = false;
  String? _connectionError;
  bool _startingLocal = false;
  String? _localError;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _enterLocalMode() async {
    setState(() {
      _startingLocal = true;
      _localError = null;
    });

    try {
      await ref.read(modeProvider.notifier).setLocalMode();
      ref.invalidate(apiClientProvider);
      if (!mounted) return;
      context.go('/local-startup');
    } catch (e) {
      if (mounted) {
        setState(() => _localError = '无法进入本地模式，请重试');
      }
    } finally {
      if (mounted) setState(() => _startingLocal = false);
    }
  }

  Future<void> _testConnection() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _connectionError = '请输入服务器地址');
      return;
    }

    setState(() {
      _testingConnection = true;
      _connectionError = null;
      _connectionOk = false;
    });

    try {
      final testUrl = url.endsWith('/') ? '${url}health' : '$url/health';
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final resp = await dio.get(testUrl);
      if (resp.statusCode == 200) {
        setState(() => _connectionOk = true);
      } else {
        setState(() => _connectionError = '服务器返回异常状态码: ${resp.statusCode}');
      }
    } on DioException catch (e) {
      String msg;
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
          msg = '连接超时，请检查地址和网络';
          break;
        case DioExceptionType.connectionError:
          msg = '无法连接服务器，请检查地址是否正确';
          break;
        default:
          msg = e.message ?? '连接失败';
      }
      setState(() => _connectionError = msg);
    } catch (e) {
      setState(() => _connectionError = '连接失败: $e');
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  Future<void> _confirmServerMode() async {
    final url = _urlController.text.trim();
    await ref.read(modeProvider.notifier).setServerMode(url);
    ref.invalidate(apiClientProvider);
    final api = ref.read(apiClientProvider);
    api.dio.options.baseUrl = url;

    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showEmbedded = !kIsWeb && BackendManager.shouldRunEmbedded;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_stories_rounded,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'TrustRAG',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '可信赖的 RAG 知识工作台',
                  style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Text(
                  '选择你的使用方式',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 32),

                if (showEmbedded) ...[
                  _buildModeCard(
                    theme: theme,
                    icon: Icons.computer_rounded,
                    title: '本地使用',
                    subtitle: '数据保存在本地，无需服务器',
                    badges: const ['零配置', '离线可用', '隐私保护'],
                    recommended: true,
                    isLoading: _startingLocal,
                    error: _localError,
                    onTap: _startingLocal ? null : _enterLocalMode,
                  ),
                  const SizedBox(height: 16),
                ],

                _buildModeCard(
                  theme: theme,
                  icon: Icons.cloud_rounded,
                  title: '连接服务器',
                  subtitle: '连接远程服务器，支持团队协作',
                  badges: const ['多用户', '数据同步', '团队协作'],
                  recommended: !showEmbedded,
                  isLoading: false,
                  onTap: () => setState(() => _showServerForm = !_showServerForm),
                ),

                if (_showServerForm) ...[
                  const SizedBox(height: 20),
                  _buildServerForm(theme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<String> badges,
    required bool recommended,
    required bool isLoading,
    String? error,
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: recommended ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: recommended
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isLoading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 32, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(title, style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
                            if (recommended) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('推荐', style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                )),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        )),
                      ],
                    ),
                  ),
                  if (isLoading)
                    const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: badges.map((b) => Chip(
                  label: Text(b, style: const TextStyle(fontSize: 11)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                )).toList(),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    error,
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerForm(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('服务器地址', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'http://your-server.com/api',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) {
                if (_connectionOk || _connectionError != null) {
                  setState(() {
                    _connectionOk = false;
                    _connectionError = null;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testingConnection ? null : _testConnection,
                    icon: _testingConnection
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_find, size: 18),
                    label: const Text('测试连接'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _connectionOk ? _confirmServerMode : null,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('确认'),
                  ),
                ),
              ],
            ),
            if (_connectionOk) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade400, size: 18),
                  const SizedBox(width: 6),
                  Text('连接成功', style: TextStyle(color: Colors.green.shade400, fontSize: 13)),
                ],
              ),
            ],
            if (_connectionError != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _connectionError!,
                      style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
