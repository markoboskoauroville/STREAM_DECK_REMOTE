package com.mantra.streamdeckremote

import android.content.Context
import android.graphics.BitmapFactory
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.URL
import java.net.URLEncoder

/** One key as the Mac describes it: kind app · open · scene · next · empty. */
data class KeyInfo(val kind: String, val label: String, val icon: String, val active: Boolean)

/** One profile's keys at version v; title and note are the lines under the deck. */
data class DeckState(val v: Long, val profile: String, val title: String, val note: String, val keys: List<KeyInfo>)

/** The Mac's helper, Stream Deck Remote (Mantra), on port 8963. */
const val PORT = 8963

/**
 * The link to the Mac. No ADB is needed: on the same Wi-Fi the helper is found by Bonjour (_mantradeck._tcp). The
 * other ways, tried in this order: the USB cable or wireless ADB (the helper sets `adb reverse`, so the Mac is at
 * 127.0.0.1 here), the Mac found last time, Bonjour, an address typed by hand, and Tailscale.
 */
class Link(private val ctx: Context, private val scope: CoroutineScope) {
    private val prefs = ctx.getSharedPreferences("deck", Context.MODE_PRIVATE)

    val status = MutableStateFlow("Looking for the Mac…")
    val connected = MutableStateFlow(false)
    val state = MutableStateFlow<DeckState?>(null)
    val profile = MutableStateFlow(prefs.getString("profile", "apps") ?: "apps")
    val visible = MutableStateFlow(true)
    val manual = MutableStateFlow(prefs.getString("manual", "") ?: "")
    val icons = mutableStateMapOf<String, ImageBitmap>()

    @Volatile private var base: String? = null
    @Volatile private var bonjour: String? = null
    private val asked = mutableSetOf<String>()

    fun start() {
        startBonjour()
        scope.launch(Dispatchers.IO) {
            profile.collectLatest { p ->
                var v = -1L
                while (isActive) {
                    visible.first { it }                                  // nothing is asked while the app is not seen
                    val b = base ?: find()
                    if (b == null) {
                        connected.value = false
                        status.value = "Looking for the Mac… (same Wi-Fi, or the cable)"
                        delay(1500)
                        continue
                    }
                    // a long poll: the Mac answers at once when anything changed since v, else after 8 s
                    val body = get("$b/state?profile=$p&v=$v", 12000)
                    val s = body?.let { parse(it) }
                    if (s == null) { base = null; v = -1; connected.value = false; continue }
                    v = s.v
                    state.value = s
                    connected.value = true
                }
            }
        }
    }

    fun setProfile(p: String) {
        if (p == profile.value) return
        prefs.edit().putString("profile", p).apply()
        profile.value = p
    }

    fun setManual(a: String) {
        val t = a.trim()
        prefs.edit().putString("manual", t).apply()
        manual.value = t
        base = null
    }

    fun press(i: Int) {
        val b = base ?: return
        val p = profile.value
        scope.launch(Dispatchers.IO) { get("$b/press?profile=$p&key=$i", 4000) }
    }

    fun loadIcon(id: String) {
        if (id.isEmpty() || icons.containsKey(id)) return
        val b = base ?: return
        synchronized(asked) { if (!asked.add(id)) return }
        scope.launch(Dispatchers.IO) {
            val d = get("$b/icon?id=" + URLEncoder.encode(id, "UTF-8"), 5000)
            val bmp = d?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }?.asImageBitmap()
            withContext(Dispatchers.Main) { if (bmp != null) icons[id] = bmp }
            synchronized(asked) { asked.remove(id) }
        }
    }

    // MARK: finding the Mac

    private fun find(): String? {
        val tries = mutableListOf<Pair<String, String>>()
        tries += "http://127.0.0.1:$PORT" to "cable"
        prefs.getString("last", null)?.let { tries += it to "Wi-Fi" }
        bonjour?.let { tries += it to "Wi-Fi" }
        manual.value.takeIf { it.isNotEmpty() }?.let { m ->
            tries += (if (m.startsWith("http")) m else if (m.contains(":")) "http://$m" else "http://$m:$PORT") to "typed address"
        }
        tries += "http://100.79.251.19:$PORT" to "Tailscale"
        for ((url, how) in tries.distinctBy { it.first }) {
            val d = get("$url/hello", 900) ?: continue
            val name = try { JSONObject(String(d)).optString("name", "the Mac") } catch (e: Exception) { continue }
            if (how != "cable") prefs.edit().putString("last", url).apply()
            status.value = "$name · $how"
            base = url
            return url
        }
        return null
    }

    private fun startBonjour() {
        val nsd = ctx.getSystemService(NsdManager::class.java) ?: return
        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(si: NsdServiceInfo) = resolve(nsd, si)
            override fun onServiceLost(si: NsdServiceInfo) {}
            override fun onDiscoveryStarted(t: String) {}
            override fun onDiscoveryStopped(t: String) {}
            override fun onStartDiscoveryFailed(t: String, e: Int) {}
            override fun onStopDiscoveryFailed(t: String, e: Int) {}
        }
        try { nsd.discoverServices("_mantradeck._tcp", NsdManager.PROTOCOL_DNS_SD, listener) } catch (e: Exception) {}
    }

    @Suppress("DEPRECATION")
    private fun resolve(nsd: NsdManager, si: NsdServiceInfo) {
        try {
            nsd.resolveService(si, object : NsdManager.ResolveListener {
                override fun onResolveFailed(s: NsdServiceInfo, e: Int) {}
                override fun onServiceResolved(s: NsdServiceInfo) {
                    val ip = s.hostAddresses.firstOrNull { it is Inet4Address }?.hostAddress ?: return
                    bonjour = "http://$ip:${s.port}"
                }
            })
        } catch (e: Exception) {}
    }

    // MARK: the wire

    private fun parse(d: ByteArray): DeckState? = try {
        val j = JSONObject(String(d))
        val ks = j.optJSONArray("keys")
        val keys = (0 until (ks?.length() ?: 0)).map { i ->
            val k = ks!!.getJSONObject(i)
            KeyInfo(k.optString("kind", "empty"), k.optString("label", ""), k.optString("icon", ""), k.optBoolean("active", false))
        }
        DeckState(j.optLong("v", 0), j.optString("profile", ""), j.optString("title", ""), j.optString("note", ""), keys)
    } catch (e: Exception) { null }

    private fun get(url: String, timeout: Int): ByteArray? = try {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = minOf(timeout, 1500)
        c.readTimeout = timeout
        c.useCaches = false
        try { if (c.responseCode == 200) c.inputStream.use { it.readBytes() } else null } finally { c.disconnect() }
    } catch (e: Exception) { null }
}
