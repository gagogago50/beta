# AGENTS.md

NEk0: an Android TeamSpeak 3 client. Flutter UI + Rust FFI. The connection, audio codec,
and session state live entirely in a Rust `.so` inside the app process.

## Build & verify

```bash
# 1. Rust → .so (REQUIRED before the app can run; libtsclient.so is gitignored)
#    Requires ANDROID_NDK_HOME set to an installed NDK.
python3 pre_build.py   # builds x86_64+aarch64, copies .so into android/app/src/main/jniLibs/

# 2. Dart checks — must pass before committing (CI runs `--set-exit-if-changed`)
dart format . --set-exit-if-changed
flutter analyze

# 3. App
flutter run / flutter build apk
```

A missing `libtsclient.so` does NOT fail the Gradle build — it crashes at runtime in
`lib/services/ts_ffi.dart` (`DynamicLibrary.open('libtsclient.so')`). CI
(`.github/workflows/ci.yml`) runs only on tag pushes: `cargo check` → `pre_build.py` →
`flutter gen-l10n` + `dart format` + `flutter analyze` → `flutter build apk` (release artifacts).

## Architecture

- `native/` — Rust `cdylib` (`tsclient`). `src/lib.rs`: globals (`STATE` mutex, tokio
  `RUNTIME`, `CONNECTION_STASH`, lock-free per-client jitter buffers, `AUDIO_STREAM` cpal
  stream). `src/api.rs`: all `ts_*` FFI exports, the connection event loop, audio mixing.
- `native/Cargo.toml` **patches** the tsclientlib/tsproto git deps to the vendored copy in
  `native/local_tsclientlib/` — keep the vendored sources and git branch in sync.
- `lib/services/ts_ffi.dart` — FFI bindings. Rust-returned strings MUST be freed via
  `ts_free_string` (the `_ptrToString` helper does this; use it for any new FFI functions).
- Connection lifecycle: `do_connect` emits `connection_phase` events (resolving →
  connecting → authenticating) and fails with a structured `connect_failed`
  (`kind`/`retryable` derived from the `tsclientlib::Error` *variant* in
  `classify_connect_error` — never from message text). `ts_cancel_connect` aborts the
  in-flight attempt via `CONNECT_TASK`. `disconnected` carries `expected` so Dart can tell
  a user-requested disconnect from a dropped link; only the latter triggers
  `ReconnectPolicy` (2s→30s exponential backoff, ±20% jitter, 6 attempts, never for
  password/ban/cancelled) which also restores the pre-drop channel by name.
- Event flow: Dart polls `TsNative.pollEvents()` on a 200ms `Timer.periodic`; Rust pushes
  `TsEvent`s (`connected`, `disconnected`, `text_message`, ...) that drive Riverpod state,
  audio, and the foreground service.
- Whisper: outgoing whisper lives entirely in `Command::SendAudio` handling —
  `STATE.whisper_active` + target lists switch the packet from `AudioData::C2S` to
  `AudioData::C2SWhisper`, with its own `whisper_seq` counter and a zero-length
  terminator frame on every voice↔whisper switch. Targets are session-scoped IDs
  (reset in `ts_connect`, pruned in Dart); the incoming allow list is keyed by UID
  and enforced in `whisper_is_allowed()` before Opus decoding.
