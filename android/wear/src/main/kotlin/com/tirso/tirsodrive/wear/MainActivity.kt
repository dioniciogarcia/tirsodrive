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
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.PagerDefaults
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.layout.Row
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.unit.Velocity
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date
import kotlin.math.abs

private val Accent = Color(0xFF3BA7F5)
private val Card = Color(0xFF14181F)
private val Muted = Color(0xFF8C97AD)

sealed class Screen {
    object Home : Screen()
    data class Kids(val parent: String, val title: String) : Screen()
    data class Files(val title: String, val chat: Long, val preset: List<WFile>? = null) : Screen()
    data class Detail(val file: WFile) : Screen()
    data class Share(val file: WFile) : Screen()
    object Profile : Screen()
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Tg.init(this)
        setContent { WatchApp() }
    }
}

private fun voiceIntent() = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)

@Composable
fun WatchApp() {
    // true black background, TirsoDrive blue accent
    MaterialTheme(colors = Colors(primary = Accent, background = Color.Black, surface = Card, onBackground = Color.White, onSurface = Color.White)) {
        val s = Strings(Tg.es)
        Scaffold(timeText = { TimeText() }, modifier = Modifier.background(Color.Black)) {
            Box(Modifier.fillMaxSize().background(Color.Black)) {
                when (val a = Tg.auth) {
                    is Auth.Starting, is Auth.Loading -> CircularProgressIndicator(Modifier.align(Alignment.Center), indicatorColor = Accent)
                    is Auth.Qr -> QrLogin(a.link, s)
                    is Auth.Password -> PasswordLogin(a, s)
                    is Auth.Ready -> Library(s)
                }
            }
        }
    }
}

