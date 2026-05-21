import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/router/app_router.dart';
import 'core/services/backend_manager.dart';
import 'core/services/update_checker.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/widgets/update_dialog.dart';

const appVersion = '0.2.1';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

final rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  GoogleFonts.config.allowRuntimeFetching = false;

  if (BackendManager.shouldRunEmbedded) {
    debugPrint('[App] Starting embedded backend...');
    await BackendManager().start();
    debugPrint('[App] Backend status: running=${BackendManager().isRunning}, url=${BackendManager().baseUrl}');
  }

  runApp(const ProviderScope(child: TrustRAGApp()));
}

class TrustRAGApp extends ConsumerStatefulWidget {
  const TrustRAGApp({super.key});

  @override
  ConsumerState<TrustRAGApp> createState() => _TrustRAGAppState();
}

class _TrustRAGAppState extends ConsumerState<TrustRAGApp> {
  @override
  void initState() {
    super.initState();
    _scheduleUpdateCheck();
  }

  void _scheduleUpdateCheck() {
    Future.delayed(const Duration(seconds: 3), () async {
      final release = await UpdateChecker().checkForUpdate(appVersion);
      if (release != null) {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          UpdateDialog.show(ctx, release: release, currentVersion: appVersion);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'TrustRAG',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
