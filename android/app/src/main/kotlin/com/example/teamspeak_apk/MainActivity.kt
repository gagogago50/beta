package com.senlinjun.nek0

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private var audioRecord: AudioRecord? = null
    private val secureStorage by lazy { SecureStorage(applicationContext) }
    private val voiceAudio by lazy { VoiceAudioController(applicationContext) }
    private val identityBackup by lazy { IdentityBackup() }
    @Volatile var isRecording = false

    // Platform DSP preferences, pushed from Dart and applied when the capture
    // session is (re)created. AGC defaults to off: the app already exposes a
    // manual mic gain, and stacking both fights the VAD threshold.
    @Volatile private var aecEnabled = true
    @Volatile private var nsEnabled = true
    @Volatile private var agcEnabled = false

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        val cacheKey = "teamspeak_engine"
        var engine = FlutterEngineCache.getInstance().get(cacheKey)
        if (engine == null) {
            engine = FlutterEngine(context)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            FlutterEngineCache.getInstance().put(cacheKey, engine)
        }
        return engine
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Mic capture via EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.senlinjun.nek0/mic")
            .setStreamHandler(MicStreamHandler(this))

        // Network availability / transport changes for the reconnect policy.
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.senlinjun.nek0/connectivity",
        ).setStreamHandler(ConnectivityStreamHandler(applicationContext))

        // Keystore-backed storage for the TS identity and server passwords.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.senlinjun.nek0/secure_storage",
        ).setMethodCallHandler { call, result ->
            // File operations use a "name" argument instead of "key".
            if (call.method == "write_file" ||
                call.method == "read_file" ||
                call.method == "delete_file" ||
                call.method == "delete_all_files"
            ) {
                try {
                    when (call.method) {
                        "write_file" -> {
                            val name = call.argument<String>("name")
                            val value = call.argument<String>("value")
                            if (name == null || value == null) {
                                result.error("invalid_args", "name and value are required", null)
                            } else {
                                secureStorage.writeFile(name, value)
                                result.success(true)
                            }
                        }
                        "read_file" -> {
                            val name = call.argument<String>("name")
                            if (name == null) {
                                result.error("invalid_args", "name is required", null)
                            } else {
                                result.success(secureStorage.readFile(name))
                            }
                        }
                        "delete_file" -> {
                            val name = call.argument<String>("name")
                            if (name == null) {
                                result.error("invalid_args", "name is required", null)
                            } else {
                                result.success(secureStorage.deleteFile(name))
                            }
                        }
                        else -> result.success(secureStorage.deleteAllFiles())
                    }
                } catch (error: Exception) {
                    result.error("secure_storage_error", error.javaClass.simpleName, null)
                }
                return@setMethodCallHandler
            }
            val key = call.argument<String>("key")
            if (key.isNullOrBlank()) {
                result.error("invalid_key", "Secure storage key is required", null)
                return@setMethodCallHandler
            }
            try {
                when (call.method) {
                    "get" -> result.success(secureStorage.get(key))
                    "put" -> {
                        val value = call.argument<String>("value")
                        if (value == null) {
                            result.error("invalid_value", "Secure storage value is required", null)
                        } else {
                            secureStorage.put(key, value)
                            result.success(true)
                        }
                    }
                    "delete" -> result.success(secureStorage.delete(key))
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                // Never include the value or cryptographic material in errors.
                result.error("secure_storage_error", error.javaClass.simpleName, null)
            }
        }

        // Audio focus: an incoming call or another voice app must silence our
        // capture, and Dart owns the mute state, so the events are forwarded.
        val audioChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.senlinjun.nek0/audio",
        )
        voiceAudio.onFocusLost = {
            runOnUiThread { audioChannel.invokeMethod("focus_lost", null) }
        }
        voiceAudio.onFocusRegained = {
            runOnUiThread { audioChannel.invokeMethod("focus_regained", null) }
        }

        // Voice audio: platform DSP effects and output routing.
        audioChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "effect_availability" -> result.success(voiceAudio.effectAvailability())
                "set_effects" -> {
                    aecEnabled = call.argument<Boolean>("aec") ?: aecEnabled
                    nsEnabled = call.argument<Boolean>("ns") ?: nsEnabled
                    agcEnabled = call.argument<Boolean>("agc") ?: agcEnabled
                    // Re-attach immediately when a session is already live, so a
                    // toggle takes effect without cycling the mic.
                    val session = audioRecord?.audioSessionId
                    if (session != null) {
                        voiceAudio.attachEffects(session, aecEnabled, nsEnabled, agcEnabled)
                    }
                    result.success(true)
                }
                "list_routes" -> result.success(voiceAudio.availableRoutes())
                "set_route" -> {
                    val route = call.argument<String>("route")
                    if (route == null) {
                        result.error("invalid_route", "route is required", null)
                    } else {
                        result.success(voiceAudio.applyRoute(route))
                    }
                }
                "current_route" -> result.success(voiceAudio.currentRoute())
                // File-transfer targets must stay inside app-private storage:
                // Dart asks Android for the path instead of building one.
                "cache_dir" -> result.success(cacheDir.absolutePath)
                "bluetooth_connected" ->
                    result.success(voiceAudio.isBluetoothHeadsetConnected())
                else -> result.notImplemented()
            }
        }

        // Foreground service control via MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.senlinjun.nek0/service")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val title = call.argument<String>("title") ?: "TeamSpeak"
                        val text = call.argument<String>("text") ?: "Connected"
                        val mic = call.argument<Boolean>("mic") ?: false
                        val inputMuted = call.argument<Boolean>("input_muted") ?: false
                        val fullMuted = call.argument<Boolean>("full_muted") ?: false
                        val muteLabel = call.argument<String>("mute_label") ?: "Mute"
                        val unmuteLabel = call.argument<String>("unmute_label") ?: "Unmute"
                        val disconnectLabel = call.argument<String>("disconnect_label") ?: "Disconnect"
                        KeepAliveService.start(
                            this, title, text, mic, inputMuted, fullMuted,
                            muteLabel, unmuteLabel, disconnectLabel,
                        )
                        result.success(true)
                    }
                    "stop" -> {
                        KeepAliveService.stop(this)
                        result.success(true)
                    }
                    "update" -> {
                        val title = call.argument<String>("title") ?: "TeamSpeak"
                        val text = call.argument<String>("text") ?: "Connected"
                        val mic = call.argument<Boolean>("mic") ?: false
                        val inputMuted = call.argument<Boolean>("input_muted") ?: false
                        val fullMuted = call.argument<Boolean>("full_muted") ?: false
                        val muteLabel = call.argument<String>("mute_label") ?: "Mute"
                        val unmuteLabel = call.argument<String>("unmute_label") ?: "Unmute"
                        val disconnectLabel = call.argument<String>("disconnect_label") ?: "Disconnect"
                        KeepAliveService.update(
                            this, title, text, mic, inputMuted, fullMuted,
                            muteLabel, unmuteLabel, disconnectLabel,
                        )
                        result.success(true)
                    }
                    "request_battery_optimization_exemption" -> {
                        result.success(requestBatteryOptimizationExemption())
                    }
                    else -> result.notImplemented()
                }
            }

        // Password-protected identity export/import. The password never leaves
        // Dart as plaintext: the identity JSON crosses this channel exactly once
        // and the sealed blob is returned for the user to save.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.senlinjun.nek0/identity_backup",
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "encrypt" -> {
                        val value = call.argument<String>("value")
                        val password = call.argument<String>("password")
                        if (value == null || password == null) {
                            result.error("invalid_args", "value and password are required", null)
                        } else {
                            result.success(identityBackup.encrypt(value, password))
                        }
                    }
                    "decrypt" -> {
                        val blob = call.argument<String>("blob")
                        val password = call.argument<String>("password")
                        if (blob == null || password == null) {
                            result.error("invalid_args", "blob and password are required", null)
                        } else {
                            result.success(identityBackup.decrypt(blob, password))
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                // Map "bad password"/"tampered" to a stable code the UI can
                // translate, without leaking content.
                val code = when (error) {
                    is javax.crypto.AEADBadTagException -> "bad_password"
                    is IllegalArgumentException -> "bad_format"
                    else -> "error"
                }
                result.error(code, error.javaClass.simpleName, null)
            }
        }
    }

    /// Music players stay alive partly because they're exempt from battery
    /// optimization. Ask the system for the same exemption on first connect.
    private fun requestBatteryOptimizationExemption(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val pkg = packageName
        if (pm.isIgnoringBatteryOptimizations(pkg)) return true
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$pkg")
                )
            )
            false
        } catch (_: Exception) {
            false
        }
    }

    fun startMic(): Boolean {
        if (isRecording) return true
        val sampleRate = 48000
        val bufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_FLOAT,
        )
        if (bufferSize == AudioRecord.ERROR || bufferSize == AudioRecord.ERROR_BAD_VALUE) {
            return false
        }

        val record = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_FLOAT,
            bufferSize * 2,
        )
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            return false
        }

        audioRecord = record
        // MODE_IN_COMMUNICATION must be set before the effects are attached:
        // the echo canceller needs the platform to treat this as a voice call
        // to get a proper far-end reference signal.
        voiceAudio.startVoiceMode()
        voiceAudio.attachEffects(record.audioSessionId, aecEnabled, nsEnabled, agcEnabled)
        // Re-assert the user's route: connecting a headset or entering
        // communication mode can reset it.
        voiceAudio.applyRoute(voiceAudio.requestedRoute)
        record.startRecording()
        isRecording = true
        return true
    }

    fun stopMic() {
        isRecording = false
        // Effects hold a reference to the capture session: release them first.
        voiceAudio.releaseEffects()
        audioRecord?.let {
            it.stop()
            it.release()
        }
        audioRecord = null
        voiceAudio.stopVoiceMode()
    }

    /// 20 ms at 48 kHz. Reused across reads: allocating a frame 50 times a
    /// second is 200 kB/s of garbage for nothing.
    private val micFrame = FloatArray(960)

    /**
     * Blocking read of exactly one frame.
     *
     * The previous implementation polled with READ_NON_BLOCKING and slept 10 ms
     * on failure: that woke the CPU ~100 times a second even in silence.
     * A blocking read parks the thread until the hardware has data, which is
     * what AudioRecord is designed for and costs nothing while idle.
     */
    fun readMicBuffer(): FloatArray? {
        val record = audioRecord ?: return null
        if (!isRecording) return null
        val read = record.read(micFrame, 0, micFrame.size, AudioRecord.READ_BLOCKING)
        if (read <= 0) return null
        return if (read < micFrame.size) micFrame.copyOf(read) else micFrame
    }
}

