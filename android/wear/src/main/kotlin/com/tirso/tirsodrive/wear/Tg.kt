package com.tirso.tirsodrive.wear

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

sealed class Auth {
    object Starting : Auth()
    data class Qr(val link: String?) : Auth()
    data class Password(val hint: String, val wrong: Boolean = false) : Auth()
    object Loading : Auth()
    object Ready : Auth()
}

data class Profile(val name: String, val username: String, val phone: String, val photo: String?)

class Page(val files: List<WFile>, val next: Long, val done: Boolean)

/** The watch's own Telegram session (logged in by QR) and everything it reads from it. */
object Tg {
    var auth by mutableStateOf<Auth>(Auth.Starting)
    var groups by mutableStateOf<List<Group>>(emptyList())
    val es = Locale.getDefault().language == "es"
    private val scope = CoroutineScope(Dispatchers.IO)
    private val chats = ConcurrentHashMap<Long, JSONObject>()
    private var recentIds: List<Long> = emptyList()
    private var contactsCache: List<Contact>? = null
    private var myId = 0L
    private lateinit var app: Context
    private var started = false

    fun init(ctx: Context) {
        if (started) return
        started = true
        app = ctx.applicationContext
        Td.onUpdate = ::onUpdate
        Td.start()
    }

    private fun onUpdate(u: JSONObject) {
        when (u.optString("@type")) {
            "updateAuthorizationState" -> handleAuth(u.getJSONObject("authorization_state"))
            "updateNewChat" -> u.getJSONObject("chat").let { chats[it.getLong("id")] = it }
            "updateChatTitle" -> chats[u.getLong("chat_id")]?.put("title", u.getString("title"))
        }
    }

    private fun handleAuth(st: JSONObject) {
        scope.launch {
            try {
                when (st.optString("@type")) {
                    "authorizationStateWaitTdlibParameters" -> Td.call("setTdlibParameters") {
                        put("use_test_dc", false)
                        put("database_directory", app.filesDir.path + "/td_db")
                        put("files_directory", app.cacheDir.path + "/td_files")
                        put("database_encryption_key", "")
                        put("use_file_database", false)
                        put("use_chat_info_database", true)
                        put("use_message_database", false)
                        put("use_secret_chats", false)
                        put("api_id", 38798734)
                        put("api_hash", "dee69532c862a3a3975eda119ba52223")
                        put("system_language_code", Locale.getDefault().language)
                        put("device_model", "TirsoDrive (Watch)")
                        put("system_version", "Wear OS")
                        put("application_version", "0.13.1")
                    }
                    "authorizationStateWaitPhoneNumber" -> {
                        auth = Auth.Qr(null)
                        Td.call("requestQrCodeAuthentication") { put("other_user_ids", JSONArray()) }
                    }
                    "authorizationStateWaitOtherDeviceConfirmation" -> auth = Auth.Qr(st.optString("link"))
                    "authorizationStateWaitPassword" -> auth = Auth.Password(st.optString("password_hint"))
                    "authorizationStateReady" -> { auth = Auth.Loading; try { loadAll() } catch (_: Exception) {}; auth = Auth.Ready }
                    "authorizationStateLoggingOut", "authorizationStateClosed" -> { groups = emptyList(); chats.clear(); contactsCache = null; auth = Auth.Qr(null) }
                    else -> {}
                }
            } catch (_: Exception) {
                if (auth is Auth.Loading) auth = Auth.Ready
            }
        }
    }

    suspend fun password(p: String) {
        try {
            Td.call("checkAuthenticationPassword") { put("password", p) }
        } catch (_: TdError) {
            val cur = auth
            auth = Auth.Password((cur as? Auth.Password)?.hint ?: "", wrong = true)
        }
    }

    fun signOut() { scope.launch { try { Td.call("logOut") } catch (_: Exception) {} } }

    // ------------------------------------------------------------ library

    var refreshing by mutableStateOf(false)
    var me by mutableStateOf<Profile?>(null)
    var note by mutableStateOf("")

    private suspend fun loadList(list: String) {
        repeat(12) {
            try {
                Td.call("loadChats") { put("chat_list", JSONObject().put("@type", list)); put("limit", 100) }
            } catch (e: TdError) {
                if (e.code == 404) return
            }
        }
    }

    private suspend fun idsOf(list: String): List<Long> = try {
        val a = Td.call("getChats") { put("chat_list", JSONObject().put("@type", list)); put("limit", 500) }.optJSONArray("chat_ids")
        List(a?.length() ?: 0) { a!!.getLong(it) }
    } catch (_: Exception) { emptyList() }

