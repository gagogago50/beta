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
      // Extra admin actions, always visible for server admins (these do not
      // depend on per-target permission hints, only on being connected).
      _action(
        context,
        icon: Icons.vpn_key,
        label: 'Ban by UID',
        color: context.ts.dangerAccent,
        onTap: () => _banByUid(context),
      ),
      _action(
        context,
        icon: Icons.flag_outlined,
        label: 'File a complaint',
        color: context.ts.warning,
        onTap: () => _complain(context),
      ),
      _action(
        context,
        icon: Icons.voice_over_off,
        label: client.talkPowerGranted ? 'Make silent' : 'Allow to talk',
        color: context.ts.dangerAccent,
        onTap: () {
          Navigator.of(context).pop();
          // Invert: if they can currently talk, mute them (talk_power=false);
          // otherwise re-allow (talk_power=true).
          notifier.setTalker(client.id, !client.talkPowerGranted);
        },
      ),
      if (client.serverGroupIds.isNotEmpty)
        _action(
          context,
          icon: Icons.groups,
          label: 'Server groups',
          onTap: () => _manageGroups(context),
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

  /// Bans the client's persistent UID (valid across every server they use).
  Future<void> _banByUid(BuildContext context) async {
    final result = await showDialog<_BanRequest>(
      context: context,
      builder: (ctx) => _BanDialog(nickname: client.nickname),
    );
    if (result == null) return;
    notifier.banUid(
      client.uid ?? '',
      seconds: result.seconds,
      reason: result.reason,
    );
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Ban by UID sent')));
    }
  }

  /// Files a complaint against the client.
  Future<void> _complain(BuildContext context) async {
    final al = AppLocalizations.of(context);
    final message = await _promptText(context, 'Complaint', al.send);
    if (message == null || message.isEmpty) return;
    notifier.complainAdd(client.id, message);
    if (context.mounted) Navigator.of(context).pop();
  }

  /// Lets an admin add/remove this client from its server groups.
  Future<void> _manageGroups(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.ts.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => _GroupManager(client: client, notifier: notifier),
    );
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

/// Admin: add/remove a client from its server groups.
///
/// The engine exposes the client's current group ids; an admin can pop one of
/// them and type a new group id to assign. This mirrors the desktop client's
/// "Server groups" dialog without needing a full group list (the server may
/// not expose it to every client).
class _GroupManager extends StatelessWidget {
  final TsClient client;
  final TsConnectionNotifier notifier;

  const _GroupManager({required this.client, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final al = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Server groups · ${client.nickname}',
              style: TextStyle(
                color: context.ts.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            for (final groupId in client.serverGroupIds)
              ListTile(
                dense: true,
                leading: const Icon(Icons.group, size: 18),
                title: Text(
                  'Group $groupId',
                  style: TextStyle(color: context.ts.textPrimary),
                ),
                trailing: IconButton(
                  icon: Icon(
                    Icons.remove_circle_outline,
                    color: context.ts.danger,
                  ),
                  tooltip: 'Remove',
                  onPressed: () =>
                      notifier.removeClientFromGroup(client.id, groupId),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => _addGroup(context),
              icon: const Icon(Icons.add),
              label: const Text('Assign group by ID'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(al.close),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addGroup(BuildContext context) async {
    final controller = TextEditingController();
    final groupId = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.ts.card,
        title: const Text('Assign server group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: TextStyle(color: context.ts.textPrimary),
          decoration: const InputDecoration(hintText: 'Server group id'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              ctx,
            ).pop(int.tryParse(controller.text.trim()) ?? 0),
            child: Text('Assign'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (groupId != null && groupId > 0) {
      notifier.addClientToGroup(client.id, groupId);
    }
  }
}
