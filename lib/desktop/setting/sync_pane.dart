import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/sync_enums.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/sync_provider.dart';
import '../../core/services/sync/sync_api_client.dart';
import '../../core/services/sync/sync_credential_store.dart';
import '../../core/services/sync/sync_ledger.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/ios_switch.dart';
import '../../theme/app_font_weights.dart';
import '../widgets/desktop_select_dropdown.dart';

class DesktopSyncPane extends StatefulWidget {
  const DesktopSyncPane({super.key});

  @override
  State<DesktopSyncPane> createState() => _DesktopSyncPaneState();
}

class _DesktopSyncPaneState extends State<DesktopSyncPane> {
  late final TextEditingController _serverUrlCtl;
  late final TextEditingController _usernameCtl;
  late final TextEditingController _passwordCtl;
  final FocusNode _serverUrlFn = FocusNode();
  final FocusNode _usernameFn = FocusNode();
  final FocusNode _passwordFn = FocusNode();

  bool _enabled = false;
  SyncDirection _direction = SyncDirection.pullOnly;
  Map<SyncCategory, bool> _categories = {};
  bool _cloudExecution = false;
  bool _obscurePassword = true;

  final SyncCredentialStore _credentialStore = SyncCredentialStore();

  @override
  void initState() {
    super.initState();
    final sp = context.read<SettingsProvider>();
    final cfg = sp.syncConfig;
    _enabled = cfg.enabled;
    _direction = cfg.direction;
    _categories = Map.of(cfg.categories);
    _cloudExecution = cfg.cloudExecutionEnabled;

    _serverUrlCtl = TextEditingController(text: cfg.serverUrl);
    _usernameCtl = TextEditingController(text: cfg.username);
    _passwordCtl = TextEditingController();

    // Load password from secure storage
    _credentialStore.readPassword().then((pwd) {
      if (mounted && pwd != null) {
        _passwordCtl.text = pwd;
      }
    });

    _serverUrlFn.addListener(() {
      if (!_serverUrlFn.hasFocus) _persistConfig();
    });
    _usernameFn.addListener(() {
      if (!_usernameFn.hasFocus) _persistConfig();
    });
    _passwordFn.addListener(() {
      if (!_passwordFn.hasFocus) {
        _credentialStore.savePassword(_passwordCtl.text);
      }
    });

    // Check login status on init
    context.read<SyncProvider>().checkLoginStatus(_credentialStore);
  }

  @override
  void dispose() {
    _serverUrlCtl.dispose();
    _usernameCtl.dispose();
    _passwordCtl.dispose();
    _serverUrlFn.dispose();
    _usernameFn.dispose();
    _passwordFn.dispose();
    super.dispose();
  }

