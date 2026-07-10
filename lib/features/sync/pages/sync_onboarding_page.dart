import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:kelivo_max/core/providers/settings_provider.dart';
import 'package:kelivo_max/core/providers/sync_provider.dart';
import 'package:kelivo_max/core/services/sync/sync_api_client.dart';
import 'package:kelivo_max/core/services/sync/sync_credential_store.dart';
import 'package:kelivo_max/core/models/sync_config.dart';
import 'package:kelivo_max/l10n/app_localizations.dart';

class SyncOnboardingPage extends StatefulWidget {
  final VoidCallback onComplete;
  const SyncOnboardingPage({super.key, required this.onComplete});

  @override
  State<SyncOnboardingPage> createState() => _SyncOnboardingPageState();
}

class _SyncOnboardingPageState extends State<SyncOnboardingPage> {
  final _usernameCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _usernameCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameCtl.text.trim();
    final password = _passwordCtl.text;
    if (username.isEmpty || password.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final settings = context.read<SettingsProvider>();
      final syncProvider = context.read<SyncProvider>();
      final credentialStore = SyncCredentialStore();

      await syncProvider.login(
        serverUrl: SyncConfig.defaultServerUrl,
        username: username,
        password: password,
        credentialStore: credentialStore,
        settingsProvider: settings,
      );

      if (!mounted) return;
      await settings.setSyncOnboardingCompleted(true);
      widget.onComplete();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final username = _usernameCtl.text.trim();
    final password = _passwordCtl.text;
    if (username.isEmpty || password.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = SyncApiClient(
        serverUrl: SyncConfig.defaultServerUrl,
        credentialStore: SyncCredentialStore(),
      );
      await client.register(username, password);
      client.dispose();

      // Auto-login after register
      if (!mounted) return;
      await _login();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _skip() {
    final settings = context.read<SettingsProvider>();
    settings.setSyncOnboardingCompleted(true);
    // Disable sync when skipping
    settings.setSyncConfig(settings.syncConfig.copyWith(enabled: false));
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;
    final maxWidth = isWide ? 400.0 : double.infinity;
    final horizontalPadding = isWide ? 0.0 : 32.0;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 48,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // App icon
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/app_icon.png',
                      width: 80,
                      height: 80,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Title
                  Text(
                    l10n.syncOnboardingTitle,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  // Subtitle
                  Text(
                    l10n.syncOnboardingSubtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  // Username
                  TextField(
                    controller: _usernameCtl,
                    decoration: InputDecoration(
                      labelText: l10n.syncUsername,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    textInputAction: TextInputAction.next,
                    enabled: !_loading,
                  ),
                  const SizedBox(height: 16),
                  // Password
                  TextField(
                    controller: _passwordCtl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: l10n.syncPassword,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _login(),
                    enabled: !_loading,
                  ),
                  // Error
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: cs.error, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Login button — primary filled
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _loading ? null : _login,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.syncLoginButton),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // "or" divider
                  Row(
                    children: [
                      Expanded(child: Divider(color: cs.outlineVariant)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          l10n.syncOnboardingOrDivider,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: cs.outlineVariant)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Register button — outlined
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _loading ? null : _register,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(l10n.syncRegisterButton),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Skip button — small and subtle
                  TextButton(
                    onPressed: _loading ? null : _skip,
                    child: Text(
                      l10n.syncOnboardingSkip,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
