/// How often Dart drains the engine's event queue.
///
/// The Rust engine is event-driven and wakes Dart through a native callback;
/// this timer is only a safety net plus the source of the UI's live mic
/// indicator. Its cadence is therefore a pure battery/latency trade-off, and
/// nothing functional depends on the fast tiers.
class PollPolicy {
  const PollPolicy._();

  /// Foreground while capturing: drives the talking indicator, which has to
  /// look instant.
  static const capturing = Duration(milliseconds: 50);

  /// Foreground, connected, not capturing: reconciles the roster.
  static const foregroundIdle = Duration(seconds: 2);

  /// While connecting: the connection state machine is short-lived.
  static const connecting = Duration(seconds: 1);

  /// Backgrounded: there is no UI to refresh, so the timer is a pure safety
  /// net behind the native wake-up callback. Audio keeps flowing through the
  /// engine either way — this timer never carries voice.
  static const background = Duration(seconds: 15);

  /// Interval for the current situation.
  ///
  /// [foreground] false means the app is paused/hidden: the expensive tiers
  /// are skipped entirely, which is what saves the battery during the long
  /// background sessions this app is built for.
  static Duration intervalFor({
    required bool connected,
    required bool capturing,
    required bool foreground,
  }) {
    if (!foreground) return background;
    if (capturing) return PollPolicy.capturing;
    if (connected) return foregroundIdle;
    return PollPolicy.connecting;
  }

  /// Whether the full roster snapshot (JSON serialization of every client)
  /// should be rebuilt on this cycle. Pointless while backgrounded: nothing
  /// displays it, and events already update the state on change.
  static bool shouldReconcileRoster({required bool foreground}) => foreground;
}
