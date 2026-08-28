import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/reconnect_policy.dart';
import '../models/app_theme.dart';

class ConnectionBar extends StatelessWidget {
  final String serverName;
  final bool connected;

  /// Connection state machine phase, shown instead of a bare "Disconnected"
  /// while an attempt or a retry is in flight.
  final TsPhase phase;
  final String voiceEncryptionMode;
  final int rttMs;

  /// Inter-arrival jitter (ms), shown alongside the RTT.
  final int jitterMs;

  /// Commands waiting behind the anti-flood budget, and whether the engine is
  /// in degraded mode after a server flood warning.
  final int pendingCommands;
  final bool commandRateDegraded;
  final double packetLossPercent;
  final VoidCallback onDisconnect;
  final VoidCallback? onShowGuide;

  const ConnectionBar({
    super.key,
    required this.serverName,
    required this.connected,
    this.phase = TsPhase.idle,
    required this.voiceEncryptionMode,
    required this.rttMs,
    this.jitterMs = 0,
    this.pendingCommands = 0,
    this.commandRateDegraded = false,
    required this.packetLossPercent,
    required this.onDisconnect,
    this.onShowGuide,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: context.ts.appbar,
      child: Row(
        children: [
          Icon(
            connected
                ? Icons.cloud_done
                : phase.isBusy
                ? Icons.cloud_sync
                : Icons.cloud_off,
            color: connected
                ? context.ts.success
                : phase.isBusy
                ? context.ts.warning
                : context.ts.danger,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              connected
                  ? serverName
                  : _phaseLabel(AppLocalizations.of(context)),
              style: TextStyle(
                color: connected
                    ? context.ts.textPrimary
                    : phase.isBusy
                    ? context.ts.warning
                    : context.ts.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (connected && pendingCommands > 0)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Tooltip(
                message: commandRateDegraded
                    ? AppLocalizations.of(context).commandsThrottled
                    : AppLocalizations.of(
                        context,
                      ).commandsQueued('$pendingCommands'),
                child: Icon(
                  Icons.hourglass_top,
                  size: 14,
                  color: commandRateDegraded
                      ? context.ts.warning
                      : context.ts.textSecondary,
                ),
              ),
            ),
          if (connected && rttMs > 0)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                '$rttMs ms${jitterMs > 0 ? ' ~$jitterMs' : ''} • '
                '${packetLossPercent.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: packetLossPercent >= 5
                      ? context.ts.warning
                      : context.ts.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
          if (connected)
            Tooltip(
              message: 'Voice encryption: $voiceEncryptionMode',
              child: Icon(
                voiceEncryptionMode == 'ForcedOff'
                    ? Icons.lock_open
                    : Icons.lock,
                color: voiceEncryptionMode == 'ForcedOff'
                    ? context.ts.warning
                    : context.ts.success,
                size: 16,
              ),
            ),
          if (onShowGuide != null)
            IconButton(
              icon: Icon(
                Icons.help_outline,
                color: context.ts.textSecondary,
                size: 18,
              ),
              onPressed: onShowGuide,
              tooltip: AppLocalizations.of(context).guide,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          const SizedBox(width: 12),
          if (connected)
            IconButton(
              icon: Icon(Icons.logout, color: context.ts.danger, size: 18),
              onPressed: onDisconnect,
              tooltip: AppLocalizations.of(context).disconnect,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  String _phaseLabel(AppLocalizations al) => switch (phase) {
    TsPhase.resolving => al.phaseResolving,
    TsPhase.connecting => al.phaseConnecting,
    TsPhase.authenticating => al.phaseAuthenticating,
    TsPhase.reconnecting => al.phaseReconnecting,
    _ => al.disconnected,
  };
}
