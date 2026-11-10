package com.tirso.tirsodrive.wear

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.speech.RecognizerIntent
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Colors
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.text.DateFormat
import java.util.Date
import kotlin.math.abs

private val Accent = Color(0xFF3BA7F5)
private val Card = Color(0xFF14181F)
private val Muted = Color(0xFF8C97AD)

sealed class Screen {
    object Home : Screen()
    data class Kids(val parent: String, val title: String) : Screen()
    data class Files(val title: String, val chat: Long, val kids: String = "", val preset: List<WFile>? = null) : Screen()
    data class Detail(val file: WFile) : Screen()
    data class Share(val file: WFile) : Screen()
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PhoneLink.attach(this)
        setContent { WatchApp() }
    }

    override fun onDestroy() {
        PhoneLink.detach(this)
        super.onDestroy()
    }
}

@Composable
fun WatchApp() {
    // true black background, TirsoDrive blue accent
    MaterialTheme(colors = Colors(primary = Accent, background = Color.Black, surface = Card, onBackground = Color.White, onSurface = Color.White)) {
        val ctx = LocalContext.current
        val scope = rememberCoroutineScope()
        val stack = remember { mutableStateListOf<Screen>(Screen.Home) }
        var groups by remember { mutableStateOf<List<Group>>(emptyList()) }
        var favs by remember { mutableStateOf<List<Contact>>(emptyList()) }
        var es by remember { mutableStateOf(false) }
        var loading by remember { mutableStateOf(true) }
        var failed by remember { mutableStateOf(false) }
        var goingBack by remember { mutableStateOf(false) }
        val s = Strings(es)

        fun load() {
            loading = true; failed = false
            scope.launch {
                try {
                    val r = PhoneLink.request(ctx, "menu")
                    if (r.optBoolean("empty") || r.has("error")) failed = true
                    else {
                        groups = r.optJSONArray("groups").groups()
                        favs = r.optJSONArray("recent").contacts()
                        es = r.optString("lang") == "es"
                    }
                } catch (_: Exception) { failed = true }
                loading = false
            }
        }
        LaunchedEffect(Unit) { load() }

        fun push(x: Screen) { goingBack = false; stack.add(x) }
        fun pop() { if (stack.size > 1) { goingBack = true; stack.removeAt(stack.lastIndex) } }
        BackHandler(enabled = stack.size > 1) { pop() }

        val speech = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
            if (r.resultCode == Activity.RESULT_OK) {
                val q = r.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
                if (!q.isNullOrBlank()) scope.launch {
                    try {
                        val res = PhoneLink.request(ctx, "search") { put("q", q) }
                        push(Screen.Files("\"$q\"", 0, preset = res.optJSONArray("files").wfiles()))
                    } catch (_: Exception) { failed = true }
                }
            }
        }

        Scaffold(timeText = { TimeText() }, modifier = Modifier.background(Color.Black)) {
            Box(Modifier.fillMaxSize().background(Color.Black)) {
                when {
                    loading -> CircularProgressIndicator(Modifier.align(Alignment.Center), indicatorColor = Accent)
                    failed -> Column(Modifier.align(Alignment.Center).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(s.noPhone, textAlign = TextAlign.Center, fontSize = 14.sp)
                        Chip(onClick = { load() }, label = { Text(s.retry) }, modifier = Modifier.padding(top = 10.dp), colors = ChipDefaults.primaryChipColors(backgroundColor = Accent))
                    }
                    else -> AnimatedContent(
                        targetState = stack.last(),
                        transitionSpec = {
                            if (goingBack) (slideInHorizontally(tween(260)) { -it / 3 } + fadeIn(tween(260))) togetherWith (slideOutHorizontally(tween(260)) { it } + fadeOut(tween(200)))
                            else (slideInHorizontally(tween(260)) { it } + fadeIn(tween(260))) togetherWith (slideOutHorizontally(tween(260)) { -it / 3 } + fadeOut(tween(200)))
                        },
                        label = "screens",
                    ) { screen ->
                        when (screen) {
                            is Screen.Home -> HomePager(groups, s,
                                onSearch = { speech.launch(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)) },
                                onOpen = { g ->
                                    if (g.kids) push(Screen.Kids(g.key, g.title))
                                    else push(Screen.Files(g.title, g.chatId))
                                })
                            is Screen.Kids -> KidsList(screen, groups.filter { it.parent == screen.parent }) { g -> push(Screen.Files(g.title, g.chatId)) }
                            is Screen.Files -> FileList(screen, s) { push(Screen.Detail(it)) }
                            is Screen.Detail -> Detail(screen.file, s, true) { push(Screen.Share(screen.file)) }
                            is Screen.Share -> ShareList(screen.file, favs, s, onDone = { pop() })
                        }
                    }
                }
            }
        }
    }
}

