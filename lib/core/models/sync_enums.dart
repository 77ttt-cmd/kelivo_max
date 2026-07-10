/// Enums for cloud sync feature.
library;

/// Categories of data that can be synced.
enum SyncCategory {
  chats,
  providers,
  assistants,
  quickPhrases,
  mcp,
  searchServices,
  ttsServices,
  settings,
  files,
}

/// Direction of sync.
enum SyncDirection { pullOnly, bidirectional }

extension SyncCategoryExt on SyncCategory {
  /// Convert to a deterministic string key for JSON serialization.
  String toKey() => name;

  /// Parse a string key back to SyncCategory, returns null for unknown input.
  static SyncCategory? fromKey(String key) {
    for (final v in SyncCategory.values) {
      if (v.name == key) return v;
    }
    return null;
  }
}

extension SyncDirectionExt on SyncDirection {
  /// Convert to a deterministic string key for JSON serialization.
  String toKey() => name;

  /// Parse a string key back to SyncDirection, returns null for unknown input.
  static SyncDirection? fromKey(String key) {
    for (final v in SyncDirection.values) {
      if (v.name == key) return v;
    }
    return null;
  }
}