    private suspend fun chatOf(id: Long): JSONObject? = chats[id] ?: try {
        Td.call("getChat") { put("chat_id", id) }.also { chats[id] = it }
    } catch (_: Exception) { null }

    fun refresh() {
        if (refreshing) return
        refreshing = true
        scope.launch { try { contactsCache = null; loadAll() } catch (_: Exception) {} ; refreshing = false }
    }

    private suspend fun loadAll() {
        try {
            val u = Td.call("getMe")
            myId = u.optLong("id")
            val name = listOf(u.optString("first_name"), u.optString("last_name")).filter { it.isNotEmpty() }.joinToString(" ")
            val un = u.optJSONObject("usernames")?.optJSONArray("active_usernames")?.optString(0) ?: ""
            me = Profile(name, un, u.optString("phone_number"), me?.photo)
            loadPhoto(u.optJSONObject("profile_photo")?.optJSONObject("small")?.optInt("id") ?: 0)
        } catch (_: Exception) {}
        loadList("chatListMain")
        loadList("chatListArchive")
        val main = idsOf("chatListMain")
        recentIds = main
        val all = LinkedHashSet<Long>(main)
        all.addAll(idsOf("chatListArchive"))
        // fallback: find the channels by name if the chat lists didn't include them
        try {
            val r = Td.call("searchChats") { put("query", "TD -"); put("limit", 100) }.optJSONArray("chat_ids")
            for (i in 0 until (r?.length() ?: 0)) all.add(r!!.getLong(i))
        } catch (_: Exception) {}
        val found = ArrayList<Pair<Cat, Long>>()
        for (id in all) {
            val c = chatOf(id) ?: continue
            if (!isChannel(c)) continue
            val cat = Cats.byTitle(c.optString("title")) ?: continue
            found.add(cat to id)
        }
        note = "${all.size} chats · ${found.size} libraries"
        fun rank(c: Cat) = when (c.kind) { 1 -> 300; 2 -> 400; else -> Cats.all.filter { it.kind == 0 }.indexOf(c) * 10 }
        found.sortBy { rank(it.first) }
        val out = ArrayList<Group>()
        for ((cat, id) in found) {
            out.add(Group(cat.key, if (es) cat.es else cat.en, id, if (cat.kind == 1) "apks" else if (cat.kind == 2) "roms" else null, cat.logo, -1, false))
        }
        fun at(parent: String) = out.indexOfFirst { it.parent == parent }
        if (at("roms") >= 0) out.add(at("roms"), Group("roms", "ROMs", 0, null, null, -1, true))
        if (at("apks") >= 0) out.add(at("apks"), Group("apks", if (es) "Juegos (APKs)" else "Games (APKs)", 0, null, null, -1, true))
        groups = out
    }

    private suspend fun loadPhoto(fileId: Int) {
        if (fileId == 0) return
        try {
            val f = Td.call("downloadFile") { put("file_id", fileId); put("priority", 1); put("offset", 0); put("limit", 0); put("synchronous", true) }
            val path = f.optJSONObject("local")?.optString("path") ?: ""
            if (path.isNotEmpty()) me = me?.copy(photo = path)
        } catch (_: Exception) {}
    }

    private fun isChannel(c: JSONObject): Boolean {
        val t = c.optJSONObject("type") ?: return false
        return t.optString("@type") == "chatTypeSupergroup" && t.optBoolean("is_channel")
    }

    private fun parse(m: JSONObject): WFile? {
        val c = m.optJSONObject("content") ?: return null
        val id = m.optLong("id")
        var name = ""
        var size = 0L
        when (c.optString("@type")) {
            "messageDocument" -> c.getJSONObject("document").let { name = it.optString("file_name"); size = it.getJSONObject("document").optLong("size") }
            "messageVideo" -> c.getJSONObject("video").let { name = it.optString("file_name").ifEmpty { "video_$id.mp4" }; size = it.getJSONObject("video").optLong("size") }
            "messageAudio" -> c.getJSONObject("audio").let { name = it.optString("file_name"); size = it.getJSONObject("audio").optLong("size") }
            "messageAnimation" -> c.getJSONObject("animation").let { name = it.optString("file_name"); size = it.getJSONObject("animation").optLong("size") }
            "messagePhoto" -> {
                val sizes = c.getJSONObject("photo").optJSONArray("sizes")
                name = "photo_$id.jpg"
                if (sizes != null && sizes.length() > 0) size = sizes.getJSONObject(sizes.length() - 1).getJSONObject("photo").optLong("size")
            }
            else -> return null
        }
        val cap = c.optJSONObject("caption")?.optString("text") ?: ""
        if (cap.split(Regex("\\s+")).any { it.startsWith("trashed=") }) return null
        Regex("(?:^|\\s)name=(\\S+)").find(cap)?.let { try { name = java.net.URLDecoder.decode(it.groupValues[1].replace("+", "%2B"), "UTF-8") } catch (_: Exception) {} }
        if (name.isEmpty()) name = "file_$id"
        return WFile(id, m.optLong("chat_id"), name, size, m.optLong("date"))
    }