- Playback is Rust `cpal` (continuous output stream, silence when idle); mic capture is
  Kotlin `AudioRecord` in `MainActivity.kt`, streamed to Dart over EventChannel
  `com.senlinjun.nek0/mic`. (README's `flutter_pcm_sound` architecture line is stale — cpal.)

## Android specifics

- Voice audio DSP and output routing live in `VoiceAudioController.kt`
  (MethodChannel `com.senlinjun.nek0/audio`): AEC/NS/AGC are attached to the
  `AudioRecord` session id — always after `MODE_IN_COMMUNICATION` and always guarded by
  `isAvailable()` — and released before the record. Routing uses
  `setCommunicationDevice` on API 31+ with a legacy `startBluetoothSco` path for API 28-30.
  `applyRoute` returns the route actually applied; Dart trusts that return value.
- Kotlin cannot be compiled by CI-less sandboxes: `kotlinc -cp <android.jar>` type-checks
  `VoiceAudioController.kt` standalone, the rest needs Gradle (AndroidX + generated `R`).

- MethodChannel `com.senlinjun.nek0/service` (start/update/stop foreground service,
  `request_battery_optimization_exemption`) is handled in `MainActivity.kt`.
- One cached FlutterEngine (`"teamspeak_engine"`) is shared by the Activity and
  `NotificationActionReceiver` so platform channels keep working while backgrounded.
- Keep-alive: `KeepAliveService.kt` runs a foreground service (mediaPlayback[|microphone])
  + a `MediaSession` in PLAYING state while connected — this is what exempts the app from
  Android 14/15 background kill policies (Android 15 caps mediaPlayback FGS at 6h/24h
  without an active media session). Changes here must keep that design intact.
- **Swipe-away disconnect is intentional**: `onTaskRemoved` calls `tsDisconnect()` and
  tears down the service — do not change it.
- Kotlin gotcha: `android.app.Notification` has NO `setMediaSession()`/`mediaSession` member
  (verified via javap on the SDK jar). The session token attaches only through
  `Notification.MediaStyle().setMediaSession(token)` on the Builder (`buildNotification`).
- Kotlin sources live under `kotlin/com/example/teamspeak_apk/` but declare
  `package com.senlinjun.nek0` (the applicationId). Keep the package, not the directory.

## Battery

- The Dart poll timer is a safety net, never a data path: `PollPolicy` picks 50ms only in the
  foreground while capturing, 2s foreground idle, **15s backgrounded**. Roster JSON
  reconciliation is skipped entirely while backgrounded. Do not reintroduce a fixed cadence.
- Mic capture uses `READ_BLOCKING` with a reused frame buffer — never poll with
  `READ_NON_BLOCKING` + sleep, that was ~100 wakeups/s in silence.
- The Rust maintenance task ticks 500ms only while `CLIENT_BUFFERS` is non-empty, 2s otherwise.
- `PARTIAL_WAKE_LOCK` is taken only when audio needs it and released on full mute
  (`applyWakeLock`). The foreground service + MediaSession keep the process alive on their own.

## Chat threads

- A message belongs to `channel`, `server` or `client:<peer>`. For private messages the peer
  is **not** the sender for outgoing ones: `ChatMessage.peerId` holds the recipient, which is
  what keeps both halves of a conversation in one thread. Legacy entries without a peer fall
  back to the sender.
- Unread counters live per thread key: own messages never count, and the thread currently
  open on screen never counts (`openThread`/`closeThreads`).

## Encrypted storage

- Secrets and the chat history share one Keystore key (`SecureStorage.kt`). Small values go
  to the SharedPreferences path (`put`/`get`), anything sizeable goes to the **file** path
  (`writeFile`/`readFile`): temp-file + rename, file name used as AAD, undecryptable files
  deleted and treated as absent.
- Chat history is opt-in, one file per `server_uid`, pruned by retention *and* a 500-entry
  cap (`ChatHistoryService.prune`, a pure function — keep it that way, it is what the tests
  cover). Writes are debounced 3s; disabling the feature deletes what was stored.

## File transfers

- Downloads run off the event loop (`spawn_file_download`): `ftinitdownload` on the command
  channel, then a plain TCP connection where the one-shot `ftkey` is sent first. The payload
  is buffered in memory and written once — never stream straight to disk, a truncated file
  would be cached as valid.
- Two independent size checks: the server-announced size before connecting, and the real
  byte count while reading. `TRANSFER_HARD_LIMIT` (8 MiB) caps whatever the caller asked for.
- Target paths come from Android (`cache_dir` on the audio channel); the engine refuses
  relative paths and any `..`. An unsolicited `notifystartdownload` opens no socket.

## Permissions

- What we may do to another client comes from `notifyclientpermhints`
  (`ClientPermissionHint` bitmask), stored per client in `STATE.permission_hints`, serialized
  as `permission_hints` and decoded by `ClientPermissions` in Dart. **Default is deny**: no
  hint means no action.
- UI rule: build only the allowed entries (`ModerationSheet`). Never show a disabled action
  and never assume success — the server can still refuse with a typed `command_error`.

## Command rate limiting

- Every control command goes through `COMMAND_BUDGET` (`CommandBudget` in `native/src/lib.rs`)
  before reaching the server: token bucket (8 burst / 3 per second), bounded queue, and
  state commands supersede themselves (`Command::supersedes`) so a burst of channel moves
  collapses to the last one. Audio and `Disconnect` bypass it deliberately.
- A `ClientIsFlooding`/`BanFlooding` answer switches the budget to degraded mode for 30s.
  New FFI commands must declare a `flood_cost` and, if they carry state, a supersede rule.

## Logging & secrets

- **Never** use `debugPrint`/`print` in Dart or `eprintln!` in Rust. Use `AppLog.*`
  (`lib/services/app_log.dart`) and the `log_error!/log_warn!/log_info!/log_debug!` macros
  (`native/src/lib.rs`). Both redact addresses, nicknames, UIDs, identity blobs and the
  values of secret-looking keys, and both are level-filtered (release floor: warn).
- Log the exception **type**, never the instance: exception messages embed the offending
  value. `AppLog.e(tag, msg, error)` already does this.
- `ts_set_log_level` keeps the engine level in sync with the Dart one.
- Erasure path (`eraseIdentityAndSecrets` + `ServerListNotifier.eraseAllSecrets`) must stay
  ordered: disconnect → `ts_clear_identity` → Keystore → passwords → UID-keyed prefs.
  Skipping the engine wipe resurrects the identity on the next connect.

## Conventions

- CI (`.github/workflows/ci.yml`) runs on every push/PR: `cargo fmt`/`check`/
  `clippy -p tsclient -- -D warnings`/`test`, then NDK + `pre_build.py` + `gen-l10n` +
  `dart format` + `analyze` + `flutter test` + debug APK. Keep `-p tsclient` on the clippy
  step: the vendored ReSpeak sources carry hundreds of upstream warnings.
- Tests: `flutter test` (`test/`) and `cargo test` (unit tests at
  the bottom of `native/src/api.rs`). Verification for any change is `dart format` +
  `flutter analyze` + `flutter test` (+ `cargo check`/`cargo test` for Rust changes).
- Keep all code and comments in English.
- i18n: all UI strings go through `AppLocalizations` (gen-l10n). After editing
  `lib/l10n/*.arb`, run `flutter gen-l10n` — generated files in `lib/l10n/generated/`
  ARE committed (CI's `dart format`/`analyze` depend on them). Notification-button
  labels are localized in Dart and passed to `KeepAliveService` via the service
  channel (`mute_label`/`unmute_label`/`disconnect_label`).