  Future<void> _persistConfig() async {
    final sp = context.read<SettingsProvider>();
    await sp.setSyncConfig(
      sp.syncConfig.copyWith(
        serverUrl: _serverUrlCtl.text.trim(),
        username: _usernameCtl.text.trim(),
        enabled: _enabled,
        direction: _direction,
        categories: Map.of(_categories),
        cloudExecutionEnabled: _cloudExecution,
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
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
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

    // Refresh local state to reflect reset config
    final newCfg = settings.syncConfig;
    setState(() {
      _serverUrlCtl.text = newCfg.serverUrl;
      _usernameCtl.text = newCfg.username;
      _passwordCtl.text = '';
      _enabled = newCfg.enabled;
      _direction = newCfg.direction;
      _categories = Map.of(newCfg.categories);
      _cloudExecution = newCfg.cloudExecutionEnabled;
    });
  }

  String _categoryLabel(SyncCategory cat, AppLocalizations l10n) {
    switch (cat) {
      case SyncCategory.chats:
        return l10n.syncCategoryChats;
      case SyncCategory.providers:
        return l10n.syncCategoryProviders;
      case SyncCategory.assistants:
        return l10n.syncCategoryAssistants;
      case SyncCategory.quickPhrases:
        return l10n.syncCategoryQuickPhrases;
      case SyncCategory.mcp:
        return l10n.syncCategoryMcp;
      case SyncCategory.searchServices:
        return l10n.syncCategorySearchServices;
      case SyncCategory.ttsServices:
        return l10n.syncCategoryTtsServices;
      case SyncCategory.settings:
        return l10n.syncCategorySettings;
      case SyncCategory.files:
        return l10n.syncCategoryFiles;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final syncProvider = context.watch<SyncProvider>();

    return Container(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            children: [
              // Title
              SizedBox(
                height: 36,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.syncPageTitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: AppFontWeights.regular,
                      color: cs.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Connection section
              _sectionCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      l10n.syncPageTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.onSurface.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                  _ItemRow(
                    label: l10n.syncServerUrl,
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 140,
                        maxWidth: 420,
                      ),
                      child: TextField(
                        controller: _serverUrlCtl,
                        focusNode: _serverUrlFn,
                        style: const TextStyle(fontSize: 14),
                        decoration: _deskInputDecoration(
                          context,
                        ).copyWith(hintText: 'https://'),
                      ),
                    ),
                  ),
                  _rowDivider(context),
                  _ItemRow(
                    label: l10n.syncUsername,
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 140,
                        maxWidth: 420,
                      ),
                      child: TextField(
                        controller: _usernameCtl,
                        focusNode: _usernameFn,
                        style: const TextStyle(fontSize: 14),
                        decoration: _deskInputDecoration(context),
                      ),
                    ),
                  ),
                  _rowDivider(context),
                  _ItemRow(
                    label: l10n.syncPassword,
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 140,
                        maxWidth: 420,
                      ),
                      child: TextField(
                        controller: _passwordCtl,
                        focusNode: _passwordFn,
                        obscureText: _obscurePassword,
                        style: const TextStyle(fontSize: 14),
                        decoration: _deskInputDecoration(context).copyWith(
                          hintText: '••••••••',
                          suffixIcon: _PasswordVisibilityToggle(
                            obscure: _obscurePassword,
                            onToggle: () {
                              setState(
                                () => _obscurePassword = !_obscurePassword,
                              );
                            },
                          ),
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _rowDivider(context),
                  _ItemRow(
                    label: l10n.syncEnableLabel,
                    vpad: 4,
                    trailing: IosSwitch(
                      value: _enabled,
                      onChanged: (v) {
                        setState(() => _enabled = v);
                        _persistConfig();
                      },
                    ),
                  ),
                  _rowDivider(context),
                  _ItemRow(
                    label: l10n.syncDirectionLabel,
                    trailing: SizedBox(
                      width: 220,
                      child: DesktopSelectDropdown<SyncDirection>(
                        value: _direction,
                        options: [
                          DesktopSelectOption(
                            value: SyncDirection.pullOnly,
                            label: l10n.syncDirectionPullOnly,
                          ),
                          DesktopSelectOption(
                            value: SyncDirection.bidirectional,
                            label: l10n.syncDirectionBidirectional,
                          ),
                        ],
                        onSelected: (v) {
                          setState(() => _direction = v);
                          _persistConfig();
                        },
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Category toggles section
              _sectionCard(
                children: [
                  for (int i = 0; i < SyncCategory.values.length; i++) ...[
                    if (i > 0) _rowDivider(context),
                    _ItemRow(
                      label: _categoryLabel(SyncCategory.values[i], l10n),
                      vpad: 4,
                      trailing: IosSwitch(
                        value: _categories[SyncCategory.values[i]] ?? false,
                        onChanged: (v) {
                          setState(() {
                            _categories[SyncCategory.values[i]] = v;
                          });
                          _persistConfig();
                        },
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 10),

              // Cloud execution + encryption notice
              _sectionCard(
                children: [
                  _ItemRow(
                    label: l10n.syncCloudExecutionLabel,
                    vpad: 4,
                    trailing: IosSwitch(
                      value: _cloudExecution,
                      onChanged: (v) {
                        setState(() => _cloudExecution = v);
                        _persistConfig();
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Text(
                      l10n.syncCloudExecutionHint,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  _rowDivider(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l10n.syncKeyEncryptionNotice,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Login / Logout section
              _sectionCard(
                children: [
                  if (syncProvider.isLoggedIn) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Text(
                        l10n.syncLoggedInStatus(
                          context.watch<SettingsProvider>().syncConfig.username,
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          _DeskIosDestructiveButton(
                            label: l10n.syncLogoutButton,
                            dense: true,
                            onTap: syncProvider.state == SyncState.syncing
                                ? () {}
                                : () async {
                                    final sp = context.read<SettingsProvider>();
                                    await syncProvider.logout(
                                      credentialStore: _credentialStore,
                                      settingsProvider: sp,
                                    );
                                    if (!mounted) return;
                                    final newCfg = sp.syncConfig;
                                    setState(() {
                                      _enabled = newCfg.enabled;
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          _DeskIosButton(
                            label: syncProvider.state == SyncState.syncing
                                ? l10n.syncStatusSyncing
                                : l10n.syncLoginButton,
                            filled: true,
                            dense: true,
                            onTap: syncProvider.state == SyncState.syncing
                                ? () {}
                                : () {
                                    syncProvider.login(
                                      serverUrl: _serverUrlCtl.text.trim(),
                                      username: _usernameCtl.text.trim(),
                                      password: _passwordCtl.text,
                                      credentialStore: _credentialStore,
                                      settingsProvider: context
                                          .read<SettingsProvider>(),
                                    );
                                  },
                          ),
                          const SizedBox(width: 8),
                          _DeskIosButton(
                            label: l10n.syncRegisterButton,
                            filled: false,
                            dense: true,
                            onTap: syncProvider.state == SyncState.syncing
                                ? () {}
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
                                      final sp = this.context
                                          .read<SettingsProvider>();
                                      await syncProvider.login(
                                        serverUrl: _serverUrlCtl.text.trim(),
                                        username: _usernameCtl.text.trim(),
                                        password: _passwordCtl.text,
                                        credentialStore: _credentialStore,
                                        settingsProvider: sp,
                                      );
                                    } catch (e) {
                                      client.dispose();
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        this.context,
                                      ).showSnackBar(
                                        SnackBar(content: Text('$e')),
                                      );
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 10),

              // Sync Now / Test Connection + status
              _sectionCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        _DeskIosButton(
                          label: syncProvider.state == SyncState.syncing
                              ? l10n.syncStatusSyncing
                              : l10n.syncNowButton,
                          filled: true,
                          dense: true,
                          onTap: syncProvider.state == SyncState.syncing
                              ? () {}
                              : () => syncProvider.syncNow(),
                        ),
                        const SizedBox(width: 8),
                        _DeskIosButton(
                          label: l10n.syncTestConnectionButton,
                          filled: false,
                          dense: true,
                          onTap: syncProvider.state == SyncState.syncing
                              ? () {}
                              : () => syncProvider.syncNow(),
                        ),
                      ],
                    ),
                  ),
                  if (syncProvider.lastMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Text(
                        syncProvider.lastMessage,
                        style: TextStyle(
                          fontSize: 12,
                          color: syncProvider.state == SyncState.error
                              ? cs.error
                              : cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  if (context.watch<SettingsProvider>().syncConfig.lastSyncAt !=
                      null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Text(
                        _formatSyncTime(
                          context
                              .watch<SettingsProvider>()
                              .syncConfig
                              .lastSyncAt!,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              // Incognito Wipe
              _sectionCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        _DeskIosDestructiveButton(
                          label: l10n.syncIncognitoWipeButton,
                          dense: true,
                          onTap: syncProvider.state == SyncState.syncing
                              ? () {}
                              : () => _handleIncognitoWipe(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Helpers (matched with network_proxy_pane style) ---

Widget _rowDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    height: 1,
    color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
  );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.label, required this.trailing, this.vpad = 8});
  final String label;
  final Widget trailing;
  final double vpad;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: vpad),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurface.withValues(alpha: 0.88),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Align(alignment: Alignment.centerRight, child: trailing),
        ],
      ),
    );
  }
}

class _DeskIosButton extends StatefulWidget {
  const _DeskIosButton({
    required this.label,
    required this.filled,
    required this.dense,
    required this.onTap,
  });
  final String label;
  final bool filled;
  final bool dense;
  final VoidCallback onTap;
  @override
  State<_DeskIosButton> createState() => _DeskIosButtonState();
}

class _DeskIosButtonState extends State<_DeskIosButton> {
  bool _hover = false;
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = widget.filled
        ? Colors.white
        : cs.onSurface.withValues(alpha: 0.9);
    final bg = widget.filled
        ? (_hover ? cs.primary.withValues(alpha: 0.92) : cs.primary)
        : (_hover
              ? (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05))
              : Colors.transparent);
    final borderColor = widget.filled
        ? Colors.transparent
        : cs.outlineVariant.withValues(alpha: isDark ? 0.22 : 0.18);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: widget.dense ? 8 : 12,
              horizontal: 12,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: textColor,
                fontWeight: AppFontWeights.semibold,
                fontSize: widget.dense ? 13 : 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeskIosDestructiveButton extends StatefulWidget {
  const _DeskIosDestructiveButton({
    required this.label,
    required this.dense,
    required this.onTap,
  });
  final String label;
  final bool dense;
  final VoidCallback onTap;
  @override
  State<_DeskIosDestructiveButton> createState() =>
      _DeskIosDestructiveButtonState();
}

class _DeskIosDestructiveButtonState extends State<_DeskIosDestructiveButton> {
  bool _hover = false;
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover ? cs.error.withValues(alpha: 0.1) : Colors.transparent;
    final borderColor = cs.error.withValues(alpha: isDark ? 0.35 : 0.3);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: widget.dense ? 8 : 12,
              horizontal: 12,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: cs.error,
                fontWeight: AppFontWeights.semibold,
                fontSize: widget.dense ? 13 : 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _sectionCard({required List<Widget> children}) {
  return Builder(
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final baseBg = isDark
          ? Colors.white10
          : Colors.white.withValues(alpha: 0.96);
      return Container(
        decoration: BoxDecoration(
          color: baseBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.08),
            width: 0.8,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    },
  );
}

InputDecoration _deskInputDecoration(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cs = Theme.of(context).colorScheme;
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: isDark ? Colors.white10 : const Color(0xFFF7F7F9),
    hintStyle: TextStyle(
      fontSize: 14,
      color: cs.onSurface.withValues(alpha: 0.5),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: cs.outlineVariant.withValues(alpha: 0.12),
        width: 0.6,
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: cs.outlineVariant.withValues(alpha: 0.12),
        width: 0.6,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: cs.primary.withValues(alpha: 0.35),
        width: 0.8,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );
}

class _PasswordVisibilityToggle extends StatefulWidget {
  const _PasswordVisibilityToggle({
    required this.obscure,
    required this.onToggle,
  });
  final bool obscure;
  final VoidCallback onToggle;
  @override
  State<_PasswordVisibilityToggle> createState() =>
      _PasswordVisibilityToggleState();
}

class _PasswordVisibilityToggleState extends State<_PasswordVisibilityToggle> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            widget.obscure ? Icons.visibility_off : Icons.visibility,
            size: 18,
            color: cs.onSurface.withValues(alpha: _hover ? 0.7 : 0.45),
          ),
        ),
      ),
    );
  }
}
