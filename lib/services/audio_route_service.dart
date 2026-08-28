import 'package:flutter/services.dart';

import 'app_log.dart';

/// Output routes exposed by the Android side (`VoiceAudioController`).
enum AudioRoute {
  auto,
  earpiece,
  speaker,
  wired,
  usb,
  bluetooth;

  String get id => switch (this) {
    AudioRoute.auto => 'auto',
    AudioRoute.earpiece => 'earpiece',
    AudioRoute.speaker => 'speaker',
    AudioRoute.wired => 'wired',
    AudioRoute.usb => 'usb',
    AudioRoute.bluetooth => 'bluetooth',
  };

  static AudioRoute fromId(String id) => switch (id) {
    'earpiece' => AudioRoute.earpiece,
    'speaker' => AudioRoute.speaker,
    'wired' => AudioRoute.wired,
    'usb' => AudioRoute.usb,
    'bluetooth' => AudioRoute.bluetooth,
    _ => AudioRoute.auto,
  };
}

/// Availability of the platform DSP effects on this device. Reported by
/// Android so the UI can disable a switch instead of pretending an effect is
/// active on hardware that does not implement it.
class AudioEffectSupport {
  final bool aec;
  final bool ns;
  final bool agc;

  const AudioEffectSupport({
    this.aec = false,
    this.ns = false,
    this.agc = false,
  });

  static const none = AudioEffectSupport();

  bool get any => aec || ns || agc;
}

/// Thin wrapper over the `com.senlinjun.nek0/audio` MethodChannel.
///
/// Every call degrades gracefully: on a platform error the app keeps working
/// with whatever routing/effects Android chose by itself, which is exactly the
/// behaviour before this feature existed.
class AudioRouteService {
  static const _channel = MethodChannel('com.senlinjun.nek0/audio');

  const AudioRouteService._();

  /// Registers the audio-focus callbacks pushed by Android.
  ///
  /// Focus loss means another app owns voice audio (typically an incoming
  /// phone call): the microphone must stop transmitting, and resume only if
  /// the app had muted it itself.
  static void setFocusListeners({
    required VoidCallback onLost,
    required VoidCallback onRegained,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'focus_lost':
          onLost();
        case 'focus_regained':
          onRegained();
        default:
          AppLog.d('audio', 'unhandled platform call ${call.method}');
      }
      return null;
    });
  }

  static Future<AudioEffectSupport> effectAvailability() async {
    try {
      final raw = await _channel.invokeMapMethod<String, bool>(
        'effect_availability',
      );
      if (raw == null) return AudioEffectSupport.none;
      return AudioEffectSupport(
        aec: raw['aec'] ?? false,
        ns: raw['ns'] ?? false,
        agc: raw['agc'] ?? false,
      );
    } on PlatformException catch (error) {
      AppLog.w('audio', 'effect_availability failed: ${error.code}');
      return AudioEffectSupport.none;
    } on MissingPluginException {
      return AudioEffectSupport.none;
    }
  }

  static Future<void> setEffects({
    required bool aec,
    required bool ns,
    required bool agc,
  }) async {
    try {
      await _channel.invokeMethod<bool>('set_effects', {
        'aec': aec,
        'ns': ns,
        'agc': agc,
      });
    } on PlatformException catch (error) {
      AppLog.w('audio', 'set_effects failed: ${error.code}');
    } on MissingPluginException {
      // Non-Android host (tests): nothing to do.
    }
  }

  static Future<List<AudioRoute>> availableRoutes() async {
    try {
      final raw = await _channel.invokeListMethod<String>('list_routes');
      if (raw == null || raw.isEmpty) return const [AudioRoute.auto];
      return raw.map(AudioRoute.fromId).toList();
    } on PlatformException catch (error) {
      AppLog.w('audio', 'list_routes failed: ${error.code}');
      return const [AudioRoute.auto];
    } on MissingPluginException {
      return const [AudioRoute.auto];
    }
  }

  /// Applies [route] and returns the route Android actually selected — it can
  /// differ when the device vanished in the meantime (headset unplugged).
  static Future<AudioRoute> setRoute(AudioRoute route) async {
    try {
      final applied = await _channel.invokeMethod<String>('set_route', {
        'route': route.id,
      });
      return AudioRoute.fromId(applied ?? 'auto');
    } on PlatformException catch (error) {
      AppLog.w('audio', 'set_route failed: ${error.code}');
      return AudioRoute.auto;
    } on MissingPluginException {
      return AudioRoute.auto;
    }
  }

  static Future<AudioRoute> currentRoute() async {
    try {
      final raw = await _channel.invokeMethod<String>('current_route');
      return AudioRoute.fromId(raw ?? 'auto');
    } on PlatformException {
      return AudioRoute.auto;
    } on MissingPluginException {
      return AudioRoute.auto;
    }
  }
}