    suspend fun page(chat: Long, from: Long): Page {
        val out = ArrayList<WFile>()
        var next = from
        var rounds = 0
        var empty = 0
        while (out.size < 25 && rounds++ < 6 && empty < 2) {
            val msgs = Td.call("getChatHistory") {
                put("chat_id", chat); put("from_message_id", next); put("offset", 0); put("limit", 40); put("only_local", false)
            }.optJSONArray("messages")
            if (msgs == null || msgs.length() == 0) { empty++; if (next == 0L) break; continue }
            for (i in 0 until msgs.length()) parse(msgs.getJSONObject(i))?.let { out.add(it) }
            next = msgs.getJSONObject(msgs.length() - 1).getLong("id")
        }
        return Page(out, next, empty >= 2 || out.isEmpty())
    }

    suspend fun search(q: String): List<WFile> = coroutineScope {
        val chatsToSearch = groups.filter { it.chatId != 0L }
        chatsToSearch.map { g ->
            async {
                try {
                    val msgs = Td.call("searchChatMessages") {
                        put("chat_id", g.chatId); put("query", q); put("from_message_id", 0); put("offset", 0); put("limit", 30)
                    }.optJSONArray("messages")
                    List(msgs?.length() ?: 0) { parse(msgs!!.getJSONObject(it)) }.filterNotNull()
                } catch (_: Exception) { emptyList<WFile>() }
            }
        }.awaitAll().flatten().sortedByDescending { it.date }.take(60)
    }

    // ------------------------------------------------------------ contacts

    private fun shareable(c: JSONObject): Boolean {
        val t = c.optJSONObject("type") ?: return false
        return when (t.optString("@type")) {
            "chatTypePrivate", "chatTypeBasicGroup" -> true
            "chatTypeSupergroup" -> !t.optBoolean("is_channel")
            else -> false
        }
    }

    private fun titleOf(id: Long, c: JSONObject) = if (id == myId) (if (es) "Mensajes guardados" else "Saved Messages") else c.optString("title")

    /** Recent chats, newest first — the same list the phone app offers when sharing. */
    fun recent(): List<Contact> {
        val out = ArrayList<Contact>()
        for (id in recentIds) {
            val c = chats[id] ?: continue
            if (!shareable(c)) continue
            out.add(Contact(id, titleOf(id, c)))
            if (out.size >= 25) break
        }
        return out
    }

    /** Every chat plus every Telegram contact, for searching. */
    suspend fun allContacts(): List<Contact> {
        contactsCache?.let { return it }
        val list = ArrayList<Contact>()
        val seen = HashSet<Long>()
        for (id in recentIds) {
            val c = chats[id] ?: continue
            if (shareable(c) && seen.add(id)) list.add(Contact(id, titleOf(id, c)))
        }
        try {
            val ids = Td.call("getContacts").optJSONArray("user_ids")
            val users = coroutineScope {
                List(minOf(ids?.length() ?: 0, 400)) { i -> async { try { Td.call("getUser") { put("user_id", ids!!.getLong(i)) } } catch (_: Exception) { null } } }.awaitAll()
            }
            for (u in users) {
                if (u == null) continue
                val id = u.optLong("id")
                if (!seen.add(id)) continue
                val name = listOf(u.optString("first_name"), u.optString("last_name")).filter { it.isNotEmpty() }.joinToString(" ")
                list.add(Contact(id, name.ifEmpty { "?" }))
            }
        } catch (_: Exception) {}
        val sorted = list.sortedBy { it.name.lowercase() }
        contactsCache = sorted
        return sorted
    }

    suspend fun findContacts(q: String): List<Contact> {
        val words = q.lowercase().trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        return allContacts().filter { c -> val n = c.name.lowercase(); words.all { n.contains(it) } }.take(40)
    }

    /** Sends a clean copy of the file (no "forwarded from") — nothing is uploaded again. */
    suspend fun send(f: WFile, to: Long) {
        if (to > 0) try { Td.call("createPrivateChat") { put("user_id", to); put("force", false) } } catch (_: Exception) {}
        Td.call("forwardMessages") {
            put("chat_id", to); put("from_chat_id", f.chat)
            put("message_ids", JSONArray().put(f.id))
            put("send_copy", true); put("remove_caption", true)
        }
    }
}