class MicStreamHandler(private val activity: MainActivity) : EventChannel.StreamHandler {
    private var sink: EventChannel.EventSink? = null
    private var thread: Thread? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        if (activity.startMic()) {
            thread = Thread {
                // Raised priority: the capture thread must not be preempted by
                // UI work, otherwise frames are dropped and the codec stutters.
                android.os.Process.setThreadPriority(
                    android.os.Process.THREAD_PRIORITY_URGENT_AUDIO,
                )
                // Reused every frame: allocating a 3840-byte array 50×/s (200 kB/s
                // of garbage) is what the legacy path did. The frame is consumed
                // synchronously by the codec, so reusing it is safe.
                val bytes = ByteArray(960 * 4)
                val byteBuffer = ByteBuffer.wrap(bytes)
                    .order(ByteOrder.LITTLE_ENDIAN)
                    .asFloatBuffer()
                while (activity.isRecording) {
                    // Blocking read: no polling loop, no sleep, no wakeups
                    // while the microphone has nothing to give.
                    val data = activity.readMicBuffer() ?: continue
                    byteBuffer.clear()
                    byteBuffer.put(data, 0, data.size)
                    // Fire directly on the capture thread. The event codec
                    // serializes synchronously, so `bytes` is fully consumed
                    // before the next read — no per-frame UI thread dispatch.
                    sink?.success(bytes)
                }
            }.also { it.start() }
        }
    }

    override fun onCancel(arguments: Any?) {
        activity.stopMic()
        sink = null
        thread = null
    }
}
