import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/update_checker.dart';

class UpdateDialog extends StatelessWidget {
  final ReleaseInfo release;
  final String currentVersion;
  final VoidCallback? onSkip;
  final VoidCallback? onLater;

  const UpdateDialog({
    super.key,
    required this.release,
    required this.currentVersion,
    this.onSkip,
    this.onLater,
  });

  /// Convenience method to show the dialog.
  static Future<void> show(
    BuildContext context, {
    required ReleaseInfo release,
    required String currentVersion,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(
        release: release,
        currentVersion: currentVersion,
        onSkip: () {
          UpdateChecker().skipVersion(release.version);
          Navigator.of(context).pop();
        },
        onLater: () => Navigator.of(context).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platformUrl = release.currentPlatformUrl;

    return AlertDialog(
      icon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.system_update_alt_rounded,
          color: theme.colorScheme.primary,
          size: 32,
        ),
      ),
      title: const Text('发现新版本'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _versionBadge(context, 'v$currentVersion', isOld: true),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: theme.colorScheme.primary, size: 20),
                  ),
                  _versionBadge(context, 'v${release.version}', isOld: false),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (release.releaseNotes.isNotEmpty) ...[
              Text('更新内容', style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              )),
              const SizedBox(height: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Markdown(
                    data: release.releaseNotes,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    styleSheet: MarkdownStyleSheet(
                      p: theme.textTheme.bodyMedium,
                      h1: theme.textTheme.titleMedium,
                      h2: theme.textTheme.titleSmall,
                      listBullet: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onSkip,
          child: const Text('跳过此版本'),
        ),
        TextButton(
          onPressed: onLater,
          child: const Text('稍后提醒'),
        ),
        FilledButton.icon(
          onPressed: () => _openDownload(context, platformUrl),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('前往下载'),
        ),
      ],
      actionsAlignment: MainAxisAlignment.end,
    );
  }

  Widget _versionBadge(BuildContext context, String text, {required bool isOld}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isOld
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: isOld
            ? null
            : Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isOld ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary,
          fontSize: 13,
        ),
      ),
    );
  }

  Future<void> _openDownload(BuildContext context, String? platformUrl) async {
    final url = platformUrl ?? release.htmlUrl;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接: $e')),
        );
      }
    }
  }
}
