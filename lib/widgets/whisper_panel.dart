import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/ts_state.dart';
import '../models/app_theme.dart';

/// Whisper configuration sheet.
///
/// Outgoing side: pick the users and channels a whisper burst is addressed to.
/// TeamSpeak sends whisper voice packets with an explicit target list, so the
/// selection here maps one-to-one onto the `C2SWhisper` packet fields.
///
/// Incoming side: an optional allow list. It is a purely local policy — the
/// engine drops whisper frames from anyone outside the list before decoding,
/// which is what the desktop client's whisper ignore list does.
class WhisperPanel extends StatefulWidget {
  final TsConnectionState conn;
  final TsConnectionNotifier notifier;

  const WhisperPanel({super.key, required this.conn, required this.notifier});

  @override
  State<WhisperPanel> createState() => _WhisperPanelState();
}

class _WhisperPanelState extends State<WhisperPanel> {
  late Set<int> _clients;
  late Set<int> _channels;

  @override
  void initState() {
    super.initState();
    _clients = widget.conn.whisperTargetClientIds.toSet();
    _channels = widget.conn.whisperTargetChannelIds.toSet();
  }

  void _commit() {
    widget.notifier.setWhisperTargets(
      clientIds: _clients.toList(),
      channelIds: _channels.toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final al = AppLocalizations.of(context);
    final conn = widget.conn;
    final others = conn.clients
        .where((c) => c.id != conn.ownClientId)
        .toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.record_voice_over,
                  color: context.ts.accentAlt,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  al.whisperTargets,
                  style: TextStyle(
                    color: context.ts.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: (_clients.isEmpty && _channels.isEmpty)
                      ? null
                      : () {
                          setState(() {
                            _clients.clear();
                            _channels.clear();
                          });
                          _commit();
                        },
                  child: Text(al.whisperClear),
                ),
              ],
            ),
            Text(
              al.whisperTargetSummary(
                '${_clients.length}',
                '${_channels.length}',
              ),
              style: TextStyle(color: context.ts.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _sectionTitle(al.whisperTargetClients),
                  if (others.isEmpty)
                    _emptyHint(al.noUsersInChannel)
                  else
                    ...others.map(
                      (client) => CheckboxListTile(
                        dense: true,
                        value: _clients.contains(client.id),
                        title: Text(
                          client.nickname,
                          style: TextStyle(
                            color: context.ts.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _clients.add(client.id);
                            } else {
                              _clients.remove(client.id);
                            }
                          });
                          _commit();
                        },
                      ),
                    ),
                  _sectionTitle(al.whisperTargetChannels),
                  if (conn.channels.isEmpty)
                    _emptyHint(al.noChannels)
                  else
                    ...conn.channels.map(
                      (channel) => CheckboxListTile(
                        dense: true,
                        value: _channels.contains(channel.id),
                        title: Text(
                          channel.name,
                          style: TextStyle(
                            color: context.ts.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _channels.add(channel.id);
                            } else {
                              _channels.remove(channel.id);
                            }
                          });
                          _commit();
                        },
                      ),
                    ),
                  Divider(color: context.ts.divider),
                  _sectionTitle(al.whisperIncoming),
                  SwitchListTile(
                    dense: true,
                    value: conn.whisperAllowlistEnabled,
                    title: Text(
                      al.whisperAllowlistEnabled,
                      style: TextStyle(
                        color: context.ts.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      al.whisperAllowlistHint,
                      style: TextStyle(
                        color: context.ts.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    onChanged: (value) =>
                        widget.notifier.setWhisperAllowlistEnabled(value),
                  ),
                  if (conn.whisperAllowlistEnabled) ...[
                    _sectionTitle(al.whisperAllowlistMembers),
                    ...others.map((client) {
                      final uid = client.uid;
                      final hasUid = uid != null && uid.isNotEmpty;
                      return CheckboxListTile(
                        dense: true,
                        value: hasUid && conn.whisperAllowedUids.contains(uid),
                        title: Text(
                          client.nickname,
                          style: TextStyle(
                            color: hasUid
                                ? context.ts.textPrimary
                                : context.ts.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: hasUid
                            ? null
                            : Text(
                                al.whisperNoUid,
                                style: TextStyle(
                                  color: context.ts.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                        onChanged: hasUid
                            ? (_) =>
                                  widget.notifier.toggleWhisperAllowedUid(uid)
                            : null,
                      );
                    }),
                    if (conn.whisperIgnoredCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 16,
                          top: 4,
                          bottom: 8,
                        ),
                        child: Text(
                          al.whisperIgnored('${conn.whisperIgnoredCount}'),
                          style: TextStyle(
                            color: context.ts.warning,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF7777AA),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _emptyHint(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Text(
      text,
      style: TextStyle(color: context.ts.textSecondary, fontSize: 12),
    ),
  );
}