@Composable
fun QrLogin(link: String?, s: Strings) {
    Column(Modifier.fillMaxSize().padding(top = 22.dp, bottom = 10.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        if (link == null) CircularProgressIndicator(Modifier.size(28.dp), indicatorColor = Accent)
        else {
            val m = remember(link) { QRCodeWriter().encode(link, BarcodeFormat.QR_CODE, 0, 0, mapOf(EncodeHintType.MARGIN to 0)) }
            Box(Modifier.size(124.dp).clip(RoundedCornerShape(8.dp)).background(Color.White).padding(6.dp)) {
                Canvas(Modifier.fillMaxSize()) {
                    val cell = size.width / m.width
                    for (x in 0 until m.width) for (y in 0 until m.height) {
                        if (m.get(x, y)) drawRect(Color.Black, Offset(x * cell, y * cell), Size(cell + 0.6f, cell + 0.6f))
                    }
                }
            }
        }
        Text(s.signIn, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
        Text(s.signInHow, color = Muted, fontSize = 9.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 26.dp))
    }
}

@Composable
fun PasswordLogin(a: Auth.Password, s: Strings) {
    val scope = rememberCoroutineScope()
    var pw by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(horizontal = 22.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Text(s.password, fontSize = 12.sp, textAlign = TextAlign.Center)
        if (a.hint.isNotEmpty()) Text(a.hint, color = Muted, fontSize = 10.sp)
        if (a.wrong) Text(s.wrongPassword, color = Color(0xFFE86F6F), fontSize = 11.sp)
        Box(Modifier.padding(vertical = 8.dp).clip(RoundedCornerShape(10.dp)).background(Card).padding(10.dp)) {
            BasicTextField(pw, { pw = it }, singleLine = true, visualTransformation = PasswordVisualTransformation(),
                textStyle = TextStyle(color = Color.White, fontSize = 16.sp), cursorBrush = SolidColor(Accent), modifier = Modifier.fillMaxSize())
        }
        Chip(onClick = { scope.launch { Tg.password(pw) } }, label = { Text(s.ok) }, colors = ChipDefaults.primaryChipColors(backgroundColor = Accent))
    }
}

@Composable
fun Library(s: Strings) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val stack = remember { mutableStateListOf<Screen>(Screen.Home) }
    var goingBack by remember { mutableStateOf(false) }
    fun push(x: Screen) { goingBack = false; stack.add(x) }
    fun pop() { if (stack.size > 1) { goingBack = true; stack.removeAt(stack.lastIndex) } }
    BackHandler(enabled = stack.size > 1) { pop() }
    var searching by remember { mutableStateOf(false) }

    val speech = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode == Activity.RESULT_OK) {
            val q = r.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            if (!q.isNullOrBlank()) scope.launch {
                searching = true
                val res = try { Tg.search(q) } catch (_: Exception) { emptyList() }
                searching = false
                push(Screen.Files("\"$q\"", 0, preset = res))
            }
        }
    }
    val onSearch = { speech.launch(voiceIntent()) }

    if (searching) { CircularProgressIndicator(Modifier.fillMaxSize().padding(60.dp), indicatorColor = Accent); return }
    AnimatedContent(
        targetState = stack.last(),
        transitionSpec = {
            if (goingBack) (slideInHorizontally(tween(260)) { -it / 3 } + fadeIn(tween(260))) togetherWith (slideOutHorizontally(tween(260)) { it } + fadeOut(tween(200)))
            else (slideInHorizontally(tween(260)) { it } + fadeIn(tween(260))) togetherWith (slideOutHorizontally(tween(260)) { -it / 3 } + fadeOut(tween(200)))
        },
        label = "screens",
    ) { screen ->
        when (screen) {
            is Screen.Home -> HomePager(Tg.groups, s, onSearch,
                onOpen = { g -> if (g.kids) push(Screen.Kids(g.key, g.title)) else push(Screen.Files(g.title, g.chatId)) },
                onProfile = { push(Screen.Profile) })
            is Screen.Profile -> ProfileScreen(s)
            is Screen.Kids -> KidsList(screen, Tg.groups.filter { it.parent == screen.parent }) { g -> push(Screen.Files(g.title, g.chatId)) }
            is Screen.Files -> FileList(screen, s, onSearch) { push(Screen.Detail(it)) }
            is Screen.Detail -> Detail(screen.file, s) { push(Screen.Share(screen.file)) }
            is Screen.Share -> ShareList(screen.file, s)
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

/** Categories stacked vertically: swipe or turn the crown/bezel and each one snaps into place with a small springy "magnet". */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun HomePager(groups: List<Group>, s: Strings, onSearch: () -> Unit, onOpen: (Group) -> Unit, onProfile: () -> Unit) {
    val top = groups.filter { it.parent == null }
    val total = top.size + 2 // search, profile, categories
    val pager = rememberPagerState { total }
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }
    val snap = spring<Float>(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMediumLow)
    val fling = PagerDefaults.flingBehavior(state = pager, snapAnimationSpec = snap)
    var lastTick = remember { 0L }
    var pull by remember { mutableStateOf(0f) }
    val pullConnection = remember {
        object : NestedScrollConnection {
            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                if (pager.currentPage == 0 && available.y > 0f) {
                    pull += available.y
                    if (pull > 140f) { pull = 0f; Tg.refresh() }
                } else if (available.y < 0f) pull = 0f
                return Offset.Zero
            }
            override suspend fun onPostFling(consumed: Velocity, available: Velocity): Velocity { pull = 0f; return Velocity.Zero }
        }
    }
    LaunchedEffect(Unit) { try { focus.requestFocus() } catch (_: Exception) {} }
    Box(Modifier.fillMaxSize()) {
        VerticalPager(
            state = pager, flingBehavior = fling,
            modifier = Modifier.fillMaxSize()
                .nestedScroll(pullConnection)
                .onRotaryScrollEvent { ev ->
                    val now = System.currentTimeMillis()
                    if (now - lastTick > 140) {
                        lastTick = now
                        val to = (pager.currentPage + if (ev.verticalScrollPixels > 0) 1 else -1).coerceIn(0, total - 1)
                        scope.launch { pager.animateScrollToPage(to, animationSpec = snap) }
                    }
                    true
                }
                .focusRequester(focus).focusable(),
        ) { page ->
            val offset = abs((pager.currentPage - page) + pager.currentPageOffsetFraction)
            val g = top.getOrNull(page - 2)
            Column(
                Modifier.fillMaxSize().scale(1f - offset * 0.2f).alpha(1f - offset * 0.65f)
                    .combinedClickable(
                        onClick = { when { page == 0 -> onSearch(); g != null -> onOpen(g); else -> onProfile() } },
                        onLongClick = onSearch,
                    ),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
            ) {
                when {
                    page == 0 -> {
                        Text("🔍", fontSize = 40.sp)
                        Text(s.search, fontWeight = FontWeight.SemiBold, fontSize = 18.sp, modifier = Modifier.padding(top = 6.dp))
                        Text(s.searchHint, color = Muted, fontSize = 12.sp)
                    }
                    g != null -> {
                        Text(emojiFor(g.key), fontSize = 40.sp)
                        Text(g.title, fontWeight = FontWeight.SemiBold, fontSize = 18.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 6.dp, start = 16.dp, end = 16.dp))
                        if (g.kids) Text("›", color = Muted, fontSize = 14.sp)
                    }
                    else -> {
                        Text("👤", fontSize = 40.sp)
                        Text(s.profile, fontWeight = FontWeight.SemiBold, fontSize = 18.sp, modifier = Modifier.padding(top = 6.dp))
                        Text(Tg.me?.name ?: "", color = Muted, fontSize = 12.sp, maxLines = 1)
                        if (top.isEmpty()) Text(s.pullHint, color = Muted, fontSize = 10.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp, start = 26.dp, end = 26.dp))
                    }
                }
            }
        }
        if (Tg.refreshing) CircularProgressIndicator(Modifier.align(Alignment.TopCenter).padding(top = 18.dp).size(18.dp), indicatorColor = Accent, strokeWidth = 2.dp)
        // position dots, on the right edge because the pages move up and down
        Column(Modifier.align(Alignment.CenterEnd).padding(end = 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
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
                icon = if (logo != null) ({ Image(painterResource(logo), null, Modifier.size(26.dp), contentScale = ContentScale.Fit) }) else null,
                colors = ChipDefaults.chipColors(backgroundColor = Card),
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

@Composable
fun FileList(screen: Screen.Files, s: Strings, onSearch: () -> Unit, onOpen: (WFile) -> Unit) {
    var files by remember { mutableStateOf(screen.preset ?: emptyList()) }
    var next by remember { mutableStateOf(0L) }
    var done by remember { mutableStateOf(screen.preset != null) }
    var busy by remember { mutableStateOf(screen.preset == null) }
    val scope = rememberCoroutineScope()

    fun loadMore() {
        busy = true
        scope.launch {
            try {
                val p = Tg.page(screen.chat, next)
                files = files + p.files
                next = p.next
                done = p.done
            } catch (_: Exception) { done = true }
            busy = false
        }
    }
    LaunchedEffect(Unit) { if (screen.preset == null) loadMore() }

    ScalingLazyColumn(Modifier.fillMaxSize()) {
        item { Text(screen.title, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(bottom = 4.dp)) }
        item { Chip(onClick = onSearch, label = { Text("🔍 ${s.search}") }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxSize()) }
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
        else if (screen.preset == null && !done) item { Chip(onClick = { loadMore() }, label = { Text(s.more) }, colors = ChipDefaults.secondaryChipColors()) }
    }
}

@Composable
fun Detail(f: WFile, s: Strings, onShare: () -> Unit) {
    ScalingLazyColumn(Modifier.fillMaxSize()) {
        item { Text(f.name, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 12.dp)) }
        item { Text("${sizeText(f.size)} · ${DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(f.date * 1000))}", color = Muted, fontSize = 12.sp) }
        item {
            Chip(onClick = onShare, label = { Text(s.share) },
                colors = ChipDefaults.primaryChipColors(backgroundColor = Accent), modifier = Modifier.padding(top = 8.dp))
        }
    }
}

@Composable
fun ShareList(f: WFile, s: Strings) {
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf<String?>(null) }
    var searching by remember { mutableStateOf(false) }
    var found by remember { mutableStateOf<List<Contact>>(emptyList()) }
    var query by remember { mutableStateOf("") }
    val recent = remember { Tg.recent() }

    fun lookup(q: String) {
        query = q
        scope.launch { found = try { Tg.findContacts(q) } catch (_: Exception) { emptyList() } }
    }
    val speech = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode == Activity.RESULT_OK) {
            val q = r.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            if (!q.isNullOrBlank()) lookup(q)
        }
    }
    fun send(c: Contact) {
        scope.launch {
            status = try { Tg.send(f, c.id); "${s.sent} ✓ ${c.name}" } catch (_: Exception) { s.noPhone }
        }
    }
    ScalingLazyColumn(Modifier.fillMaxSize()) {
        item { Text(if (searching) s.allContacts else s.share, fontWeight = FontWeight.SemiBold, fontSize = 16.sp) }
        if (status != null) item { Text(status!!, color = Accent, textAlign = TextAlign.Center, fontSize = 13.sp, modifier = Modifier.padding(8.dp)) }
        if (!searching) {
            items(recent) { c -> ContactChip(c) { send(c) } }
            item {
                Chip(onClick = { searching = true; lookup("") }, label = { Text(s.allContacts) },
                    colors = ChipDefaults.primaryChipColors(backgroundColor = Accent), modifier = Modifier.fillMaxSize())
            }
        } else {
            item {
                Chip(
                    onClick = { speech.launch(voiceIntent()) },
                    label = { Text(s.searchContacts) },
                    secondaryLabel = { Text(if (query.isEmpty()) s.searchHint else "\"$query\"", fontSize = 11.sp) },
                    colors = ChipDefaults.primaryChipColors(backgroundColor = Accent), modifier = Modifier.fillMaxSize())
            }
            items(found) { c -> ContactChip(c) { send(c) } }
        }
    }
}

