import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

import '../models/ts_state.dart';
import '../models/app_theme.dart';

/// Shared mic voice settings panel (PTT mode, VAD, threshold + level meter,
/// mic gain). Used by the server screen's long-press-mic bottom sheet and by
/// the settings screen.
class VoiceSettingsPanel extends StatefulWidget {
  const VoiceSettingsPanel({
    super.key,
    required this.conn,
    required this.notifier,
    this.showTitle = true,
    this.levelOverride,
  });

  final TsConnectionState conn;
  final TsConnectionNotifier notifier;
  final bool showTitle;

  /// External mic level (e.g. from the settings mic test). When null the
  /// panel falls back to the live [conn.micRms].
  final double? levelOverride;

  @override
  State<VoiceSettingsPanel> createState() => _VoiceSettingsPanelState();
}

class _VoiceSettingsPanelState extends State<VoiceSettingsPanel> {
  late bool _pttMode;
  late bool _vadEnabled;
  late double _vadThreshold;
  late double _micGain;

  @override
  void initState() {
    super.initState();
    _pttMode = widget.conn.pttMode;
    _vadEnabled = widget.conn.vadEnabled;
    _vadThreshold = widget.conn.vadThreshold;
    _micGain = widget.conn.micGain;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showTitle) ...[
          Text(
            AppLocalizations.of(context).voiceSettings,
            style: TextStyle(
              color: context.ts.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
        ],
        // PTT / VA mode toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppLocalizations.of(context).pttMode,
              style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
            ),
            Switch(
              value: _pttMode,
              activeTrackColor: context.ts.accent,
              onChanged: (v) {
                setState(() => _pttMode = v);
                widget.notifier.togglePttMode();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        // VAD enable/disable
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppLocalizations.of(context).voiceActivation,
              style: TextStyle(
                color: _pttMode
                    ? context.ts.textSecondary
                    : context.ts.textPrimary,
                fontSize: 14,
              ),
            ),
            Switch(
              value: _vadEnabled,
              activeTrackColor: context.ts.accent,
              onChanged: _pttMode
                  ? null
                  : (v) {
                      setState(() => _vadEnabled = v);
                      widget.notifier.setVadEnabled(v);
                    },
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Threshold slider stacked on mic level bar (same 0–1 scale)
        Builder(
          builder: (_) {
            final s = widget.conn;
            final micActive = !s.inputMuted && (!s.pttMode || s.pttPressed);
            final rms = widget.levelOverride ?? (micActive ? s.micRms : 0.0);
            final fill = rms.clamp(0.0, 1.0);
            final over = rms >= _vadThreshold && _vadThreshold > 0.0;
            return Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    AppLocalizations.of(context).level,
                    style: TextStyle(
                      color: context.ts.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Bottom: mic level bar
                      LinearProgressIndicator(
                        value: fill,
                        backgroundColor: context.ts.surfaceAlt,
                        color: over
                            ? context.ts.accent
                            : context.ts.textSecondary,
                        minHeight: 4,
                      ),
                      // Top: threshold slider (transparent track, only knob visible)
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          overlayShape: SliderComponentShape.noOverlay,
                          activeTrackColor: Colors.transparent,
                          inactiveTrackColor: Colors.transparent,
                          thumbColor: context.ts.accent,
                          disabledThumbColor: context.ts.textSecondary,
                        ),
                        child: Slider(
                          value: _vadThreshold,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (_pttMode || !_vadEnabled)
                              ? null
                              : (v) {
                                  setState(() => _vadThreshold = v);
                                  widget.notifier.setVadThreshold(v);
                                },
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    _vadThreshold.toStringAsFixed(3),
                    style: TextStyle(
                      color: context.ts.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        // Mic gain slider
        Row(
          children: [
            Text(
              AppLocalizations.of(context).micGain,
              style: TextStyle(color: context.ts.textSecondary, fontSize: 12),
            ),
            Expanded(
              child: Slider(
                value: _micGain,
                min: 0.0,
                max: 2.0,
                divisions: 40,
                activeColor: context.ts.accent,
                onChanged: (v) {
                  setState(() => _micGain = v);
                  widget.notifier.setMicGain(v);
                },
              ),
            ),
            Text(
              _micGain.toStringAsFixed(2),
              style: TextStyle(color: context.ts.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}
