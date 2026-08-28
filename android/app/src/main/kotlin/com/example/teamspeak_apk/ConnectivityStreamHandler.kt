package com.senlinjun.nek0

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Streams network availability to Dart so the reconnection policy can fire as
 * soon as connectivity is back instead of waiting out its backoff.
 *
 * It also reports the *transport* and a network identifier: moving from Wi-Fi
 * to mobile keeps "a network available" from the system's point of view, but
 * the local address changed, so an existing TeamSpeak session is dead and the
 * client must reconnect rather than wait for a timeout.
 */
class ConnectivityStreamHandler(private val context: Context) :
    EventChannel.StreamHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    private val manager: ConnectivityManager
        get() = context.getSystemService(Context.CONNECTIVITY_SERVICE)
            as ConnectivityManager

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        val networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = emit(network, true)

            override fun onLost(network: Network) = emit(network, false)

            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities,
            ) {
                // Fires on Wi-Fi ↔ mobile handover and on validation changes;
                // the transport in the payload is what lets Dart notice the
                // change of path.
                emit(network, true, capabilities)
            }
        }
        callback = networkCallback
        runCatching { manager.registerNetworkCallback(request, networkCallback) }
            .onFailure { sink?.let { s -> mainHandler.post { s.error("register_failed", it.javaClass.simpleName, null) } } }

        // Emit the current state immediately: a listener attaching after a
        // drop would otherwise wait for the next system event.
        emitCurrentState()
    }

    override fun onCancel(arguments: Any?) {
        callback?.let { runCatching { manager.unregisterNetworkCallback(it) } }
        callback = null
        sink = null
    }

    private fun emitCurrentState() {
        val active = manager.activeNetwork
        if (active == null) {
            postEvent(mapOf("available" to false, "transport" to "none", "network" to ""))
            return
        }
        emit(active, true, manager.getNetworkCapabilities(active))
    }

    private fun emit(
        network: Network,
        available: Boolean,
        capabilities: NetworkCapabilities? = null,
    ) {
        val caps = capabilities ?: manager.getNetworkCapabilities(network)
        val transport = when {
            caps == null -> "unknown"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            else -> "other"
        }
        val validated = caps?.hasCapability(
            NetworkCapabilities.NET_CAPABILITY_VALIDATED,
        ) ?: false
        postEvent(
            mapOf(
                // A network that is up but not validated (captive portal) is
                // not usable for a TeamSpeak session.
                "available" to (available && validated),
                "transport" to transport,
                // Opaque handle: Dart only compares it with the previous one
                // to detect a path change.
                "network" to network.toString(),
            ),
        )
    }

    private fun postEvent(payload: Map<String, Any>) {
        val target = sink ?: return
        // Platform channels must be touched from the main thread only.
        mainHandler.post { target.success(payload) }
    }
}
