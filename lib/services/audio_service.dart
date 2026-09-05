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

  // ─── Zero-allocation mic path (D4) ────────────────────────────────
  //
  // The legacy audio path allocated a fresh Float32List, a ByteData view and
  // a malloc'd Float pointer for every 20 ms frame — 50×/s of garbage. Here
  // the FFI pointer is allocated once and reused; the per-frame work is one
  // native float copy straight into it (no GC allocation during the hot loop).
  //
  // Frame length is fixed by the capture (960 samples = 20 ms @ 48 kHz), but
  // we size for any count to tolerate engine changes.
  static const int _maxMicSamples = 960;
  Pointer<Float>? _micPtr;

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
    // Free the reused FFI buffer so it is re-allocated (fresh) on next start.
    _freeMicBuffer();
    AppLog.d('audio', 'stopped');
  }

  void _freeMicBuffer() {
    final ptr = _micPtr;
    if (ptr != null) {
      malloc.free(ptr);
      _micPtr = null;
    }
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

  /// Decodes a little-endian float32 frame, computes RMS and forwards it to
  /// the engine, all in a single pass over the data and without allocating
  /// during the hot loop (the FFI pointer is reused across frames).
  void _handleMicData(Uint8List bytes) {
    final floatCount = bytes.length ~/ 4;
    if (floatCount == 0) return;
    if (floatCount > _maxMicSamples) {
      // Unexpectedly large frame: drop it rather than overflowing the buffer.
      AppLog.w('audio', 'oversized mic frame ($floatCount)');
      return;
    }
    final bd = ByteData.sublistView(bytes);

    // Mic-only mode (no session): still report the level but never transmit.
    final transmit = _running && connectionId != 0;
    final ptr = transmit ? (_micPtr ??= malloc<Float>(_maxMicSamples)) : null;

    var sumSq = 0.0;
    if (ptr != null) {
      for (int i = 0; i < floatCount; i++) {
        final s = bd.getFloat32(i * 4, Endian.little);
        sumSq += s * s;
        ptr[i] = s;
      }
    } else {
      for (int i = 0; i < floatCount; i++) {
        final s = bd.getFloat32(i * 4, Endian.little);
        sumSq += s * s;
      }
    }
    _micRms = sqrt(sumSq / floatCount);
    onMicLevel?.call(_micRms);

    if (transmit && ptr != null) {
      TsNative.sendAudio(connectionId, ptr, floatCount);
    }
  }
}
