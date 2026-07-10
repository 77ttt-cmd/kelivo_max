import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/sync_provider.dart';
import '../../../core/models/sync_config.dart';
import '../../../core/models/sync_enums.dart';
import '../../../core/services/sync/sync_credential_store.dart';
import '../../../core/services/sync/sync_api_client.dart';
import '../../../core/services/sync/sync_ledger.dart';
import '../../../core/services/haptics.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_switch.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  late final TextEditingController _serverUrlCtl;
  late final TextEditingController _usernameCtl;
  late final TextEditingController _passwordCtl;

  final SyncCredentialStore _credentialStore = SyncCredentialStore();
  bool _passwordLoaded = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    final cfg = settings.syncConfig;
    _serverUrlCtl = TextEditingController(text: cfg.serverUrl);
    _usernameCtl = TextEditingController(text: cfg.username);
    _passwordCtl = TextEditingController();
    _loadPassword();
    // Check login status on init
    context.read<SyncProvider>().checkLoginStatus(_credentialStore);
  }

  Future<void> _loadPassword() async {
    final pw = await _credentialStore.readPassword();
    if (mounted) {
      setState(() {
        _passwordCtl.text = pw ?? '';
        _passwordLoaded = true;
      });
    }
  }

  Future<void> _savePassword(String value) async {
    if (value.isEmpty) {
      await _credentialStore.deletePassword();
    } else {
      await _credentialStore.savePassword(value);
    }
  }

  void _saveConfig({
    String? serverUrl,
    String? username,
    bool? enabled,
    SyncDirection? direction,
    Map<SyncCategory, bool>? categories,
    bool? cloudExecutionEnabled,
  }) {
    final settings = context.read<SettingsProvider>();
    settings.setSyncConfig(
      settings.syncConfig.copyWith(
        serverUrl: serverUrl ?? _serverUrlCtl.text,
        username: username ?? _usernameCtl.text,
        enabled: enabled,
        direction: direction,
        categories: categories,
        cloudExecutionEnabled: cloudExecutionEnabled,
      ),
    );
  }

  @override
  void dispose() {
    _serverUrlCtl.dispose();
    _usernameCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final cfg = settings.syncConfig;
    final syncProvider = context.watch<SyncProvider>();

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.syncPageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // --- Server section ---
          _sectionCard(
            children: [
              IosFormTextField(
                label: l10n.syncServerUrl,
                controller: _serverUrlCtl,
                hintText: 'https://',
                keyboardType: TextInputType.url,
                onChanged: (v) => _saveConfig(serverUrl: v),
              ),
              _divider(context),
              IosFormTextField(
                label: l10n.syncUsername,
                controller: _usernameCtl,
                onChanged: (v) => _saveConfig(username: v),
              ),
              _divider(context),
              IosFormTextField(
                label: l10n.syncPassword,
                controller: _passwordCtl,
                enabled: _passwordLoaded,
                hintText: _passwordLoaded ? null : '...',
                onChanged: _savePassword,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // --- Login / Logout ---
          _sectionCard(
            children: [
              if (syncProvider.isLoggedIn) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.syncLoggedInStatus(cfg.username),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: AppFontWeights.medium,
                            color: cs.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _divider(context),
                _actionRow(
                  context,
                  icon: Lucide.CloudOff,
                  label: l10n.syncLogoutButton,
                  onTap: syncProvider.state == SyncState.syncing
                      ? null
                      : () async {
                          final settings = context.read<SettingsProvider>();
                          await syncProvider.logout(
                            credentialStore: _credentialStore,
                            settingsProvider: settings,
                          );
                          if (mounted) {
                            final newCfg = settings.syncConfig;
                            _serverUrlCtl.text = newCfg.serverUrl;
                            _usernameCtl.text = newCfg.username;
                          }
                        },
                ),
              ] else ...[
                _actionRow(
                  context,
                  icon: Lucide.User,
                  label: l10n.syncLoginButton,
                  busy: syncProvider.state == SyncState.syncing,
                  onTap: syncProvider.state == SyncState.syncing
                      ? null
                      : () {
                          final settings = context.read<SettingsProvider>();
                          syncProvider.login(
                            serverUrl: _serverUrlCtl.text.trim(),
                            username: _usernameCtl.text.trim(),
                            password: _passwordCtl.text,
                            credentialStore: _credentialStore,
                            settingsProvider: settings,
                          );
                        },
                ),
                _divider(context),
                _actionRow(
                  context,
                  icon: Lucide.Plus,
                  label: l10n.syncRegisterButton,
                  onTap: syncProvider.state == SyncState.syncing
                      ? null
                      : () async {
                          final client = SyncApiClient(
                            serverUrl: _serverUrlCtl.text.trim(),
                            credentialStore: _credentialStore,
                          );
                          try {
                            await client.register(
                              _usernameCtl.text.trim(),
                              _passwordCtl.text,
                            );
                            client.dispose();
                            if (!mounted) return;
                            // Auto-login after register
                            final settings = this.context
                                .read<SettingsProvider>();
                            await syncProvider.login(
                              serverUrl: _serverUrlCtl.text.trim(),
                              username: _usernameCtl.text.trim(),
                              password: _passwordCtl.text,
                              credentialStore: _credentialStore,
                              settingsProvider: settings,
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(
                              this.context,
                            ).showSnackBar(SnackBar(content: Text('$e')));
                            client.dispose();
                          }
                        },
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // --- Enable toggle ---
          _sectionCard(
            children: [
              _toggleRow(
                context,
                label: l10n.syncEnableLabel,
                value: cfg.enabled,
                onChanged: (v) => _saveConfig(enabled: v),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // --- Sync Direction ---
          _header(l10n.syncDirectionLabel),
          _sectionCard(
            children: [
              _radioRow(
                context,
                label: l10n.syncDirectionPullOnly,
                selected: cfg.direction == SyncDirection.pullOnly,
                onTap: () => _saveConfig(direction: SyncDirection.pullOnly),
              ),
              _divider(context),
              _radioRow(
                context,
                label: l10n.syncDirectionBidirectional,
                selected: cfg.direction == SyncDirection.bidirectional,
                onTap: () =>
                    _saveConfig(direction: SyncDirection.bidirectional),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // --- Category toggles ---
          _sectionCard(children: _buildCategoryToggles(context, l10n, cfg)),

          const SizedBox(height: 16),

          // --- Cloud Execution ---
          _sectionCard(
            children: [
              _toggleRow(
                context,
                label: l10n.syncCloudExecutionLabel,
                subtitle: l10n.syncCloudExecutionHint,
                value: cfg.cloudExecutionEnabled,
                onChanged: (v) => _saveConfig(cloudExecutionEnabled: v),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // --- Key Encryption Notice ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Lucide.Shield,
                  size: 14,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.syncKeyEncryptionNotice,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // --- Action buttons ---
          _sectionCard(
            children: [
              _actionRow(
                context,
                icon: Lucide.RefreshCw,
                label: l10n.syncNowButton,
                busy: syncProvider.state == SyncState.syncing,
                onTap: syncProvider.state == SyncState.syncing
                    ? null
                    : () => syncProvider.syncNow(),
              ),
              _divider(context),
              _actionRow(
                context,
                icon: Lucide.Cable,
                label: l10n.syncTestConnectionButton,
                onTap: () {
                  // Placeholder — will be implemented in Phase 1
                },
              ),
            ],
          ),

          // --- Status ---
          if (syncProvider.lastMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 4),
              child: Text(
                syncProvider.lastMessage,
                style: TextStyle(
                  fontSize: 12,
                  color: syncProvider.state == SyncState.error
                      ? cs.error
                      : cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),

          if (cfg.lastSyncAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                _formatSyncTime(cfg.lastSyncAt!),
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),

          const SizedBox(height: 24),

          // --- Incognito Wipe ---
          _sectionCard(
            children: [
              _destructiveActionRow(
                context,
                icon: Lucide.Trash2,
                label: l10n.syncIncognitoWipeButton,
                busy: syncProvider.state == SyncState.syncing,
                onTap: syncProvider.state == SyncState.syncing
                    ? null
                    : () => _handleIncognitoWipe(context),
              ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _formatSyncTime(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _handleIncognitoWipe(BuildContext ctx) async {
    final l10n = AppLocalizations.of(ctx)!;
    final settings = ctx.read<SettingsProvider>();
    final syncProvider = ctx.read<SyncProvider>();

    // Initialize ledger and get preview
    final ledger = SyncLedger();
    await ledger.init();
    final preview = syncProvider.incognitoWipePreview(ledger: ledger);

    if (!mounted) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final cs = Theme.of(dialogCtx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(l10n.syncIncognitoWipeConfirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.syncIncognitoWipeConfirmBody),
              if (preview.totalCount > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '${preview.totalCount}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(l10n.syncIncognitoWipeCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: Text(l10n.syncIncognitoWipeConfirmOk),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    // Execute wipe
    await syncProvider.incognitoWipe(
      ledger: ledger,
      credentialStore: _credentialStore,
      resetSyncConfig: (cfg) async => settings.setSyncConfig(cfg),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.syncIncognitoWipeDone)));

    // Refresh text controllers to reflect reset config
    final newCfg = settings.syncConfig;
    _serverUrlCtl.text = newCfg.serverUrl;
    _usernameCtl.text = newCfg.username;
    _passwordCtl.text = '';
  }

  List<Widget> _buildCategoryToggles(
    BuildContext context,
    AppLocalizations l10n,
    SyncConfig cfg,
  ) {
    final entries = <MapEntry<SyncCategory, String>>[
      MapEntry(SyncCategory.chats, l10n.syncCategoryChats),
      MapEntry(SyncCategory.providers, l10n.syncCategoryProviders),
      MapEntry(SyncCategory.assistants, l10n.syncCategoryAssistants),
      MapEntry(SyncCategory.quickPhrases, l10n.syncCategoryQuickPhrases),
      MapEntry(SyncCategory.mcp, l10n.syncCategoryMcp),
      MapEntry(SyncCategory.searchServices, l10n.syncCategorySearchServices),
      MapEntry(SyncCategory.ttsServices, l10n.syncCategoryTtsServices),
      MapEntry(SyncCategory.settings, l10n.syncCategorySettings),
      MapEntry(SyncCategory.files, l10n.syncCategoryFiles),
    ];

    final widgets = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      widgets.add(
        _toggleRow(
          context,
          label: entry.value,
          value: cfg.isCategoryEnabled(entry.key),
          onChanged: (v) {
            final updated = Map<SyncCategory, bool>.from(cfg.categories);
            updated[entry.key] = v;
            _saveConfig(categories: updated);
          },
        ),
      );
      if (i < entries.length - 1) {
        widgets.add(_divider(context));
      }
    }
    return widgets;
  }
}

// --- Shared iOS-style widgets ---

Widget _sectionCard({required List<Widget> children}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final Color bg = isDark
          ? Colors.white10
          : Colors.white.withValues(alpha: 0.96);
      return Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
            width: 0.6,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: children),
        ),
      );
    },
  );
}

Widget _header(String text) {
  return Builder(
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: AppFontWeights.semibold,
            color: cs.onSurface.withValues(alpha: 0.8),
          ),
        ),
      );
    },
  );
}

Widget _divider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 6,
    thickness: 0.6,
    indent: 12,
    endIndent: 12,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}

Widget _toggleRow(
  BuildContext context, {
  required String label,
  required bool value,
  required ValueChanged<bool> onChanged,
  String? subtitle,
}) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: AppFontWeights.medium,
                  color: cs.onSurface.withValues(alpha: 0.9),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
        ),
        IosSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );
}

Widget _radioRow(
  BuildContext context, {
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {
      Haptics.soft();
      onTap();
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: AppFontWeights.medium,
                color: cs.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ),
          if (selected) Icon(Lucide.Check, size: 18, color: cs.primary),
        ],
      ),
    ),
  );
}

Widget _actionRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  VoidCallback? onTap,
  bool busy = false,
}) {
  final cs = Theme.of(context).colorScheme;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : Icon(icon, size: 18, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: AppFontWeights.medium,
                color: cs.primary,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _destructiveActionRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  VoidCallback? onTap,
  bool busy = false,
}) {
  final cs = Theme.of(context).colorScheme;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.error,
                    ),
                  )
                : Icon(icon, size: 18, color: cs.error),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: AppFontWeights.medium,
                color: cs.error,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// Icon-only tactile button for AppBar (matches settings_page pattern)
class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 22,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final pressColor = base.withValues(alpha: 0.7);
    final icon = Icon(
      widget.icon,
      size: widget.size,
      color: _pressed ? pressColor : base,
    );

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          Haptics.light();
          widget.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: icon,
        ),
      ),
    );
  }
}
