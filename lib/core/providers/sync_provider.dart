import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:Kelivo/core/models/sync_config.dart';
import 'package:Kelivo/core/models/sync_enums.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/sync/incognito_wipe.dart';
import 'package:Kelivo/core/services/sync/sync_api_client.dart';
import 'package:Kelivo/core/services/sync/sync_category_handler.dart';
import 'package:Kelivo/core/services/sync/sync_credential_store.dart';
import 'package:Kelivo/core/services/sync/sync_ledger.dart';

/// Runtime sync states.
enum SyncState { idle, syncing, error }

/// Provider for sync operations, exposed globally via MultiProvider.
class SyncProvider extends ChangeNotifier {
  SyncState _state = SyncState.idle;
  String _lastMessage = '';
  int _conflictCount = 0;
  bool _isLoggedIn = false;

  SyncState get state => _state;
  String get lastMessage => _lastMessage;
  int get conflictCount => _conflictCount;
  bool get isLoggedIn => _isLoggedIn;

  // Stored dependencies — set via [configure] before calling [syncNow].
  SyncApiClient? _apiClient;
  SyncLedger? _ledger;
  SettingsProvider? _settingsProvider;

  /// Store the dependencies needed by [syncNow].
  ///
  /// Call this once after construction (e.g. during app initialisation)
  /// so that zero-argument [syncNow] calls from the UI work correctly.
  void configure({
    required SyncApiClient apiClient,
    required SyncLedger ledger,
    required SettingsProvider settingsProvider,
  }) {
    _apiClient = apiClient;
    _ledger = ledger;
    _settingsProvider = settingsProvider;
  }

  /// Pull remote changes and apply them locally.
  ///
  /// Uses stored dependencies from [configure].  Optional overrides can be
  /// passed directly — useful for tests.
  Future<void> syncNow({
    SyncApiClient? apiClient,
    SyncLedger? ledger,
    SettingsProvider? settingsProvider,
  }) async {
    final client = apiClient ?? _apiClient;
    final lgr = ledger ?? _ledger;
    final settings = settingsProvider ?? _settingsProvider;

    if (client == null || lgr == null || settings == null) {
      _state = SyncState.idle;
      _lastMessage = 'Sync not configured';
      notifyListeners();
      return;
    }

    final config = settings.syncConfig;
    if (!config.enabled) return;

    _state = SyncState.syncing;
    _lastMessage = '';
    _conflictCount = 0;
    notifyListeners();

    try {
      // Determine enabled categories.
      final enabledCategories = SyncCategory.values
          .where((c) => config.isCategoryEnabled(c))
          .toList();

      if (enabledCategories.isEmpty) {
        _state = SyncState.idle;
        _lastMessage = 'No categories enabled';
        notifyListeners();
        return;
      }

      final sessionId = const Uuid().v4();
      var cursor = config.lastSyncCursor;
      var totalApplied = 0;

      // Pull loop with pagination.
      bool hasMore = true;
      while (hasMore) {
        final result = await client.pullChanges(cursor, enabledCategories);

        // Group entries by category.
        final byCategory = <SyncCategory, List<Map<String, dynamic>>>{};
        for (final entry in result.entries) {
          final catKey = entry['category'] as String?;
          if (catKey == null) continue;
          final cat = SyncCategoryExt.fromKey(catKey);
          if (cat == null) continue;
          if (!enabledCategories.contains(cat)) continue;
          byCategory.putIfAbsent(cat, () => []).add(entry);
        }

        // Apply changes per category.
        for (final catEntry in byCategory.entries) {
          final handler = syncHandlerFor(catEntry.key);
          await handler.applyRemoteChanges(catEntry.value);

          // Write ledger entries for each applied record.
          for (final change in catEntry.value) {
            await lgr.append(
              category: catEntry.key,
              recordId: change['recordId'] as String? ?? '',
              direction: 'pull',
              sessionId: sessionId,
            );
          }
          totalApplied += catEntry.value.length;
        }

        cursor = result.latestSeq;
        hasMore = result.hasMore;
      }

      // --- PUSH (only if bidirectional) ---
      if (config.direction == SyncDirection.bidirectional) {
        final allChanges = <Map<String, dynamic>>[];

        for (final cat in enabledCategories) {
          try {
            final handler = syncHandlerFor(cat);
            final changes = await handler.collectLocalChanges(
              config.lastSyncCursor,
            );
            for (final change in changes) {
              change['category'] = cat.toKey();
              allChanges.add(change);
            }
          } catch (e) {
            // Skip categories where collectLocalChanges fails;
            // some handlers may still have limited implementations.
          }
        }

        if (allChanges.isNotEmpty) {
          final pushResult = await client.pushChanges(allChanges);

          // Record push entries in ledger.
          for (final change in allChanges) {
            final recordId = change['recordId'] as String? ?? '';
            final catKey = change['category'] as String? ?? '';
            final cat = SyncCategoryExt.fromKey(catKey);
            if (cat != null) {
              await lgr.append(
                category: cat,
                recordId: recordId,
                direction: 'push',
                sessionId: sessionId,
              );
            }
          }

          _conflictCount = pushResult.skipped.length;
          totalApplied += pushResult.accepted;

          // Update cursor if push returned a newer seq.
          if (pushResult.latestSeq > cursor) {
            cursor = pushResult.latestSeq;
          }
        }
      }

      // Persist the new cursor and timestamp.
      await settings.setSyncConfig(
        config.copyWith(
          lastSyncCursor: cursor,
          lastSyncAt: () => DateTime.now().millisecondsSinceEpoch,
        ),
      );

      _state = SyncState.idle;
      _lastMessage = 'Synced $totalApplied records';
    } catch (e) {
      _state = SyncState.error;
      _lastMessage = 'Sync failed: $e';
    }
    notifyListeners();
  }

