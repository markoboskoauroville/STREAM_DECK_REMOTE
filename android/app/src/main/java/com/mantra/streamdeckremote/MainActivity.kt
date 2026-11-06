package com.mantra.streamdeckremote

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.lifecycleScope

private val Bg = Color(0xFF0B0B0C)
private val Body = Color(0xFF1C1C1E)
private val Rim = Color(0xFF2C2C2E)
private val KeyBg = Color(0xFF000000)
private val KeyRim = Color(0xFF26262A)
private val Green = Color(0xFF33D17A)
private val Amber = Color(0xFFFF9F0A)
private val Grey = Color(0xFF8E8E93)
private val White = Color(0xFFF2F2F7)

/** The profiles, the tabs at the bottom (Marko, 6.11.2026: "we can make tabs at the bottom so user can switch"). */
private val PROFILES = listOf("apps" to "APPS", "obs" to "OBS")

class MainActivity : ComponentActivity() {
    private lateinit var link: Link

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)   // a deck on the desk never goes dark
        link = Link(applicationContext, lifecycleScope)
        link.start()
        setContent { DeckScreen(link) }
    }

    override fun onStart() { super.onStart(); link.visible.value = true }
    override fun onStop() { link.visible.value = false; super.onStop() }
}

@Composable
private fun DeckScreen(link: Link) {
    val st by link.state.collectAsState()
    val profile by link.profile.collectAsState()
    val status by link.status.collectAsState()
    val connected by link.connected.collectAsState()
    var ask by remember { mutableStateOf(false) }
    val shown = st?.takeIf { it.profile == profile && connected }
    // a press on either face (the real deck or this phone) enlarges that key here too
    val pulses = remember { mutableStateMapOf<Int, Int>() }
    var seen by remember { mutableStateOf(-1L) }
    LaunchedEffect(st?.presses) {
        val s = st ?: return@LaunchedEffect
        if (seen >= 0 && s.presses > seen && s.pressed in 0..14) pulses[s.pressed] = (pulses[s.pressed] ?: 0) + 1
        seen = s.presses
    }

    Box(Modifier.fillMaxSize().background(Bg).windowInsetsPadding(WindowInsets.safeDrawing).padding(16.dp)) {
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
            // the line to the Mac; a tap types an address by hand
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { ask = true }
                    .padding(vertical = 10.dp, horizontal = 4.dp)
                    .semantics { contentDescription = "connection" },
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(Modifier.size(9.dp).clip(CircleShape).background(if (connected) Green else Amber))
                Spacer(Modifier.width(10.dp))
                Text(if (connected) status else "Looking for the Mac… (same Wi-Fi, or the cable)",
                    color = Grey, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }

            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                val gap = 10.dp
                val pad = 14.dp
                val byW = (maxWidth - pad * 2 - gap * 4) / 5
                val byH = (maxHeight - pad * 2 - gap * 2 - 64.dp) / 3
                val k: Dp = minOf(byW, byH, 120.dp)
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    // the deck: 5 across, 3 down, like the Elgato on the desk
                    Column(
                        Modifier.clip(RoundedCornerShape(22.dp)).background(Body)
                            .border(1.dp, Rim, RoundedCornerShape(22.dp)).padding(pad),
                        verticalArrangement = Arrangement.spacedBy(gap)
                    ) {
                        for (r in 0 until 3) Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                            for (c in 0 until 5) {
                                val i = r * 5 + c
                                KeyView(shown?.keys?.getOrNull(i), k, i, pulses[i] ?: 0, link)
                            }
                        }
                    }
                    Spacer(Modifier.height(14.dp))
                    Text(shown?.title ?: "", color = White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold,
                        maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
                    Text(shown?.note ?: "", color = Grey, fontSize = 13.sp, maxLines = 2,
                        overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
                }
            }

            Tabs(profile) { link.setProfile(it) }
        }
    }
    if (ask) AddressDialog(link.manual.value, { link.setManual(it); ask = false }) { ask = false }
}

