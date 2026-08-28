import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/app_locale.dart';
import '../models/ts_state.dart';
import '../services/app_log.dart';
import '../services/chat_history_service.dart';
import '../services/identity_backup_service.dart';
import '../services/secure_storage.dart';
import '../services/ts_ffi.dart';
import '../services/audio_service.dart';
import '../widgets/audio_output_panel.dart';
import '../widgets/voice_settings_panel.dart';
import '../models/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _languageOptions = ['system', 'en', 'zh'];

  String _languageCode = 'system';

  AudioService? _testAudio;
  bool _micTest = false;
  double _testRms = 0.0;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    // The preference lives in SharedPreferences; pull it into the provider so
    // the switch reflects reality even before the first connection.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(tsSelectedProvider).actions;
      notifier.loadReconnectPreference();
      // Route list and effect availability are device state: query them every
      // time the screen opens (a headset may have been plugged in since).
      notifier.loadAudioPreferences();
      notifier.loadHistoryPreferences();
    });
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('locale') ?? 'system';
    if (mounted) setState(() => _languageCode = code);
  }

  String _languageLabel(BuildContext context, String code) {
    final al = AppLocalizations.of(context);
    return switch (code) {
      'en' => al.languageEnglish,
      'zh' => al.languageChinese,
      _ => al.languageSystem,
    };
  }

  @override
  void dispose() {
    _testAudio?.disableMic();
    _testAudio?.stop();
    _testAudio = null;
    super.dispose();
  }

  /// Verbose logging is a diagnostic aid, never a way to see secrets: the
  /// redaction in [AppLog] applies at every level.
  void _setVerboseLogging(bool enabled) {
    setState(() {
      AppLog.minLevel = enabled ? LogLevel.debug : LogLevel.warn;
    });
    // Keep the Rust engine in step with the Dart side.
    TsNative.setLogLevel(enabled ? 4 : 2);
  }

  Future<void> _clearHistory() async {
    final al = AppLocalizations.of(context);
    await ref.read(tsSelectedProvider).actions.clearChatHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(al.clearHistoryDone)));
  }

  /// Destructive and irreversible: ask explicitly, and spell out that the
  /// identity — the only thing the user cannot recreate — is going away.
  Future<void> _confirmEraseSecrets() async {
    final al = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.ts.card,
        title: Text(
          al.eraseSecretsConfirmTitle,
          style: TextStyle(color: context.ts.textPrimary),
        ),
        content: Text(
          al.eraseSecretsConfirmBody,
          style: TextStyle(color: context.ts.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(al.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.ts.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(al.eraseSecretsConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final notifier = ref.read(tsSelectedProvider).actions;
    final identityOk = await notifier.eraseIdentityAndSecrets();
    final secretsOk = await ref
        .read(serverListProvider.notifier)
        .eraseAllSecrets()
        .then((_) => true)
        .catchError((_) => false);
    if (!mounted) return;
    final ok = identityOk && secretsOk;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(ok ? al.eraseSecretsDone : al.eraseSecretsPartial),
          backgroundColor: ok ? context.ts.success : context.ts.warning,
        ),
      );
  }

  /// Exports the TeamSpeak identity as a password-protected, portable blob.
  ///
  /// The identity is the only thing the user cannot recreate, so this is the
  /// one moment it is deliberately readable — sealed under a passphrase the
  /// user chooses. Nothing is sent anywhere; the blob is copied to the
  /// clipboard so the user can store it.
  Future<void> _exportIdentity() async {
    final al = AppLocalizations.of(context);
    final identity = await SecureStorage.get(SecureStorage.identityKey);
    if (identity == null || identity.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(al.noIdentityToExport)));
      return;
    }
    final password = await _promptPassword(
      title: al.exportIdentity,
      hint: al.chooseBackupPassword,
      confirm: true,
    );
    if (password == null || !mounted) return;

    try {
      final blob = await IdentityBackupService.export(identity, password);
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: blob));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(al.identityExported)));
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'bad_password' ? al.badPassword : al.exportFailed,
          ),
          backgroundColor: context.ts.danger,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(al.exportFailed),
          backgroundColor: context.ts.danger,
        ),
      );
    }
  }

  /// Restores a TeamSpeak identity from a password-protected blob.
  Future<void> _importIdentity() async {
    final al = AppLocalizations.of(context);
    final blob = await _promptText(
      title: al.importIdentity,
      hint: al.pasteBackupBlob,
      multiline: true,
    );
    if (blob == null || !mounted) return;
    if (!IdentityBackupService.looksLikeBlob(blob)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(al.badFormat),
          backgroundColor: context.ts.danger,
        ),
      );
      return;
    }
    final password = await _promptPassword(
      title: al.importIdentity,
      hint: al.enterBackupPassword,
    );
    if (password == null || !mounted) return;

    try {
      final identity = await IdentityBackupService.import(blob, password);
      // Persist it in Keystore-backed storage and hand it to the engine so the
      // next connect uses it.
      await SecureStorage.put(SecureStorage.identityKey, identity);
      TsNative.setIdentity(identity);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(al.identityImported)));
    } on PlatformException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'bad_password' => al.badPassword,
        'bad_format' => al.badFormat,
        _ => al.importFailed,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: context.ts.danger),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(al.importFailed),
          backgroundColor: context.ts.danger,
        ),
      );
    }
  }

  /// Prompts for a password (with an optional confirm field). Returns null on
  /// cancel.
  Future<String?> _promptPassword({
    required String title,
    required String hint,
    bool confirm = false,
  }) async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    String? value;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: context.ts.card,
          title: Text(title, style: TextStyle(color: context.ts.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                style: TextStyle(color: context.ts.textPrimary),
                decoration: InputDecoration(
                  labelText: hint,
                  labelStyle: TextStyle(color: context.ts.textSecondary),
                  errorText: error,
                ),
              ),
              if (confirm) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  style: TextStyle(color: context.ts.textPrimary),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(ctx).confirmPassword,
                    labelStyle: TextStyle(color: context.ts.textSecondary),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                AppLocalizations.of(ctx).cancel,
                style: TextStyle(color: context.ts.textSecondary),
              ),
            ),
            FilledButton(
              onPressed: () {
                final pw = controller.text;
                if (pw.isEmpty || (confirm && pw != confirmController.text)) {
                  setState(
                    () => error = AppLocalizations.of(ctx).passwordMismatch,
                  );
                  return;
                }
                value = pw;
                Navigator.pop(ctx);
              },
              child: Text(AppLocalizations.of(ctx).confirm),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    confirmController.dispose();
    return value;
  }

  /// Prompts for a multi-line value. Returns null on cancel.
  Future<String?> _promptText({
    required String title,
    required String hint,
    bool multiline = false,
  }) async {
    final controller = TextEditingController();
    String? value;
    await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.ts.card,
        title: Text(title, style: TextStyle(color: context.ts.textPrimary)),
        content: TextField(
          controller: controller,
          maxLines: multiline ? 5 : 1,
          style: TextStyle(color: context.ts.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: context.ts.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(ctx).cancel,
              style: TextStyle(color: context.ts.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () {
              value = controller.text;
              Navigator.pop(ctx);
            },
            child: Text(AppLocalizations.of(ctx).confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _toggleMicTest() async {
    if (_micTest) {
      _testAudio?.disableMic();
      _testAudio?.stop();
      _testAudio = null;
      setState(() {
        _micTest = false;
        _testRms = 0.0;
      });
      return;
    }
    final a = AudioService();
    a.onMicLevel = (rms) {
      if (mounted) setState(() => _testRms = rms);
    };
    final started = await a.start();
    final granted = started ? await a.enableMic() : false;
    if (!granted) {
      a.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).micPermissionDenied),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _testAudio = a;
      _micTest = true;
      _testRms = 0.0;
    });
  }

  String _themeLabel(BuildContext context, AppThemeMode mode) {
    final al = AppLocalizations.of(context);
    return switch (mode) {
      AppThemeMode.system => al.themeSystem,
      AppThemeMode.dark => al.themeDark,
      AppThemeMode.light => al.themeLight,
      AppThemeMode.amoled => al.themeAmoled,
    };
  }

  IconData _themeIcon(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => Icons.brightness_auto,
    AppThemeMode.dark => Icons.dark_mode,
    AppThemeMode.light => Icons.light_mode,
    AppThemeMode.amoled => Icons.brightness_high,
  };

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(tsSelectedProvider);
    final conn = view.state;
    final notifier = view.actions;
    final connected = conn.connected;
    final themeMode = ref.watch(tsThemeProvider).mode;

    return Scaffold(
      backgroundColor: context.ts.background,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).settingsTitle),
        backgroundColor: context.ts.appbar,
        foregroundColor: context.ts.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionHeader(AppLocalizations.of(context).theme),
            const SizedBox(height: 8),
            Card(
              color: context.ts.card,
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final mode in AppThemeMode.values)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        _themeIcon(mode),
                        color: mode == themeMode
                            ? context.ts.accent
                            : context.ts.textSecondary,
                      ),
                      title: Text(
                        _themeLabel(context, mode),
                        style: TextStyle(
                          color: context.ts.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                      trailing: mode == themeMode
                          ? Icon(
                              Icons.check_circle,
                              color: context.ts.accent,
                              size: 18,
                            )
                          : null,
                      onTap: () =>
                          ref.read(tsThemeProvider.notifier).setMode(mode),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionHeader(AppLocalizations.of(context).connection),
            const SizedBox(height: 8),
            Card(
              color: context.ts.card,
              margin: EdgeInsets.zero,
              child: SwitchListTile(
                value: conn.autoReconnectEnabled,
                onChanged: notifier.setAutoReconnect,
                title: Text(
                  AppLocalizations.of(context).autoReconnect,
                  style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
                ),
                subtitle: Text(
                  AppLocalizations.of(context).autoReconnectHint,
                  style: TextStyle(
                    color: context.ts.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SectionHeader(AppLocalizations.of(context).privacy),
            const SizedBox(height: 8),
            Card(
              color: context.ts.card,
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    value: AppLog.minLevel == LogLevel.debug,
                    onChanged: _setVerboseLogging,
                    title: Text(
                      AppLocalizations.of(context).verboseLogging,
                      style: TextStyle(
                        color: context.ts.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      AppLocalizations.of(context).verboseLoggingHint,
                      style: TextStyle(
                        color: context.ts.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    value: conn.eventSoundsEnabled,
                    onChanged: notifier.setEventSounds,
                    title: Text(
                      AppLocalizations.of(context).eventSounds,
                      style: TextStyle(
                        color: context.ts.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      AppLocalizations.of(context).eventSoundsHint,
                      style: TextStyle(
                        color: context.ts.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    value: conn.chatHistoryEnabled,
                    onChanged: notifier.setChatHistoryEnabled,
                    title: Text(
                      AppLocalizations.of(context).chatHistory,
                      style: TextStyle(
                        color: context.ts.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      AppLocalizations.of(context).chatHistoryHint,
                      style: TextStyle(
                        color: context.ts.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (conn.chatHistoryEnabled) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text(
                            AppLocalizations.of(context).chatRetention,
                            style: TextStyle(
                              color: context.ts.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 12),
                          for (final retention in HistoryRetention.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                selected: conn.chatRetention == retention,
                                onSelected: (_) =>
                                    notifier.setChatRetention(retention),
                                label: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).retentionDays('${retention.days}'),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                selectedColor: const Color(0xFF2A2A6A),
                                backgroundColor: context.ts.surfaceAlt,
                                labelStyle: TextStyle(
                                  color: conn.chatRetention == retention
                                      ? context.ts.textPrimary
                                      : context.ts.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ListTile(
                      onTap: _clearHistory,
                      leading: Icon(
                        Icons.delete_sweep_outlined,
                        color: context.ts.warning,
                      ),
                      title: Text(
                        AppLocalizations.of(context).clearHistory,
                        style: TextStyle(
                          color: context.ts.warning,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                  ListTile(
                    onTap: _confirmEraseSecrets,
                    leading: Icon(
                      Icons.delete_forever,
                      color: context.ts.dangerAccent,
                    ),
                    title: Text(
                      AppLocalizations.of(context).eraseSecrets,
                      style: TextStyle(
                        color: context.ts.dangerAccent,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      AppLocalizations.of(context).eraseSecretsHint,
                      style: TextStyle(
                        color: context.ts.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Divider(height: 1, color: context.ts.divider),
                  ListTile(
                    onTap: _exportIdentity,
                    leading: Icon(
                      Icons.upload_outlined,
                      color: context.ts.accent,
                    ),
                    title: Text(
                      AppLocalizations.of(context).exportIdentity,
                      style: TextStyle(color: context.ts.accent, fontSize: 14),
                    ),
                    subtitle: Text(
                      AppLocalizations.of(context).exportIdentityHint,
                      style: TextStyle(
                        color: context.ts.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  ListTile(
                    onTap: _importIdentity,
                    leading: Icon(
                      Icons.download_outlined,
                      color: context.ts.accent,
                    ),
                    title: Text(
                      AppLocalizations.of(context).importIdentity,
                      style: TextStyle(color: context.ts.accent, fontSize: 14),
                    ),
                    subtitle: Text(
                      AppLocalizations.of(context).importIdentityHint,
                      style: TextStyle(
                        color: context.ts.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionHeader(AppLocalizations.of(context).voice),
            const SizedBox(height: 8),
            Card(
              color: context.ts.card,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: VoiceSettingsPanel(
                  conn: conn,
                  notifier: notifier,
                  showTitle: false,
                  // Draw the mic test level onto the threshold slider, just
                  // like the server screen's long-press-mic sheet.
                  levelOverride: _micTest ? _testRms : null,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: context.ts.card,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AudioOutputPanel(conn: conn, notifier: notifier),
              ),
            ),
            const SizedBox(height: 12),
            // Mic test capture control (level is drawn on the threshold
            // slider in the VoiceSettingsPanel above, like the server screen)
            Card(
              color: context.ts.card,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          AppLocalizations.of(context).micTest,
                          style: TextStyle(
                            color: context.ts.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        FilledButton.tonalIcon(
                          onPressed: connected ? null : _toggleMicTest,
                          icon: Icon(
                            _micTest ? Icons.stop : Icons.mic,
                            size: 18,
                          ),
                          label: Text(
                            _micTest
                                ? AppLocalizations.of(context).stopMicTest
                                : AppLocalizations.of(context).startMicTest,
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: context.ts.divider,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    if (connected) ...[
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context).micInUseWhileConnected,
                        style: TextStyle(
                          color: context.ts.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _SectionHeader(AppLocalizations.of(context).language),
            const SizedBox(height: 8),
            Card(
              color: context.ts.card,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: RadioGroup<String>(
                  groupValue: _languageCode,
                  onChanged: (code) {
                    if (code == null) return;
                    setState(() => _languageCode = code);
                    ref.read(localeProvider.notifier).setLanguage(code);
                  },
                  child: Column(
                    children: [
                      for (final code in _languageOptions)
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          activeColor: context.ts.accent,
                          title: Text(
                            _languageLabel(context, code),
                            style: TextStyle(
                              color: context.ts.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                          value: code,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: context.ts.accent,
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }
}
