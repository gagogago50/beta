package com.senlinjun.nek0

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.util.Log

/**
 * Voice-call audio plumbing: platform DSP effects on the capture session and
 * output routing (earpiece / speaker / wired / USB / Bluetooth SCO).
 *
 * Both are what makes a voice client usable on a phone: without the echo
 * canceller, speakerphone sends the remote voices straight back to the other
 * participants; without routing, Android keeps voice-call audio on the earpiece
 * and ignores a connected headset.
 */
class VoiceAudioController(private val context: Context) {

    companion object {
        private const val TAG = "VoiceAudio"

        // Route identifiers shared with Dart (see audio_route.dart).
        const val ROUTE_AUTO = "auto"
        const val ROUTE_EARPIECE = "earpiece"
        const val ROUTE_SPEAKER = "speaker"
        const val ROUTE_WIRED = "wired"
        const val ROUTE_USB = "usb"
        const val ROUTE_BLUETOOTH = "bluetooth"
    }

    private val audioManager: AudioManager
        get() = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var focusRequest: AudioFocusRequest? = null

    /**
     * Invoked when the platform takes audio focus away for good (an incoming
     * call, another voice app). The app mutes the mic rather than keep
     * transmitting into a call the user is not in.
     */
    var onFocusLost: (() -> Unit)? = null

    /** Invoked when focus comes back after a transient loss. */
    var onFocusRegained: (() -> Unit)? = null

    private var echoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var gainControl: AutomaticGainControl? = null

    /** Route requested by the user; re-applied whenever devices change. */
    @Volatile
    var requestedRoute: String = ROUTE_AUTO
        private set

    // ─── Capture effects (AEC / NS / AGC) ────────────────────────────

    /**
     * Availability of each effect on this device. Reported to the UI so the
     * switches can be disabled instead of silently doing nothing — availability
     * is per-device and, for AEC, sometimes per-audio-source.
     */
    fun effectAvailability(): Map<String, Boolean> = mapOf(
        "aec" to AcousticEchoCanceler.isAvailable(),
        "ns" to NoiseSuppressor.isAvailable(),
        "agc" to AutomaticGainControl.isAvailable(),
    )

    /**
     * Attaches the requested platform effects to the capture session
     * [audioSessionId]. Every effect is optional and independent: a device
     * missing one must still get the others.
     *
     * Must be called after the AudioRecord is created (the session ID only
     * exists then) and released before it is.
     */
    fun attachEffects(
        audioSessionId: Int,
        enableAec: Boolean,
        enableNs: Boolean,
        enableAgc: Boolean,
    ) {
        releaseEffects()
        if (enableAec && AcousticEchoCanceler.isAvailable()) {
            echoCanceler = runCatching {
                AcousticEchoCanceler.create(audioSessionId)?.apply { enabled = true }
            }.onFailure { Log.w(TAG, "AEC unavailable: ${it.javaClass.simpleName}") }
                .getOrNull()
        }
        if (enableNs && NoiseSuppressor.isAvailable()) {
            noiseSuppressor = runCatching {
                NoiseSuppressor.create(audioSessionId)?.apply { enabled = true }
            }.onFailure { Log.w(TAG, "NS unavailable: ${it.javaClass.simpleName}") }
                .getOrNull()
        }
        if (enableAgc && AutomaticGainControl.isAvailable()) {
            gainControl = runCatching {
                AutomaticGainControl.create(audioSessionId)?.apply { enabled = true }
            }.onFailure { Log.w(TAG, "AGC unavailable: ${it.javaClass.simpleName}") }
                .getOrNull()
        }
        Log.i(
            TAG,
            "effects attached aec=${echoCanceler != null} " +
                "ns=${noiseSuppressor != null} agc=${gainControl != null}",
        )
    }

    /** Releases the effects. Safe to call when nothing is attached. */
    fun releaseEffects() {
        echoCanceler?.runCatching { release() }
        noiseSuppressor?.runCatching { release() }
        gainControl?.runCatching { release() }
        echoCanceler = null
        noiseSuppressor = null
        gainControl = null
    }

    // ─── Output routing ──────────────────────────────────────────────

    /**
     * Puts the audio system in voice-communication mode. Without this the
     * platform treats the stream as media: no echo cancellation reference
     * signal, and no earpiece routing.
     */
    fun startVoiceMode() {
        runCatching { audioManager.mode = AudioManager.MODE_IN_COMMUNICATION }
            .onFailure { Log.w(TAG, "cannot enter communication mode") }
        requestFocus()
    }

    /** Restores normal mode, releases focus and drops any forced route. */
    fun stopVoiceMode() {
        abandonFocus()
        runCatching {
            clearForcedRoute()
            audioManager.mode = AudioManager.MODE_NORMAL
        }
    }

