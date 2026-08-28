import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/client.dart';
import '../models/ts_state.dart';
import '../models/app_theme.dart';

/// Moderation actions for one client.
///
/// Only the actions the server's permission hints grant are built at all:
/// showing a greyed-out "Ban" to someone who will never be allowed to ban is
/// noise, and showing an enabled one that fails afterwards is worse.
class ModerationSheet extends StatelessWidget {
  final TsClient client;
  final TsConnectionNotifier notifier;
  final int? currentChannelId;

  /// Opens the private conversation with this client in the chat sheet.
  final void Function(int clientId)? onPrivateMessage;

  const ModerationSheet({
    super.key,
    required this.client,
    required this.notifier,
    this.currentChannelId,
    this.onPrivateMessage,
  });

  @override
  Widget build(BuildContext context) {
    final al = AppLocalizations.of(context);
    final permissions = client.permissions;
    // A private-message entry is not moderation, but it belongs in the same
    // menu: the sheet is shown whenever at least one entry exists.
    final entries = <Widget>[
      if (permissions.canPrivateMessage)
        _action(
          context,
          icon: Icons.mail_outline,
          label: al.messageUser,
          onTap: () {
            Navigator.of(context).pop();
            onPrivateMessage?.call(client.id);
          },
        ),
      if (permissions.canPoke)
        _action(
          context,
          icon: Icons.notifications_active_outlined,
          label: al.pokeClient,
          onTap: () => _poke(context),
        ),
      if (permissions.canMove && currentChannelId != null)
        _action(
          context,
          icon: Icons.swap_horiz,
          label: al.moveClientTo,
          onTap: () {
            Navigator.of(context).pop();
            notifier.moveClient(client.id, currentChannelId!);
          },
        ),
      if (permissions.canKickFromChannel)
        _action(
          context,
          icon: Icons.logout,
          label: al.kickFromChannel,
          onTap: () => _kick(context, fromServer: false),
        ),
      if (permissions.canKickFromServer)
        _action(
          context,
          icon: Icons.exit_to_app,
          label: al.kickFromServer,
          color: context.ts.warning,
          onTap: () => _kick(context, fromServer: true),
        ),
      if (permissions.canBan)
        _action(
          context,
          icon: Icons.gavel,
          label: al.banClient,
          color: context.ts.dangerAccent,
          onTap: () => _ban(context),
        ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${al.moderation} · ${client.nickname}',
                style: TextStyle(
                  color: context.ts.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...entries,
          ],
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? context.ts.textPrimary;
    return ListTile(
      dense: true,
      leading: Icon(icon, color: c, size: 20),
      title: Text(label, style: TextStyle(color: c, fontSize: 14)),
      onTap: onTap,
    );
  }

  Future<void> _poke(BuildContext context) async {
    final al = AppLocalizations.of(context);
    final message = await _promptText(context, al.pokeMessage, al.send);
    if (message == null || message.isEmpty) return;
    notifier.pokeClient(client.id, message);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _kick(BuildContext context, {required bool fromServer}) async {
    final al = AppLocalizations.of(context);
    final reason = await _promptText(
      context,
      al.reasonOptional,
      al.confirm,
      allowEmpty: true,
    );
    if (reason == null) return; // cancelled
    notifier.kickClient(
      client.id,
      fromServer: fromServer,
      reason: reason.isEmpty ? null : reason,
    );
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _ban(BuildContext context) async {
    final al = AppLocalizations.of(context);
    final result = await showDialog<_BanRequest>(
      context: context,
      builder: (ctx) => _BanDialog(nickname: client.nickname),
    );
    if (result == null) return;
    notifier.banClient(
      client.id,
      seconds: result.seconds,
      reason: result.reason,
    );
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${al.banClient}: ${client.nickname}')),
        );
    }
  }

  Future<String?> _promptText(
    BuildContext context,
    String label,
    String action, {
    bool allowEmpty = false,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.ts.card,
        title: Text(label, style: TextStyle(color: context.ts.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          style: TextStyle(color: context.ts.textPrimary),
          onSubmitted: (text) => Navigator.of(ctx).pop(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(action),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return null;
    if (!allowEmpty && value.isEmpty) return null;
    return value;
  }
}

class _BanRequest {
  final int seconds;
  final String? reason;

  const _BanRequest(this.seconds, this.reason);
}

/// Ban dialog: duration + reason. A permanent ban is the *last* option, never
/// the default.
class _BanDialog extends StatefulWidget {
  final String nickname;

  const _BanDialog({required this.nickname});

  @override
  State<_BanDialog> createState() => _BanDialogState();
}

class _BanDialogState extends State<_BanDialog> {
  final _reason = TextEditingController();
  int _seconds = 3600;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final al = AppLocalizations.of(context);
    final durations = <int, String>{
      3600: al.banOneHour,
      86400: al.banOneDay,
      604800: al.banOneWeek,
      0: al.banPermanent,
    };

    return AlertDialog(
      backgroundColor: context.ts.card,
      title: Text(
        '${al.banClient} · ${widget.nickname}',
        style: TextStyle(color: context.ts.textPrimary, fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            al.banDuration,
            style: TextStyle(color: context.ts.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in durations.entries)
                ChoiceChip(
                  selected: _seconds == entry.key,
                  onSelected: (_) => setState(() => _seconds = entry.key),
                  label: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selectedColor: context.ts.danger.withValues(alpha: 0.4),
                  backgroundColor: context.ts.surfaceAlt,
                  labelStyle: TextStyle(
                    color: _seconds == entry.key
                        ? context.ts.textPrimary
                        : context.ts.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLength: 200,
            style: TextStyle(color: context.ts.textPrimary),
            decoration: InputDecoration(
              labelText: al.reasonOptional,
              labelStyle: TextStyle(color: context.ts.textSecondary),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(al.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: context.ts.danger),
          onPressed: () {
            final reason = _reason.text.trim();
            Navigator.of(
              context,
            ).pop(_BanRequest(_seconds, reason.isEmpty ? null : reason));
          },
          child: Text(al.confirm),
        ),
      ],
    );
  }
}
