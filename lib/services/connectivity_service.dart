import 'dart:async';

import 'package:flutter/services.dart';

import 'app_log.dart';

/// Snapshot of the device's network state, as reported by
/// `ConnectivityStreamHandler` on the Android side.
class NetworkStatus {
  /// True only when a network is up **and validated** — a captive portal or an
  /// unvalidated link cannot carry a TeamSpeak session.
  final bool available;

  /// `wifi`, `cellular`, `ethernet`, `vpn`, `other`, `none`, `unknown`.
  final String transport;

  /// Opaque platform handle, only ever compared with the previous value to
  /// detect a path change (Wi-Fi ↔ mobile handover).
  final String networkId;

  const NetworkStatus({
    required this.available,
    required this.transport,
    required this.networkId,
  });

  static const unknown = NetworkStatus(
    available: true,
    transport: 'unknown',
    networkId: '',
  );

  /// A handover is a *different* usable network replacing the previous one:
  /// the socket is dead even though the device never looked offline.
  bool isHandoverFrom(NetworkStatus previous) =>
      available &&
      previous.available &&
      previous.networkId.isNotEmpty &&
      networkId.isNotEmpty &&
      networkId != previous.networkId;

  @override
  String toString() =>
      'NetworkStatus(available: $available, transport: $transport)';
}

/// Wrapper over the `com.senlinjun.nek0/connectivity` EventChannel.
class ConnectivityService {
  static const _channel = EventChannel('com.senlinjun.nek0/connectivity');

  const ConnectivityService._();

  /// Emits on every availability/transport change. On a non-Android host (or
  /// if the platform side is missing) the stream stays empty, and callers keep
  /// their previous behaviour — the timer-driven backoff.
  static Stream<NetworkStatus> watch() {
    return _channel
        .receiveBroadcastStream()
        .map((event) {
          final map = (event as Map).cast<Object?, Object?>();
          return NetworkStatus(
            available: map['available'] as bool? ?? true,
            transport: map['transport'] as String? ?? 'unknown',
            networkId: map['network'] as String? ?? '',
          );
        })
        .handleError((Object error) {
          AppLog.w('net', 'connectivity stream error: ${error.runtimeType}');
        });
  }
}
