import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/ts_state.dart';
import '../models/app_theme.dart';

/// "My status" sheet: nickname, away/AFK with a reason, channel commander.
///
/// Everything here is a `clientupdate` on the wire and is therefore paced by
/// the anti-flood budget; the UI stays optimistic and the roster refresh is
/// what confirms the change.
class StatusPanel extends StatefulWidget {
  final TsConnectionState conn;
  final TsConnectionNotifier notifier;

  const StatusPanel({super.key, required this.conn, required this.notifier});

  @override
  State<StatusPanel> createState() => _StatusPanelState();
}

class _StatusPanelState extends State<StatusPanel> {
  late final TextEditingController _nickname;
  late final TextEditingController _awayMessage;
  late bool _away;

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(text: widget.conn.nickname);
    _awayMessage = TextEditingController(text: widget.conn.awayMessage ?? '');
    _away = widget.conn.away;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _awayMessage.dispose();
    super.dispose();
  }

  void _applyNickname() {
    final value = _nickname.text.trim();
    if (value.isEmpty || value == widget.conn.nickname) return;
    if (widget.notifier.setNickname(value)) {
      FocusScope.of(context).unfocus();
    }
  }

  void _applyAway() {
    final message = _awayMessage.text.trim();
    widget.notifier.setAway(_away, message: message.isEmpty ? null : message);
  }

  @override
  Widget build(BuildContext context) {
    final al = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          // Keep the fields visible above the keyboard.
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.badge_outlined, color: context.ts.accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  al.myStatus,
                  style: TextStyle(
                    color: context.ts.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nickname,
              style: TextStyle(color: context.ts.textPrimary),
              maxLength: 30,
              decoration: InputDecoration(
                labelText: al.nickname,
                labelStyle: TextStyle(color: context.ts.textSecondary),
                helperText: al.nicknameHint,
                helperStyle: TextStyle(
                  color: context.ts.textSecondary,
                  fontSize: 11,
                ),
                suffixIcon: IconButton(
                  icon: Icon(Icons.check, color: context.ts.accent),
                  onPressed: _applyNickname,
                ),
              ),
              onSubmitted: (_) => _applyNickname(),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _away,
              title: Text(
                al.awayStatus,
                style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
              ),
              onChanged: (value) {
                setState(() => _away = value);
                _applyAway();
              },
            ),
            if (_away)
              TextField(
                controller: _awayMessage,
                style: TextStyle(color: context.ts.textPrimary),
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: al.awayMessage,
                  labelStyle: TextStyle(color: context.ts.textSecondary),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.check, color: context.ts.accent),
                    onPressed: _applyAway,
                  ),
                ),
                onSubmitted: (_) => _applyAway(),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.conn.channelCommander,
              title: Text(
                al.channelCommander,
                style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
              ),
              subtitle: Text(
                al.channelCommanderHint,
                style: TextStyle(color: context.ts.textSecondary, fontSize: 11),
              ),
              onChanged: widget.notifier.setChannelCommander,
            ),
          ],
        ),
      ),
    );
  }
}
