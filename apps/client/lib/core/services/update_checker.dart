import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReleaseInfo {
  final String version;
  final String tagName;
  final String releaseNotes;
  final String htmlUrl;
  final Map<String, String> assetUrls;
  final DateTime publishedAt;

  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.releaseNotes,
    required this.htmlUrl,
    required this.assetUrls,
    required this.publishedAt,
  });

  String? get currentPlatformUrl {
    if (kIsWeb) return null;
    if (Platform.isWindows) return assetUrls['windows_installer'] ?? assetUrls['windows_portable'];
    if (Platform.isMacOS) return assetUrls['macos'];
    if (Platform.isLinux) return assetUrls['linux'];
    if (Platform.isAndroid) return assetUrls['android'];
    return null;
  }
}

class UpdateChecker {
  static const _repo = 'XimilalaXiang/TrustRAG';
  static const _apiUrl = 'https://api.github.com/repos/$_repo/releases/latest';
  static const _cacheKey = 'update_checker_cache';
  static const _skipVersionKey = 'update_checker_skip_version';
  static const _lastCheckKey = 'update_checker_last_check';
  static const _cacheDuration = Duration(hours: 6);

  static final UpdateChecker _instance = UpdateChecker._();
  factory UpdateChecker() => _instance;
  UpdateChecker._();

  ReleaseInfo? _cached;

  /// Compare two semantic version strings. Returns:
  ///  1 if remote > local, 0 if equal, -1 if remote < local.
  static int compareVersions(String remote, String local) {
    final rParts = _parseVersion(remote);
    final lParts = _parseVersion(local);

    for (var i = 0; i < 3; i++) {
      final r = i < rParts.length ? rParts[i] : 0;
      final l = i < lParts.length ? lParts[i] : 0;
      if (r > l) return 1;
      if (r < l) return -1;
    }
    return 0;
  }

  static List<int> _parseVersion(String version) {
    final cleaned = version.replaceAll(RegExp(r'^v'), '').split('+').first;
    return cleaned.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  }

  /// Check for updates. Returns [ReleaseInfo] if a newer version is available.
  /// Returns null if up to date, check skipped by user, or on error.
  Future<ReleaseInfo?> checkForUpdate(String currentVersion, {bool force = false}) async {
    if (kIsWeb) return null;

    try {
      final prefs = await SharedPreferences.getInstance();

      if (!force) {
        final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
        final elapsed = DateTime.now().millisecondsSinceEpoch - lastCheck;
        if (elapsed < _cacheDuration.inMilliseconds && _cached != null) {
          return _shouldOffer(_cached!, currentVersion, prefs);
        }
      }

      final release = await _fetchLatestRelease();
      if (release == null) return null;

      _cached = release;
      prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      prefs.setString(_cacheKey, jsonEncode({
        'version': release.version,
        'tagName': release.tagName,
        'releaseNotes': release.releaseNotes,
        'htmlUrl': release.htmlUrl,
        'assetUrls': release.assetUrls,
        'publishedAt': release.publishedAt.toIso8601String(),
      }));

      return _shouldOffer(release, currentVersion, prefs);
    } catch (e) {
      debugPrint('[UpdateChecker] Error: $e');
      return null;
    }
  }

  ReleaseInfo? _shouldOffer(ReleaseInfo release, String currentVersion, SharedPreferences prefs) {
    if (compareVersions(release.version, currentVersion) <= 0) return null;

    final skipped = prefs.getString(_skipVersionKey);
    if (skipped == release.version) return null;

    return release;
  }

  /// Mark a version as skipped so the user won't be prompted again.
  Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_skipVersionKey, version);
  }

  /// Clear the skip marker.
  Future<void> clearSkip() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.remove(_skipVersionKey);
  }

  Future<ReleaseInfo?> _fetchLatestRelease() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(_apiUrl));
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'TrustRAG-App');

      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint('[UpdateChecker] GitHub API returned ${response.statusCode}');
        await response.drain();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      return _parseRelease(json);
    } finally {
      client.close();
    }
  }

  /// Exposed for testing. Prefer [checkForUpdate] for production use.
  static ReleaseInfo? parseReleaseForTest(Map<String, dynamic> json) => _parseRelease(json);

  static ReleaseInfo? _parseRelease(Map<String, dynamic> json) {
    final tagName = json['tag_name'] as String? ?? '';
    if (tagName.isEmpty) return null;

    final version = tagName.replaceAll(RegExp(r'^v'), '');
    final assets = json['assets'] as List? ?? [];

    final assetUrls = <String, String>{};
    for (final asset in assets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      final url = asset['browser_download_url'] as String? ?? '';
      if (url.isEmpty) continue;

      if (name.contains('windows') && name.contains('setup')) {
        assetUrls['windows_installer'] = url;
      } else if (name.contains('windows') && name.contains('portable')) {
        assetUrls['windows_portable'] = url;
      } else if (name.contains('macos')) {
        assetUrls['macos'] = url;
      } else if (name.contains('linux')) {
        assetUrls['linux'] = url;
      } else if (name.endsWith('.apk')) {
        assetUrls['android'] = url;
      } else if (name.contains('ios')) {
        assetUrls['ios'] = url;
      } else if (name.contains('web')) {
        assetUrls['web'] = url;
      }
    }

    return ReleaseInfo(
      version: version,
      tagName: tagName,
      releaseNotes: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      assetUrls: assetUrls,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// Parse release from cached JSON (for testing or offline scenarios).
  static ReleaseInfo? parseFromCache(String jsonString) {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      return ReleaseInfo(
        version: data['version'] as String,
        tagName: data['tagName'] as String,
        releaseNotes: data['releaseNotes'] as String,
        htmlUrl: data['htmlUrl'] as String,
        assetUrls: Map<String, String>.from(data['assetUrls'] as Map),
        publishedAt: DateTime.parse(data['publishedAt'] as String),
      );
    } catch (e) {
      debugPrint('[UpdateChecker] Cache parse error: $e');
      return null;
    }
  }
}