private fun emojiFor(key: String) = when (key) {
    "videos" -> "🎬"; "photos" -> "📷"; "audio" -> "🎵"; "docs" -> "📄"; "compressed" -> "🗜️"
    "apks" -> "🎮"; "roms" -> "👾"; "games" -> "🎮"; "other" -> "📦"; else -> "📁"
}

@Composable
private fun logoRes(name: String?): Int? {
    if (name == null) return null
    val ctx = LocalContext.current
    val id = ctx.resources.getIdentifier("logo_$name", "drawable", ctx.packageName)
    return if (id == 0) null else id
}

@Composable
fun HomePager(groups: List<Group>, s: Strings, onSearch: () -> Unit, onOpen: (Group) -> Unit) {
    val top = groups.filter { it.parent == null }
    val pager = rememberPagerState { top.size + 1 }
    Box(Modifier.fillMaxSize()) {
        HorizontalPager(state = pager, modifier = Modifier.fillMaxSize()) { page ->
            val offset = abs((pager.currentPage - page) + pager.currentPageOffsetFraction)
            Column(
                Modifier.fillMaxSize().scale(1f - offset * 0.18f).alpha(1f - offset * 0.6f)
                    .clickable { if (page == 0) onSearch() else onOpen(top[page - 1]) },
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
            ) {
                if (page == 0) {
                    Text("🔍", fontSize = 40.sp)
                    Text(s.search, fontWeight = FontWeight.SemiBold, fontSize = 18.sp, modifier = Modifier.padding(top = 6.dp))
                    Text(s.searchHint, color = Muted, fontSize = 12.sp)
                } else {
                    val g = top[page - 1]
                    Text(emojiFor(g.key), fontSize = 40.sp)
                    Text(g.title, fontWeight = FontWeight.SemiBold, fontSize = 18.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 6.dp, start = 16.dp, end = 16.dp))
                    Text(if (g.kids) "›" else "${g.count} ${s.files}", color = Muted, fontSize = 12.sp)
                }
            }
        }
        // page dots
        Row(Modifier.align(Alignment.BottomCenter).padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            val total = top.size + 1
            val from = (pager.currentPage - 3).coerceAtLeast(0)
            val to = (from + 6).coerceAtMost(total - 1)
            for (i in from..to) {
                val on = i == pager.currentPage
                Box(Modifier.size(if (on) 7.dp else 5.dp).clip(CircleShape).background(if (on) Accent else Color(0xFF3A4252)))
            }
        }
    }
}

