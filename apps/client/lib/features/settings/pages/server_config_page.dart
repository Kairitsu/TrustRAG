import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../providers/server_config_provider.dart';

class ServerConfigPage extends ConsumerStatefulWidget {
  const ServerConfigPage({super.key});

  @override
  ConsumerState<ServerConfigPage> createState() => _ServerConfigPageState();
}

class _ServerConfigPageState extends ConsumerState<ServerConfigPage> {
  late TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    final config = ref.read(serverConfigProvider);
    _urlController = TextEditingController(text: config.customUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final config = ref.watch(serverConfigProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.serverConfig)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildConnectionStatusCard(config, s, theme),
          const SizedBox(height: 16),
          _buildModeSelector(config, s, theme),
          const SizedBox(height: 16),
          if (config.mode == ServerMode.custom)
            _buildCustomServerForm(config, s, theme),
        ],
      ),
    );
  }

  Widget _buildConnectionStatusCard(
      ServerConfig config, S s, ThemeData theme) {
    final IconData icon;
    final Color color;
    final String label;

    switch (config.connectionStatus) {
      case ServerConnectionStatus.connected:
        icon = Icons.check_circle;
        color = Colors.green;
        label = s.serverConnected;
      case ServerConnectionStatus.disconnected:
        icon = Icons.cancel;
        color = Colors.red;
        label = s.serverDisconnected;
      case ServerConnectionStatus.checking:
        icon = Icons.sync;
        color = Colors.orange;
        label = s.connectionChecking;
      case ServerConnectionStatus.unknown:
        icon = Icons.help_outline;
        color = Colors.grey;
        label = s.connectionUnknown;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            config.connectionStatus == ServerConnectionStatus.checking
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: color)),
                  const SizedBox(height: 2),
                  Text(
                    s.currentServerUrl(config.effectiveUrl),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: config.connectionStatus ==
                      ServerConnectionStatus.checking
                  ? null
                  : () =>
                      ref.read(serverConfigProvider.notifier).checkConnection(),
              icon: const Icon(Icons.wifi_find, size: 18),
              label: Text(s.testConnection),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelector(
      ServerConfig config, S s, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildModeCard(
          title: s.officialServer,
          subtitle: s.officialServerDesc,
          icon: Icons.cloud,
          color: theme.colorScheme.primary,
          selected: config.mode == ServerMode.official,
          onTap: () {
            ref.read(serverConfigProvider.notifier).setMode(ServerMode.official);
          },
          trailing: Text(
            ServerConfig.officialUrl,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        ),
        const SizedBox(height: 8),
        _buildModeCard(
          title: s.customServer,
          subtitle: s.customServerDesc,
          icon: Icons.dns,
          color: Colors.orange,
          selected: config.mode == ServerMode.custom,
          onTap: () {
            ref.read(serverConfigProvider.notifier).setMode(ServerMode.custom);
          },
        ),
      ],
    );
  }

  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: color, width: 2)
            : BorderSide.none,
      ),
      color: selected
          ? color.withValues(alpha: 0.05)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: selected
                    ? color.withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.1),
                child: Icon(icon, color: selected ? color : Colors.grey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey)),
                    if (trailing != null) ...[
                      const SizedBox(height: 4),
                      trailing,
                    ],
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: color)
              else
                Icon(Icons.radio_button_unchecked,
                    color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomServerForm(
      ServerConfig config, S s, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.serverAddress,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: s.serverAddressHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => _urlController.clear(),
                ),
              ),
              keyboardType: TextInputType.url,
              onChanged: (value) {
                ref.read(serverConfigProvider.notifier).setCustomUrl(value.trim());
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      final url = _urlController.text.trim();
                      if (url.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(s.serverAddressEmpty)),
                        );
                        return;
                      }
                      ref.read(serverConfigProvider.notifier).setCustomUrl(url);
                      ref
                          .read(serverConfigProvider.notifier)
                          .checkConnection();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(s.serverConfigSaved),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                    icon: const Icon(Icons.save, size: 18),
                    label: Text(s.saveServerConfig),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