@Composable
private fun ContactChip(c: Contact, onClick: () -> Unit) = Chip(
    onClick = onClick,
    label = { Text(c.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
    colors = ChipDefaults.chipColors(backgroundColor = Card),
    modifier = Modifier.fillMaxSize(),
)

@Composable
fun ProfileScreen(s: Strings) {
    val me = Tg.me
    val bmp = remember(me?.photo) { me?.photo?.let { try { BitmapFactory.decodeFile(it)?.asImageBitmap() } catch (_: Exception) { null } } }
    ScalingLazyColumn(Modifier.fillMaxSize()) {
        item {
            Box(Modifier.size(64.dp).clip(CircleShape).background(Card), contentAlignment = Alignment.Center) {
                if (bmp != null) Image(bmp, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                else Text((me?.name?.firstOrNull() ?: '?').toString(), fontSize = 28.sp, color = Accent)
            }
        }
        item { Text(me?.name ?: "", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp)) }
        if (!me?.username.isNullOrEmpty()) item { Text("@${me!!.username}", color = Accent, fontSize = 13.sp) }
        if (!me?.phone.isNullOrEmpty()) item { Text("+${me!!.phone}", color = Muted, fontSize = 12.sp) }
        item { Text("${Tg.groups.count { it.chatId != 0L }} ${if (Tg.es) "bibliotecas" else "libraries"}", color = Muted, fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp)) }
        if (Tg.note.isNotEmpty()) item { Text(Tg.note, color = Muted, fontSize = 9.sp) }
        item { Chip(onClick = { Tg.refresh() }, label = { Text(s.refresh) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.padding(top = 8.dp).fillMaxSize()) }
        item { Chip(onClick = { Tg.signOut() }, label = { Text(s.signOut) }, colors = ChipDefaults.chipColors(backgroundColor = Card), modifier = Modifier.fillMaxSize()) }
    }
}
