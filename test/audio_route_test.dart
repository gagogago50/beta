import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/services/audio_route_service.dart';

void main() {
  group('AudioRoute', () {
    test('round-trips every route through its wire id', () {
      for (final route in AudioRoute.values) {
        expect(AudioRoute.fromId(route.id), route);
      }
    });

    test('ids match the identifiers used by VoiceAudioController.kt', () {
      // These strings are a cross-language contract: renaming one side only
      // would silently fall back to automatic routing.
      expect(AudioRoute.auto.id, 'auto');
      expect(AudioRoute.earpiece.id, 'earpiece');
      expect(AudioRoute.speaker.id, 'speaker');
      expect(AudioRoute.wired.id, 'wired');
      expect(AudioRoute.usb.id, 'usb');
      expect(AudioRoute.bluetooth.id, 'bluetooth');
    });

    test('an unknown id degrades to automatic', () {
      expect(AudioRoute.fromId('hearing_aid'), AudioRoute.auto);
      expect(AudioRoute.fromId(''), AudioRoute.auto);
    });
  });

  group('AudioEffectSupport', () {
    test('defaults to nothing supported', () {
      expect(AudioEffectSupport.none.aec, isFalse);
      expect(AudioEffectSupport.none.ns, isFalse);
      expect(AudioEffectSupport.none.agc, isFalse);
      expect(AudioEffectSupport.none.any, isFalse);
    });

    test('any is true as soon as one effect exists', () {
      const support = AudioEffectSupport(aec: false, ns: true, agc: false);
      expect(support.any, isTrue);
    });
  });
}
