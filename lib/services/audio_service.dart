import 'dart:async';
import 'dart:ffi';
import 'dart:math' show sqrt;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_log.dart';
import 'ts_ffi.dart';

class AudioService {
  bool _running = false;
  StreamSubscription? _micSubscription;

  static const _micChannel = EventChannel('com.senlinjun.nek0/mic');

  /// The session into which the (single, device-wide) microphone transmits.
  /// In multi-server mode only the currently focused server captures voice,
  /// so this is updated by the controller whenever the active tab changes.
  int connectionId = 0;

  bool get isRunning => _running;

  double _micRms = 0.0;
  double get micRms => _micRms;
  void Function(double rms)? onMicLevel;

  Future<bool> start() async {
    if (_running) return true;

    // No session attached (the settings micro test): run in mic-only mode —
    // capture and report the level, but never transmit a TeamSpeak packet.
    if (connectionId == 0) {
      _running = true;
      AppLog.d('audio', 'started (mic-only, no session)');
      return true;
    }

    if (!TsNative.startAudio(connectionId)) {
      AppLog.w('audio', 'startAudio failed (no/closed session)');
      return false;
    }

    _running = true;
    AppLog.d('audio', 'started (mic not yet active)');
    return true;
  }

  // ─── Mic ─────────────────────────────────────────────────────────

  Future<bool> enableMic() async {
    try {
      await Permission.notification.request();
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        _startMic();
        AppLog.i('audio', 'mic enabled');
        return true;
      } else {
        AppLog.w('audio', 'mic permission denied');
        return false;
      }
    } catch (e) {
      AppLog.e('audio', 'mic permission error', e);
      return false;
    }
  }

  void disableMic() {
    _stopMic();
    AppLog.i('audio', 'mic disabled');
  }

  void stop() {
    if (!_running) return;
    _running = false;

    _stopMic();
    if (connectionId != 0) TsNative.stopAudio(connectionId);
    AppLog.d('audio', 'stopped');
  }

  void _startMic() {
    _micSubscription = _micChannel.receiveBroadcastStream().listen(
      (data) {
        if (data is Uint8List && _running) {
          _handleMicData(data);
        }
      },
      onError: (e) {
        AppLog.e('audio', 'mic error', e);
      },
    );
  }

  void _stopMic() {
    _micSubscription?.cancel();
    _micSubscription = null;
  }

  void _handleMicData(Uint8List bytes) {
    final floatCount = bytes.length ~/ 4;
    if (floatCount == 0) return;
    final bd = ByteData.sublistView(bytes);
    final floats = Float32List(floatCount);
    var sumSq = 0.0;
    for (int i = 0; i < floatCount; i++) {
      final s = bd.getFloat32(i * 4, Endian.little);
      floats[i] = s;
      sumSq += s * s;
    }
    _micRms = sqrt(sumSq / floatCount);
    onMicLevel?.call(_micRms);
    _sendMicData(floats);
  }

  void _sendMicData(Float32List samples) {
    if (!_running) return;
    // Mic-only mode (no session): report the level but never transmit.
    if (connectionId == 0) return;
    final ptr = malloc<Float>(samples.length);
    try {
      for (int i = 0; i < samples.length; i++) {
        ptr[i] = samples[i];
      }
      TsNative.sendAudio(connectionId, ptr, samples.length);
    } finally {
      malloc.free(ptr);
    }
  }
}
