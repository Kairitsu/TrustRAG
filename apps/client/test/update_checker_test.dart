import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/core/services/update_checker.dart';

void main() {
  group('UpdateChecker.compareVersions', () {
    test('newer version returns 1', () {
      expect(UpdateChecker.compareVersions('1.0.1', '1.0.0'), 1);
      expect(UpdateChecker.compareVersions('1.1.0', '1.0.0'), 1);
      expect(UpdateChecker.compareVersions('2.0.0', '1.9.9'), 1);
      expect(UpdateChecker.compareVersions('0.3.0', '0.2.1'), 1);
    });

    test('same version returns 0', () {
      expect(UpdateChecker.compareVersions('1.0.0', '1.0.0'), 0);
      expect(UpdateChecker.compareVersions('0.2.1', '0.2.1'), 0);
    });

    test('older version returns -1', () {
      expect(UpdateChecker.compareVersions('1.0.0', '1.0.1'), -1);
      expect(UpdateChecker.compareVersions('0.2.0', '0.2.1'), -1);
    });

    test('handles v prefix', () {
      expect(UpdateChecker.compareVersions('v1.0.1', '1.0.0'), 1);
      expect(UpdateChecker.compareVersions('v1.0.0', 'v1.0.0'), 0);
    });

    test('handles build metadata (+ suffix)', () {
      expect(UpdateChecker.compareVersions('0.2.1+5', '0.2.1+4'), 0);
      expect(UpdateChecker.compareVersions('0.3.0+1', '0.2.1+5'), 1);
    });

    test('handles partial versions', () {
      expect(UpdateChecker.compareVersions('1.0', '1.0.0'), 0);
      expect(UpdateChecker.compareVersions('2', '1.9.9'), 1);
    });
  });

  group('ReleaseInfo parsing', () {
    test('parses GitHub release JSON correctly', () {
      final json = {
        'tag_name': 'v0.3.0',
        'body': '## Changes\n- New feature\n- Bug fix',
        'html_url': 'https://github.com/XimilalaXiang/TrustRAG/releases/tag/v0.3.0',
        'published_at': '2026-06-01T12:00:00Z',
        'assets': [
          {
            'name': 'TrustRAG-Setup-Windows-x64.exe',
            'browser_download_url': 'https://example.com/windows-setup.exe',
          },
          {
            'name': 'trustrag-windows-x64-portable.zip',
            'browser_download_url': 'https://example.com/windows-portable.zip',
          },
          {
            'name': 'trustrag-macos.tar.gz',
            'browser_download_url': 'https://example.com/macos.tar.gz',
          },
          {
            'name': 'trustrag-linux-x64.tar.gz',
            'browser_download_url': 'https://example.com/linux.tar.gz',
          },
          {
            'name': 'app-release.apk',
            'browser_download_url': 'https://example.com/app.apk',
          },
        ],
      };

      final release = UpdateChecker.parseReleaseForTest(json);
      expect(release, isNotNull);
      expect(release!.version, '0.3.0');
      expect(release.tagName, 'v0.3.0');
      expect(release.releaseNotes, contains('New feature'));
      expect(release.assetUrls['windows_installer'], 'https://example.com/windows-setup.exe');
      expect(release.assetUrls['windows_portable'], 'https://example.com/windows-portable.zip');
      expect(release.assetUrls['macos'], 'https://example.com/macos.tar.gz');
      expect(release.assetUrls['linux'], 'https://example.com/linux.tar.gz');
      expect(release.assetUrls['android'], 'https://example.com/app.apk');
    });

    test('handles missing assets gracefully', () {
      final json = {
        'tag_name': 'v0.1.0',
        'body': '',
        'html_url': 'https://github.com/test/repo/releases/tag/v0.1.0',
        'published_at': '2026-01-01T00:00:00Z',
        'assets': <Map<String, dynamic>>[],
      };

      final release = UpdateChecker.parseReleaseForTest(json);
      expect(release, isNotNull);
      expect(release!.version, '0.1.0');
      expect(release.assetUrls, isEmpty);
    });

    test('returns null for empty tag_name', () {
      final json = {
        'tag_name': '',
        'body': 'test',
        'html_url': '',
        'published_at': '2026-01-01T00:00:00Z',
        'assets': [],
      };

      final release = UpdateChecker.parseReleaseForTest(json);
      expect(release, isNull);
    });
  });

  group('Cache serialization', () {
    test('round-trips through cache JSON', () {
      final original = ReleaseInfo(
        version: '0.5.0',
        tagName: 'v0.5.0',
        releaseNotes: 'Big update!',
        htmlUrl: 'https://example.com',
        assetUrls: {'linux': 'https://example.com/linux.tar.gz'},
        publishedAt: DateTime.utc(2026, 6, 1),
      );

      final jsonString = jsonEncode({
        'version': original.version,
        'tagName': original.tagName,
        'releaseNotes': original.releaseNotes,
        'htmlUrl': original.htmlUrl,
        'assetUrls': original.assetUrls,
        'publishedAt': original.publishedAt.toIso8601String(),
      });

      final restored = UpdateChecker.parseFromCache(jsonString);
      expect(restored, isNotNull);
      expect(restored!.version, original.version);
      expect(restored.tagName, original.tagName);
      expect(restored.releaseNotes, original.releaseNotes);
      expect(restored.htmlUrl, original.htmlUrl);
      expect(restored.assetUrls['linux'], original.assetUrls['linux']);
    });

    test('handles invalid JSON gracefully', () {
      final result = UpdateChecker.parseFromCache('not valid json');
      expect(result, isNull);
    });
  });
}
