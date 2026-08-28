import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/ts_state.dart';
import '../services/audio_route_service.dart';
import '../models/app_theme.dart';

/// Output route picker + platform DSP switches.
///
/// Effects the device does not implement are shown disabled with an
/// explanation rather than hidden: a silently missing echo canceller is a
/// support nightmare, and the user needs to know why speakerphone echoes.
class AudioOutputPanel extends StatelessWidget {
  final TsConnectionState conn;
  final TsConnectionNotifier notifier;

  const AudioOutputPanel({
    super.key,
    required this.conn,
    required this.notifier,
  });

  String _routeLabel(AppLocalizations al, AudioRoute route) => switch (route) {
    AudioRoute.auto => al.routeAuto,
    AudioRoute.earpiece => al.routeEarpiece,
    AudioRoute.speaker => al.routeSpeaker,
    AudioRoute.wired => al.routeWired,
    AudioRoute.usb => al.routeUsb,
    AudioRoute.bluetooth => al.routeBluetooth,
  };

  IconData _routeIcon(AudioRoute route) => switch (route) {
    AudioRoute.auto => Icons.auto_mode,
    AudioRoute.earpiece => Icons.phone_in_talk,
    AudioRoute.speaker => Icons.volume_up,
    AudioRoute.wired => Icons.headset,
    AudioRoute.usb => Icons.usb,
    AudioRoute.bluetooth => Icons.bluetooth_audio,
  };

  @override
  Widget build(BuildContext context) {
    final al = AppLocalizations.of(context);
    final support = conn.effectSupport;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              al.audioOutput,
              style: TextStyle(color: context.ts.textSecondary, fontSize: 12),
            ),
            const Spacer(),
            IconButton(
              tooltip: al.audioOutput,
              onPressed: notifier.refreshAudioRoutes,
              icon: Icon(
                Icons.refresh,
                size: 18,
                color: context.ts.textSecondary,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final route in conn.availableRoutes)
              ChoiceChip(
                selected: conn.audioRoute == route,
                onSelected: (_) => notifier.setAudioRoute(route),
                avatar: Icon(
                  _routeIcon(route),
                  size: 16,
                  color: conn.audioRoute == route
                      ? context.ts.textPrimary
                      : context.ts.textSecondary,
                ),
                label: Text(
                  _routeLabel(al, route),
                  style: const TextStyle(fontSize: 12),
                ),
                selectedColor: const Color(0xFF2A2A6A),
                backgroundColor: context.ts.surfaceAlt,
                labelStyle: TextStyle(
                  color: conn.audioRoute == route
                      ? context.ts.textPrimary
                      : context.ts.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          al.audioProcessing,
          style: TextStyle(color: context.ts.textSecondary, fontSize: 12),
        ),
        _effectSwitch(
          context,
          label: al.effectAec,
          hint: support.aec ? al.effectAecHint : al.effectUnavailable,
          value: conn.aecEnabled,
          supported: support.aec,
          onChanged: (value) => notifier.setAudioEffects(aec: value),
        ),
        _effectSwitch(
          context,
          label: al.effectNs,
          hint: support.ns ? null : al.effectUnavailable,
          value: conn.nsEnabled,
          supported: support.ns,
          onChanged: (value) => notifier.setAudioEffects(ns: value),
        ),
        _effectSwitch(
          context,
          label: al.effectAgc,
          hint: support.agc ? al.effectAgcHint : al.effectUnavailable,
          value: conn.agcEnabled,
          supported: support.agc,
          onChanged: (value) => notifier.setAudioEffects(agc: value),
        ),
      ],
    );
  }

  Widget _effectSwitch(
    BuildContext context, {
    required String label,
    required String? hint,
    required bool value,
    required bool supported,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: value && supported,
      onChanged: supported ? onChanged : null,
      title: Text(
        label,
        style: TextStyle(
          color: supported ? context.ts.textPrimary : context.ts.textSecondary,
          fontSize: 13,
        ),
      ),
      subtitle: hint == null
          ? null
          : Text(
              hint,
              style: TextStyle(color: context.ts.textSecondary, fontSize: 11),
            ),
    );
  }
}
