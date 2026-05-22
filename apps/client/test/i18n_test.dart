import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/l10n/app_localizations.dart';

void main() {
  group('i18n / Localization', () {
    test('S supports zh, en, ja, ko locales', () {
      expect(S.supportedLocales.map((l) => l.languageCode), containsAll(['zh', 'en', 'ja', 'ko']));
    });

    test('S.supportedLocales has at least 4 entries', () {
      expect(S.supportedLocales.length, greaterThanOrEqualTo(4));
    });

    test('S.localizationsDelegates is not empty', () {
      expect(S.localizationsDelegates, isNotEmpty);
    });

    testWidgets('Chinese locale resolves correctly', (tester) async {
      late S strings;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Builder(builder: (context) {
            strings = S.of(context);
            return const SizedBox();
          }),
        ),
      );
      expect(strings.navChat, '对话');
      expect(strings.settings, '设置');
      expect(strings.cancel, '取消');
      expect(strings.about, '关于');
    });

    testWidgets('English locale resolves correctly', (tester) async {
      late S strings;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Builder(builder: (context) {
            strings = S.of(context);
            return const SizedBox();
          }),
        ),
      );
      expect(strings.navChat, 'Chat');
      expect(strings.settings, 'Settings');
      expect(strings.cancel, 'Cancel');
      expect(strings.about, 'About');
    });

    testWidgets('Japanese locale resolves correctly', (tester) async {
      late S strings;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Builder(builder: (context) {
            strings = S.of(context);
            return const SizedBox();
          }),
        ),
      );
      expect(strings.navChat, 'チャット');
      expect(strings.settings, '設定');
      expect(strings.cancel, 'キャンセル');
    });

    testWidgets('Korean locale resolves correctly', (tester) async {
      late S strings;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Builder(builder: (context) {
            strings = S.of(context);
            return const SizedBox();
          }),
        ),
      );
      expect(strings.navChat, '채팅');
      expect(strings.settings, '설정');
      expect(strings.cancel, '취소');
      expect(strings.languageKo, '한국어');
    });

    testWidgets('Parameterized strings work correctly', (tester) async {
      late S strings;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Builder(builder: (context) {
            strings = S.of(context);
            return const SizedBox();
          }),
        ),
      );
      expect(strings.loadFailed('timeout'), contains('timeout'));
      expect(strings.selectedCount(5), contains('5'));
      expect(strings.citationSources(3), contains('3'));
      expect(strings.currentVersion('0.2.1'), contains('0.2.1'));
    });

    testWidgets('All four locales have same keys (no missing translations)', (tester) async {
      final locales = [const Locale('zh'), const Locale('en'), const Locale('ja'), const Locale('ko')];
      final results = <String, S>{};

      for (final locale in locales) {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Builder(builder: (context) {
              results[locale.languageCode] = S.of(context);
              return const SizedBox();
            }),
          ),
        );
      }

      for (final s in results.values) {
        expect(s.appTitle, isNotEmpty);
        expect(s.navChat, isNotEmpty);
        expect(s.navDocuments, isNotEmpty);
        expect(s.navReview, isNotEmpty);
        expect(s.navWorkspaces, isNotEmpty);
        expect(s.navSearch, isNotEmpty);
        expect(s.navSettings, isNotEmpty);
        expect(s.settings, isNotEmpty);
        expect(s.about, isNotEmpty);
        expect(s.language, isNotEmpty);
        expect(s.languageZh, isNotEmpty);
        expect(s.languageEn, isNotEmpty);
        expect(s.languageJa, isNotEmpty);
        expect(s.languageKo, isNotEmpty);
      }
    });
  });
}