@Composable
fun KidsList(screen: Screen.Kids, kids: List<Group>, onOpen: (Group) -> Unit) {
    ScalingLazyColumn(Modifier.fillMaxSize()) {
        item { Text(screen.title, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, modifier = Modifier.padding(bottom = 4.dp)) }
        items(kids) { g ->
            val logo = logoRes(g.logo)
            Chip(
                onClick = { onOpen(g) },
                label = { Text(g.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                secondaryLabel = { Text("${g.count}", color = Muted) },
                icon = if (logo != null) ({ Image(painterResource(logo), null, Modifier.size(26.dp), contentScale = ContentScale.Fit) }) else null,
                colors = ChipDefaults.chipColors(backgroundColor = Card),
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

@Composable
fun FileList(screen: Screen.Files, s: Strings, onOpen: (WFile) -> Unit) {
    val ctx = LocalContext.current
    var files by remember { mutableStateOf(screen.preset ?: emptyList()) }
    var total by remember { mutableStateOf(screen.preset?.size ?: 0) }
    var busy by remember { mutableStateOf(screen.preset == null) }
    val scope = rememberCoroutineScope()

    fun loadMore() {
        busy = true
        scope.launch {
            try {
                val r = PhoneLink.request(ctx, "files") { put("c", screen.chat); put("kids", screen.kids); put("off", files.size) }
                files = files + r.optJSONArray("files").wfiles()
                total = r.optInt("total")
            } catch (_: Exception) { }
            busy = false
        }
    }
    LaunchedEffect(Unit) { if (screen.preset == null) loadMore() }

    ScalingLazyColumn(Modifier.fillMaxSize()) {
        item { Text(screen.title, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(bottom = 4.dp)) }
        if (files.isEmpty() && !busy) item { Text(s.empty, color = Muted) }
        items(files) { f ->
            Chip(
                onClick = { onOpen(f) },
                label = { Text(f.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                secondaryLabel = { Text(sizeText(f.size), color = Muted) },
                colors = ChipDefaults.chipColors(backgroundColor = Card),
                modifier = Modifier.fillMaxSize(),
            )
        }
        if (busy) item { CircularProgressIndicator(Modifier.size(24.dp), indicatorColor = Accent) }
        else if (screen.preset == null && files.size < total) item { Chip(onClick = { loadMore() }, label = { Text(s.more) }, colors = ChipDefaults.secondaryChipColors()) }
    }
}

@Composable
fun Detail(f: WFile, s: Strings, canShare: Boolean, onShare: () -> Unit) {
    ScalingLazyColumn(Modifier.fillMaxSize()) {
        item { Text(f.name, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 12.dp)) }
        item { Text("${sizeText(f.size)} · ${DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(f.date * 1000))}", color = Muted, fontSize = 12.sp) }
        item {
            Chip(onClick = onShare, enabled = canShare, label = { Text(s.share) },
                secondaryLabel = if (!canShare) ({ Text(s.noFavs, fontSize = 10.sp) }) else null,
                colors = ChipDefaults.primaryChipColors(backgroundColor = Accent), modifier = Modifier.padding(top = 8.dp))
        }
    }
}

@Composable
fun ShareList(f: WFile, recent: List<Contact>, s: Strings, onDone: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf<String?>(null) }
    var searching by remember { mutableStateOf(false) }
    var found by remember { mutableStateOf<List<Contact>>(emptyList()) }
    var query by remember { mutableStateOf("") }

    fun lookup(q: String) {
        query = q
        scope.launch {
            found = try { PhoneLink.request(ctx, "csearch") { put("q", q) }.optJSONArray("contacts").contacts() } catch (_: Exception) { emptyList() }
        }
    }
    val speech = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode == Activity.RESULT_OK) {
            val q = r.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            if (!q.isNullOrBlank()) lookup(q)
        }
    }
    fun send(c: Contact) {
        scope.launch {
            status = try {
                val r = PhoneLink.request(ctx, "share") { put("c", f.chat); put("i", f.id); put("to", c.id) }
                if (r.optBoolean("live")) "${s.sent} ✓" else s.finishOnPhone
            } catch (_: Exception) { s.noPhone }
        }
    }
    @Composable
    fun row(c: Contact) = Chip(
        onClick = { send(c) },
        label = { Text(c.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        colors = ChipDefaults.chipColors(backgroundColor = Card),
        modifier = Modifier.fillMaxSize(),
    )
    ScalingLazyColumn(Modifier.fillMaxSize()) {
        item { Text(if (searching) s.allContacts else s.share, fontWeight = FontWeight.SemiBold, fontSize = 16.sp) }
        if (status != null) item { Text(status!!, color = Accent, textAlign = TextAlign.Center, fontSize = 13.sp, modifier = Modifier.padding(8.dp)) }
        if (!searching) {
            items(recent) { c -> row(c) }
            item {
                Chip(onClick = { searching = true; lookup("") }, label = { Text(s.allContacts) },
                    colors = ChipDefaults.primaryChipColors(backgroundColor = Accent), modifier = Modifier.fillMaxSize())
            }
        } else {
            item {
                Chip(
                    onClick = { speech.launch(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)) },
                    label = { Text(s.searchContacts) },
                    secondaryLabel = { Text(if (query.isEmpty()) s.searchHint else "\"$query\"", fontSize = 11.sp) },
                    colors = ChipDefaults.primaryChipColors(backgroundColor = Accent), modifier = Modifier.fillMaxSize())
            }
            items(found) { c -> row(c) }
        }
    }
}