@Composable
private fun KeyView(k: KeyInfo?, size: Dp, index: Int, pulse: Int, link: Link) {
    val haptic = LocalHapticFeedback.current
    val src = remember { MutableInteractionSource() }
    // the press: up to 118 % and back, as the real deck shows it (Marko, 6.11.2026: "the button enlarges for certain
    // percentage and then come back indicating that it was pressed")
    val grow = remember { Animatable(1f) }
    LaunchedEffect(pulse) {
        if (pulse > 0) {
            grow.animateTo(1.18f, tween(80))
            grow.animateTo(1f, tween(160))
        }
    }
    val scale = grow.value
    val live = k != null && k.kind != "empty"
    val ring = k?.active == true && k.kind == "scene"
    val shape = RoundedCornerShape(size * 0.16f)
    val d = LocalDensity.current
    Box(
        Modifier.size(size).graphicsLayer { scaleX = scale; scaleY = scale }.clip(shape).background(KeyBg)
            .border(if (ring) 3.dp else 1.dp, if (ring) Green else KeyRim, shape)
            .clickable(src, indication = null, enabled = live) {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                link.press(index)
            }
            .semantics { contentDescription = "key${index + 1} ${k?.label ?: ""}" },
        contentAlignment = Alignment.Center
    ) {
        when (k?.kind) {
            "app", "open" -> {
                LaunchedEffect(k.icon) { link.loadIcon(k.icon) }
                val img = link.icons[k.icon]
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    if (img != null) Image(img, null, Modifier.size(size * 0.58f))
                    else Spacer(Modifier.size(size * 0.58f))
                    // the app in front: a green bar under its icon, as on the Mac's deck
                    Box(Modifier.width(size * 0.58f).height(3.dp).clip(RoundedCornerShape(2.dp))
                        .background(if (k.active) Green else Color.Transparent))
                    Text(k.label, color = White, fontSize = with(d) { (size * 0.12f).toSp() }, maxLines = 1,
                        overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 3.dp))
                }
            }
            "scene" -> Text(k.label, color = if (k.active) Green else White, fontWeight = FontWeight.Black,
                fontSize = with(d) { (size * 0.46f).toSp() })
            "fkey" -> Text(k.label, color = White, fontWeight = FontWeight.Black,
                fontSize = with(d) { (size * 0.5f).toSp() })
            "next" -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("NEXT", color = White, fontWeight = FontWeight.Bold, fontSize = with(d) { (size * 0.2f).toSp() })
                Text("▶", color = Green, fontSize = with(d) { (size * 0.2f).toSp() })
                Text(k.label, color = Grey, fontSize = with(d) { (size * 0.13f).toSp() })
            }
            else -> {}
        }
    }
}

@Composable
private fun Tabs(current: String, pick: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for ((id, name) in PROFILES) {
            val sel = id == current
            Column(
                Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).background(if (sel) Body else Color.Transparent)
                    .clickable { pick(id) }.padding(vertical = 14.dp)
                    .semantics { contentDescription = "tab $name" },
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(name, color = if (sel) White else Grey, fontSize = 15.sp, letterSpacing = 1.5.sp,
                    fontWeight = if (sel) FontWeight.Bold else FontWeight.Medium)
                Spacer(Modifier.height(6.dp))
                Box(Modifier.width(28.dp).height(3.dp).clip(RoundedCornerShape(2.dp))
                    .background(if (sel) Green else Color.Transparent))
            }
        }
    }
}

@Composable
private fun AddressDialog(now: String, save: (String) -> Unit, close: () -> Unit) {
    var text by remember { mutableStateOf(now) }
    AlertDialog(
        onDismissRequest = close,
        title = { Text("The Mac's address") },
        text = {
            Column {
                Text("Found by itself on the same Wi-Fi or over the cable. Only if it is not: the Mac's address, " +
                    "e.g. 192.168.1.20 (Stream Deck Remote (Mantra) shows it).", fontSize = 13.sp)
                Spacer(Modifier.height(10.dp))
                OutlinedTextField(text, { text = it }, singleLine = true)
            }
        },
        confirmButton = { TextButton({ save(text) }) { Text("SAVE") } },
        dismissButton = { TextButton(close) { Text("✕") } }
    )
}