  /// Execute incognito wipe using provided dependencies.
  Future<void> incognitoWipe({
    required SyncLedger ledger,
    required SyncCredentialStore credentialStore,
    required Future<void> Function(SyncConfig) resetSyncConfig,
  }) async {
    _state = SyncState.syncing;
    _lastMessage = '';
    notifyListeners();

    try {
      final wipe = IncognitoWipe(
        ledger: ledger,
        credentialStore: credentialStore,
        resetSyncConfig: resetSyncConfig,
      );
      await wipe.run();
      _state = SyncState.idle;
      _lastMessage = 'Incognito wipe completed';
      _conflictCount = 0;
    } catch (e) {
      _state = SyncState.error;
      _lastMessage = 'Wipe failed: $e';
    }
    notifyListeners();
  }

  /// Get preview of incognito wipe.
  IncognitoWipePreview incognitoWipePreview({required SyncLedger ledger}) {
    final wipe = IncognitoWipe(
      ledger: ledger,
      credentialStore: SyncCredentialStore(),
      resetSyncConfig: (_) async {},
    );
    return wipe.preview();
  }

  /// Login to sync server.
  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
    required SyncCredentialStore credentialStore,
    required SettingsProvider settingsProvider,
  }) async {
    _state = SyncState.syncing;
    _lastMessage = '';
    notifyListeners();

    try {
      final client = SyncApiClient(
        serverUrl: serverUrl,
        credentialStore: credentialStore,
      );
      await client.login(username, password);
      await credentialStore.savePassword(password);

      // Update SyncConfig
      await settingsProvider.setSyncConfig(
        settingsProvider.syncConfig.copyWith(
          serverUrl: serverUrl,
          username: username,
          enabled: true,
        ),
      );

      _isLoggedIn = true;
      _state = SyncState.idle;
      _lastMessage = 'Logged in successfully';

      // Best-effort push token registration.
      try {
        final pushToken = await _getPushToken();
        if (pushToken != null) {
          await client.registerDevice(_getPlatform(), pushToken);
        }
      } catch (_) {
        // Push registration is non-critical; do not fail the login.
      }

      client.dispose();
    } catch (e) {
      _state = SyncState.error;
      _lastMessage = 'Login failed: $e';
    }
    notifyListeners();
  }

  /// Logout from sync server.
  Future<void> logout({
    required SyncCredentialStore credentialStore,
    required SettingsProvider settingsProvider,
  }) async {
    // Best-effort push token unregistration before clearing credentials.
    try {
      final pushToken = await _getPushToken();
      if (pushToken != null) {
        final config = settingsProvider.syncConfig;
        if (config.serverUrl.isNotEmpty) {
          final client = SyncApiClient(
            serverUrl: config.serverUrl,
            credentialStore: credentialStore,
          );
          try {
            await client.unregisterDevice(pushToken);
          } finally {
            client.dispose();
          }
        }
      }
    } catch (_) {
      // Push unregistration is non-critical; proceed with logout.
    }

    await credentialStore.clearAll();
    await settingsProvider.setSyncConfig(
      settingsProvider.syncConfig.copyWith(enabled: false),
    );
    _isLoggedIn = false;
    _lastMessage = 'Logged out';
    notifyListeners();
  }

  /// Check if user is logged in (has stored access token).
  Future<void> checkLoginStatus(SyncCredentialStore credentialStore) async {
    final token = await credentialStore.readAccessToken();
    _isLoggedIn = token != null && token.isNotEmpty;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Push token helpers
  // ---------------------------------------------------------------------------

  /// Return the platform string for device registration.
  String _getPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// Obtain the device push token.
  ///
  /// - **iOS**: Reads the APNs device token via a native MethodChannel. The
  ///   token is registered by `AppDelegate.registerForRemoteNotifications()`.
  ///   No Firebase dependency — APNs works in China.
  /// - **Android / Desktop**: Returns `null`. Android push in China cannot
  ///   use FCM (Google services blocked). Instead, the client relies on the
  ///   WebSocket relay (foreground) and `recoverCloudTasks` (app restart).
  static const _pushTokenChannel = MethodChannel('app.push_token');

  Future<String?> _getPushToken() async {
    if (!Platform.isIOS) return null;
    try {
      final token = await _pushTokenChannel.invokeMethod<String>('getToken');
      return (token != null && token.isNotEmpty) ? token : null;
    } catch (_) {
      return null;
    }
  }
}
