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
      title: Text(
        client.nickname,
        style: TextStyle(
          color: client.away
              ? context.ts.textSecondary
              : context.ts.textPrimary,
          fontSize: 13,
        ),
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

  IconData _clientIcon(TsClient client) {
    if (client.outputMuted) return Icons.headset_off;
    if (client.inputMuted) return Icons.mic_off;
    if (client.away) return Icons.access_time;
    return Icons.person;
  }

  Color _clientColor(TsClient client) {
    if (client.away) return context.ts.textSecondary;
    if (client.inputMuted || client.outputMuted) return context.ts.warning;
    return context.ts.success;
  }
}
