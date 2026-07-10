import 'dart:convert';

import 'package:kelivo_max/core/models/sync_enums.dart';

/// Configuration for cloud sync.
/// Does NOT store password, access token, or refresh token.
class SyncConfig {
  final String serverUrl;
  final String username;
  final bool enabled;
  final Map<SyncCategory, bool> categories;
  final SyncDirection direction;
  final bool cloudExecutionEnabled;
  final int lastSyncCursor;
  final int? lastSyncAt;

  /// Default sync server URL.
  static const String defaultServerUrl =
      'https://3846-79545ece8ae76c54.monkeycode-ai.live';

  const SyncConfig({
    this.serverUrl = defaultServerUrl,
    this.username = '',
    this.enabled = true,
    Map<SyncCategory, bool>? categories,
    this.direction = SyncDirection.pullOnly,
    this.cloudExecutionEnabled = false,
    this.lastSyncCursor = 0,
    this.lastSyncAt,
  }) : categories = categories ?? const {};

  /// Returns whether a specific category is enabled for sync.
  bool isCategoryEnabled(SyncCategory cat) => categories[cat] ?? false;

  SyncConfig copyWith({
    String? serverUrl,
    String? username,
    bool? enabled,
    Map<SyncCategory, bool>? categories,
    SyncDirection? direction,
    bool? cloudExecutionEnabled,
    int? lastSyncCursor,
    int? Function()? lastSyncAt,
  }) {
    return SyncConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      enabled: enabled ?? this.enabled,
      categories: categories ?? Map.of(this.categories),
      direction: direction ?? this.direction,
      cloudExecutionEnabled:
          cloudExecutionEnabled ?? this.cloudExecutionEnabled,
      lastSyncCursor: lastSyncCursor ?? this.lastSyncCursor,
      lastSyncAt: lastSyncAt != null ? lastSyncAt() : this.lastSyncAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'username': username,
    'enabled': enabled,
    'categories': {
      for (final cat in SyncCategory.values)
        cat.toKey(): categories[cat] ?? false,
    },
    'direction': direction.toKey(),
    'cloudExecutionEnabled': cloudExecutionEnabled,
    'lastSyncCursor': lastSyncCursor,
    'lastSyncAt': lastSyncAt,
  };

  static SyncConfig fromJson(Map<String, dynamic> json) {
    final categoriesMap = <SyncCategory, bool>{};
    final rawCats = json['categories'];
    if (rawCats is Map) {
      for (final entry in rawCats.entries) {
        final cat = SyncCategoryExt.fromKey(entry.key.toString());
        if (cat != null && entry.value is bool) {
          categoriesMap[cat] = entry.value as bool;
        }
      }
    }

    SyncDirection dir = SyncDirection.pullOnly;
    final rawDir = json['direction'];
    if (rawDir is String) {
      dir = SyncDirectionExt.fromKey(rawDir) ?? SyncDirection.pullOnly;
    }

    return SyncConfig(
      serverUrl: json['serverUrl'] as String? ?? defaultServerUrl,
      username: json['username'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      categories: categoriesMap,
      direction: dir,
      cloudExecutionEnabled: json['cloudExecutionEnabled'] as bool? ?? false,
      lastSyncCursor: json['lastSyncCursor'] as int? ?? 0,
      lastSyncAt: json['lastSyncAt'] as int?,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static SyncConfig fromJsonString(String jsonString) {
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      return SyncConfig.fromJson(map);
    } catch (_) {
      return const SyncConfig();
    }
  }
}
