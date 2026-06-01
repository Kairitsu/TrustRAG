import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/providers/app_version_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/backend_manager.dart';
import 'core/services/update_checker.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/widgets/update_dialog.dart';
import 'l10n/app_localizations.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

final localeProvider = StateProvider<Locale?>((ref) => null);

Future<void> setAppLocale(WidgetRef ref, Locale? locale) async {
  ref.read(localeProvider.notifier).state = locale;
  final prefs = await SharedPreferences.getInstance();
  if (locale != null) {
    await prefs.setString('app_locale', locale.languageCode);
  } else {
    await prefs.remove('app_locale');
  }
}

final rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  GoogleFonts.config.allowRuntimeFetching = false;

  await ApiClient.loadSavedServerUrl();

  if (BackendManager.shouldRunEmbedded) {
    final activeAccount = await ApiClient.getActiveAccount();
    debugPrint('[App] Starting embedded backend for account: ${activeAccount ?? "default"}...');
    await BackendManager().start(accountId: activeAccount);
    debugPrint('[App] Backend status: running=${BackendManager().isRunning}, url=${BackendManager().baseUrl}');
  }

  final prefs = await SharedPreferences.getInstance();
  final savedLocale = prefs.getString('app_locale');

  runApp(ProviderScope(
    overrides: [
      if (savedLocale != null)
        localeProvider.overrideWith((ref) => Locale(savedLocale)),
    ],
    child: const TrustRAGApp(),
  ));
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
      final versionAsync = ref.read(appVersionProvider);
      final version = versionAsync.valueOrNull;
      if (version == null) return;
      final release = await UpdateChecker().checkForUpdate(version);
      if (release != null) {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          UpdateDialog.show(ctx, release: release, currentVersion: version);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'TrustRAG',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      routerConfig: appRouter,
    );
  }
}
