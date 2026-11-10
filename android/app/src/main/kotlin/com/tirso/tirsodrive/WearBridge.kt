package com.tirso.tirsodrive

import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Answers the watch app. The watch never talks to Telegram: it asks this phone app (over Google's Wear Data Layer),
 * which answers from the index TirsoDrive keeps (td_index.json) — so no extra Telegram session is created.
 */
class WearBridge : WearableListenerService() {
    companion object {
        @Volatile var onShare: (() -> Unit)? = null
    }

    override fun onMessageReceived(ev: MessageEvent) {
        if (ev.path != "/td/req") return
        val req = try { JSONObject(String(ev.data)) } catch (_: Exception) { return }
        val res = try { handle(req) } catch (e: Exception) { JSONObject().put("error", e.message ?: "error") }
        res.put("rid", req.optString("rid"))
        Wearable.getMessageClient(this).sendMessage(ev.sourceNodeId, "/td/res", res.toString().toByteArray())
    }

    private fun handle(req: JSONObject): JSONObject {
        val idx = TirsoDocs.readIndex(this) ?: return JSONObject().put("empty", true)
        return when (req.optString("op")) {
            "menu" -> JSONObject().put("groups", idx.optJSONArray("groups")).put("favorites", idx.optJSONArray("favorites"))
                .put("lang", idx.optString("lang", "en")).put("updated", idx.optLong("updated"))
            "files" -> {
                val chat = req.optLong("c")
                val keyKids = req.optString("kids")
                val out = JSONArray()
                val files = idx.optJSONArray("files") ?: JSONArray()
                val chats = if (keyKids.isNotEmpty()) kidChats(idx, keyKids) else setOf(chat)
                val all = ArrayList<JSONObject>()
                for (i in 0 until files.length()) { val f = files.getJSONObject(i); if (f.optLong("c") in chats) all.add(f) }
                all.sortByDescending { it.optLong("d") }
                val off = req.optInt("off", 0)
                for (f in all.drop(off).take(40)) out.put(f)
                JSONObject().put("files", out).put("total", all.size)
            }
            "search" -> {
                val q = req.optString("q").lowercase().trim()
                val words = q.split(Regex("\\s+")).filter { it.isNotEmpty() }
                val out = JSONArray()
                val files = idx.optJSONArray("files") ?: JSONArray()
                var n = 0
                for (i in 0 until files.length()) {
                    val f = files.getJSONObject(i)
                    val nm = f.optString("n").lowercase()
                    if (words.isNotEmpty() && words.all { nm.contains(it) }) { out.put(f); if (++n >= 40) break }
                }
                JSONObject().put("files", out)
            }
            "share" -> {
                val q = File(filesDir, "wear_share.json")
                val arr = try { JSONArray(q.readText()) } catch (_: Exception) { JSONArray() }
                arr.put(JSONObject().put("c", req.optLong("c")).put("i", req.optLong("i")).put("to", req.optLong("to")))
                q.writeText(arr.toString())
                val cb = onShare
                cb?.invoke()
                JSONObject().put("ok", true).put("live", cb != null)
            }
            else -> JSONObject().put("error", "unknown")
        }
    }

    private fun kidChats(idx: JSONObject, parent: String): Set<Long> {
        val out = HashSet<Long>()
        val g = idx.optJSONArray("groups") ?: return out
        for (i in 0 until g.length()) { val x = g.getJSONObject(i); if (x.optString("parent") == parent && x.optLong("chatId") != 0L) out.add(x.optLong("chatId")) }
        return out
    }
}