    /**
     * Takes voice-communication audio focus.
     *
     * Without it the app fights the music player instead of ducking it, and it
     * never learns about an incoming phone call — it would keep capturing the
     * microphone during the call.
     */
    private fun requestFocus() {
        if (focusRequest != null) return
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attributes)
            // Voice must never be ducked to inaudible: pausing the other app
            // is the correct behaviour for a call-like use case.
            .setWillPauseWhenDucked(true)
            .setOnAudioFocusChangeListener { change ->
                when (change) {
                    AudioManager.AUDIOFOCUS_LOSS,
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                    -> onFocusLost?.invoke()

                    AudioManager.AUDIOFOCUS_GAIN -> onFocusRegained?.invoke()
                }
            }
            .build()
        val granted = runCatching { audioManager.requestAudioFocus(request) }
            .getOrDefault(AudioManager.AUDIOFOCUS_REQUEST_FAILED)
        if (granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            focusRequest = request
        } else {
            Log.w(TAG, "audio focus denied ($granted)")
        }
    }

    private fun abandonFocus() {
        focusRequest?.let { request ->
            runCatching { audioManager.abandonAudioFocusRequest(request) }
        }
        focusRequest = null
    }

    /** Routes currently available, as identifiers understood by Dart. */
    @SuppressLint("MissingPermission")
    fun availableRoutes(): List<String> {
        val routes = mutableListOf(ROUTE_AUTO, ROUTE_EARPIECE, ROUTE_SPEAKER)
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        for (device in devices) {
            when (device.type) {
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                -> if (!routes.contains(ROUTE_WIRED)) routes.add(ROUTE_WIRED)

                AudioDeviceInfo.TYPE_USB_HEADSET,
                AudioDeviceInfo.TYPE_USB_DEVICE,
                -> if (!routes.contains(ROUTE_USB)) routes.add(ROUTE_USB)

                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_BLE_HEADSET,
                -> if (!routes.contains(ROUTE_BLUETOOTH)) routes.add(ROUTE_BLUETOOTH)
            }
        }
        // An earpiece only exists on phones.
        if (devices.none { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }) {
            routes.remove(ROUTE_EARPIECE)
        }
        return routes
    }

    /**
     * Applies [route]. Returns the route actually applied, which may differ
     * from the request when the device disappeared in between (e.g. headset
     * unplugged while the picker was open).
     */
    @SuppressLint("MissingPermission")
    fun applyRoute(route: String): String {
        requestedRoute = route
        if (route == ROUTE_AUTO) {
            clearForcedRoute()
            return ROUTE_AUTO
        }

        val wanted = matchingDeviceTypes(route)
        val device = audioManager
            .getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .firstOrNull { wanted.contains(it.type) }
        if (device == null) {
            Log.w(TAG, "route $route not available, falling back to auto")
            clearForcedRoute()
            return ROUTE_AUTO
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // API 31+: one explicit call, no deprecated SCO dance.
            val ok = runCatching { audioManager.setCommunicationDevice(device) }
                .getOrDefault(false)
            if (ok) route else ROUTE_AUTO
        } else {
            applyLegacyRoute(route)
        }
    }

    /**
     * Pre-Android 12 routing. `startBluetoothSco` is deprecated on newer
     * releases but is the only way to get SCO on API 28–30, which the app
     * still supports (minSdk 28).
     */
    @Suppress("DEPRECATION")
    private fun applyLegacyRoute(route: String): String {
        val manager = audioManager
        return runCatching {
            when (route) {
                ROUTE_BLUETOOTH -> {
                    manager.isSpeakerphoneOn = false
                    manager.isBluetoothScoOn = true
                    manager.startBluetoothSco()
                }

                ROUTE_SPEAKER -> {
                    stopScoIfNeeded(manager)
                    manager.isSpeakerphoneOn = true
                }

                // Wired and USB headsets take priority over the earpiece
                // automatically once speakerphone and SCO are off.
                else -> {
                    stopScoIfNeeded(manager)
                    manager.isSpeakerphoneOn = false
                }
            }
            route
        }.getOrElse {
            Log.w(TAG, "legacy routing failed: ${it.javaClass.simpleName}")
            ROUTE_AUTO
        }
    }

    @Suppress("DEPRECATION")
    private fun stopScoIfNeeded(manager: AudioManager) {
        if (manager.isBluetoothScoOn) {
            manager.isBluetoothScoOn = false
            manager.stopBluetoothSco()
        }
    }

    @Suppress("DEPRECATION")
    private fun clearForcedRoute() {
        requestedRoute = ROUTE_AUTO
        val manager = audioManager
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                manager.clearCommunicationDevice()
            } else {
                stopScoIfNeeded(manager)
                manager.isSpeakerphoneOn = false
            }
        }
    }

    private fun matchingDeviceTypes(route: String): Set<Int> = when (route) {
        ROUTE_EARPIECE -> setOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
        ROUTE_SPEAKER -> setOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
        ROUTE_WIRED -> setOf(
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        )

        ROUTE_USB -> setOf(
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE,
        )

        ROUTE_BLUETOOTH -> setOf(
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
        )

        else -> emptySet()
    }

    /** Human-readable current route, for diagnostics. */
    fun currentRoute(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val device = runCatching { audioManager.communicationDevice }.getOrNull()
                ?: return ROUTE_AUTO
            return when (device.type) {
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> ROUTE_EARPIECE
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> ROUTE_SPEAKER
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                -> ROUTE_WIRED

                AudioDeviceInfo.TYPE_USB_HEADSET,
                AudioDeviceInfo.TYPE_USB_DEVICE,
                -> ROUTE_USB

                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_BLE_HEADSET,
                -> ROUTE_BLUETOOTH

                else -> ROUTE_AUTO
            }
        }
        return requestedRoute
    }

    /** True when a Bluetooth headset usable for voice is connected. */
    @SuppressLint("MissingPermission")
    fun isBluetoothHeadsetConnected(): Boolean = runCatching {
        audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET
        }
    }.getOrDefault(false)
}
