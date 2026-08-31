import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/client.dart';
import 'group_icon.dart';
import '../models/app_theme.dart';

class ClientList extends StatefulWidget {
  final List<TsClient> clients;
  final int currentChannelId;

  /// Scopes the icon cache: icon ids are only unique within one server.
  final String serverUid;

  /// Session to download icons/avatars through.
  final int connectionId;
  final ValueChanged<int>? onClientTap;

  /// Long-press opens the moderation sheet — only when the server granted at
  /// least one action on that client.
  final ValueChanged<int>? onClientLongPress;

  const ClientList({
    super.key,
    required this.clients,
    required this.currentChannelId,
    this.serverUid = '',
    this.connectionId = 0,
    this.onClientTap,
    this.onClientLongPress,
  });

  @override
  State<ClientList> createState() => _ClientListState();
}

class _ClientListState extends State<ClientList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    // Search by nickname across the whole server.
    final matches = _query.trim().isEmpty
        ? widget.clients
        : widget.clients
              .where(
                (c) => c.nickname.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();
    final channelClients = matches
        .where((c) => c.channelId == widget.currentChannelId)
        .toList();

    if (channelClients.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          AppLocalizations.of(context).noUsersInChannel,
          style: TextStyle(color: context.ts.textSecondary),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(color: context.ts.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).searchUsersHint,
                hintStyle: TextStyle(color: context.ts.textSecondary),
                prefixIcon: Icon(
                  Icons.search,
                  color: context.ts.textSecondary,
                  size: 16,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(
                          Icons.close,
                          color: context.ts.textSecondary,
                          size: 16,
                        ),
                        onPressed: () {
                          _query = '';
                          setState(() {});
                        },
                      ),
                isDense: true,
                filled: true,
                fillColor: context.ts.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
              ),
            ),
          ),
        ),
        Divider(height: 1, color: context.ts.divider),
        Expanded(
          child: ListView.builder(
            itemCount: channelClients.length,
            itemBuilder: (context, index) {
              final client = channelClients[index];
              return _buildTile(context, client);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTile(BuildContext context, TsClient client) {
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 22,
        height: 22,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(_clientIcon(client), size: 18, color: _clientColor(client)),
            // Badge stack: channel commander, priority speaker, recording,
            // and server-query — each shown as a small corner mark the way the
            // desktop client overlays its "status" icons.
            if (client.isChannelCommander)
              const Positioned(
                left: 0,
                top: -5,
                child: _CornerBadge(icon: Icons.star, color: Color(0xFFF9A825)),
              ),
            if (client.isPrioritySpeaker)
              const Positioned(
                left: 0,
                bottom: -5,
                child: _CornerBadge(
                  icon: Icons.volume_up,
                  color: Color(0xFF0288D1),
                ),
              ),
            if (client.isRecording)
              const Positioned(
                right: 0,
                top: -5,
                child: _CornerBadge(
                  icon: Icons.fiber_manual_record,
                  color: Color(0xFFD32F2F),
                  size: 9,
                ),
              ),
            if (client.isTalking)
              Positioned(
                right: 0,
                bottom: 0,
                child: Icon(
                  Icons.circle,
                  size: 8,
                  color: client.isWhispering
                      ? context.ts.accentAlt
                      : context.ts.accent,
                ),
              ),
          ],
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              client.nickname,
              style: TextStyle(
                color: client.away
                    ? context.ts.textSecondary
                    : context.ts.textPrimary,
                fontSize: 13,
                fontStyle: client.isQuery ? FontStyle.italic : FontStyle.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (client.isQuery)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                ' (query)',
                style: TextStyle(color: Color(0xFF7E57C2), fontSize: 10),
              ),
            ),
        ],
      ),
      subtitle: _groupsLine(client),
      onTap: () => widget.onClientTap?.call(client.id),
      onLongPress:
          (client.permissions.hasAnyModeration ||
              client.permissions.canPrivateMessage)
          ? () => widget.onClientLongPress?.call(client.id)
          : null,
      trailing:
          (client.permissions.hasAnyModeration ||
              client.permissions.canPrivateMessage)
          ? const Icon(Icons.more_vert, size: 16, color: Color(0xFF555577))
          : null,
    );
  }

  /// Group line: icons when the server provides them, names otherwise.
  ///
  /// Both are shown together — an icon alone is unreadable for a user who does
  /// not know the server's iconography, and the desktop client does the same
  /// in its tooltip.
  Widget? _groupsLine(TsClient client) {
    final names = [
      if (client.channelGroupName != null) client.channelGroupName!,
      ...client.serverGroupNames,
    ];
    if (names.isEmpty) return null;

    final label = Text(
      names.join(' • '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: context.ts.textSecondary, fontSize: 10),
    );
    final iconIds = client.groupIconIds;
    if (iconIds.isEmpty || widget.serverUid.isEmpty) return label;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final iconId in iconIds.take(3))
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: GroupIcon(
              serverUid: widget.serverUid,
              iconId: iconId,
              connectionId: widget.connectionId,
              // No icon yet: take no space rather than reserve an empty box.
              fallback: const SizedBox.shrink(),
            ),
          ),
        Flexible(child: label),
      ],
    );
  }

  /// A server query (bot / admin tool) is rendered distinctly so a user can
  /// tell it apart from a human, matching the desktop client's "Server Query"
  /// marker. It is never a real participant and has no voice.
  static const _queryColor = Color(0xFF7E57C2);

  IconData _clientIcon(TsClient client) {
    if (client.isQuery) return Icons.smart_toy;
    if (client.outputMuted) return Icons.headset_off;
    if (client.inputMuted) return Icons.mic_off;
    if (client.away) return Icons.access_time;
    if (client.isChannelCommander) return Icons.star;
    if (client.isPrioritySpeaker) return Icons.record_voice_over;
    if (client.isRecording) return Icons.fiber_manual_record;
    return Icons.person;
  }

  Color _clientColor(TsClient client) {
    if (client.isQuery) return _queryColor;
    if (client.away) return context.ts.textSecondary;
    if (client.inputMuted || client.outputMuted) return context.ts.warning;
    if (client.isChannelCommander) return context.ts.warning;
    if (client.isPrioritySpeaker) return context.ts.accent;
    return context.ts.success;
  }
}

/// A tiny rounded badge used to overlay a "status" icon on a client row
/// (channel commander, priority speaker, recording). Wrapped in a Material of
/// the surface color so it reads as a chip against any theme.
class _CornerBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _CornerBadge({required this.icon, required this.color, this.size = 11});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 6,
      height: size + 6,
      decoration: BoxDecoration(
        color: context.ts.surface,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size, color: color),
    );
  }
}
