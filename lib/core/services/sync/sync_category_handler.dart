import 'package:Kelivo/core/models/sync_enums.dart';
import 'package:Kelivo/core/services/sync/handlers/assistants_sync_handler.dart';
import 'package:Kelivo/core/services/sync/handlers/chats_sync_handler.dart';
import 'package:Kelivo/core/services/sync/handlers/files_sync_handler.dart';
import 'package:Kelivo/core/services/sync/handlers/mcp_sync_handler.dart';
import 'package:Kelivo/core/services/sync/handlers/providers_sync_handler.dart';
import 'package:Kelivo/core/services/sync/handlers/quick_phrases_sync_handler.dart';
import 'package:Kelivo/core/services/sync/handlers/search_services_sync_handler.dart';
import 'package:Kelivo/core/services/sync/handlers/settings_sync_handler.dart';
import 'package:Kelivo/core/services/sync/handlers/tts_services_sync_handler.dart';

/// Abstract contract for per-category sync operations.
///
/// Each [SyncCategory] has one handler that knows how to:
/// - Collect local changes since a given cursor (for push)
/// - Apply remote changes from the server (for pull)
abstract class SyncCategoryHandler {
  /// Which category this handler manages.
  SyncCategory get category;

  /// Collect local records changed since [sinceCursor].
  /// Returns a list of JSON-serializable maps.
  Future<List<Map<String, dynamic>>> collectLocalChanges(int sinceCursor);

  /// Apply a batch of remote changes to local storage.
  Future<void> applyRemoteChanges(List<Map<String, dynamic>> changes);
}

/// Returns the handler for [category].
SyncCategoryHandler syncHandlerFor(SyncCategory category) {
  return switch (category) {
    SyncCategory.chats => ChatsSyncHandler(),
    SyncCategory.providers => ProvidersSyncHandler(),
    SyncCategory.assistants => AssistantsSyncHandler(),
    SyncCategory.quickPhrases => QuickPhrasesSyncHandler(),
    SyncCategory.mcp => McpSyncHandler(),
    SyncCategory.searchServices => SearchServicesSyncHandler(),
    SyncCategory.ttsServices => TtsServicesSyncHandler(),
    SyncCategory.settings => SettingsSyncHandler(),
    SyncCategory.files => FilesSyncHandler(),
  };
}
