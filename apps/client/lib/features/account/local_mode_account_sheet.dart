import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/account/account_mode_service.dart';

class LocalModeAccountSheet extends ConsumerWidget {
  const LocalModeAccountSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
          const SizedBox(height: 16),
          Icon(Icons.computer_rounded, size: 40, color: Colors.green.shade600),
          const SizedBox(height: 12),
          Text(
            '本地模式',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '数据仅保存在当前设备',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('切换到服务器账号'),
              onTap: () async {
                await AccountModeService.switchToServerMode(ref, context);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              leading: Icon(Icons.delete_forever, color: Colors.red.shade400),
              title: Text(
                '删除本机资料库',
                style: TextStyle(color: Colors.red.shade400),
              ),
              onTap: () async {
                await AccountModeService.deleteLocalLibrary(ref, context);
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}