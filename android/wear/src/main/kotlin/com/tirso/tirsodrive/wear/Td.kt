package com.tirso.tirsodrive.wear

import com.sun.jna.Library
import com.sun.jna.Native
import kotlinx.coroutines.CompletableDeferred
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlin.concurrent.thread

interface TdLib : Library {
    fun td_create_client_id(): Int
    fun td_send(clientId: Int, request: String)
    fun td_receive(timeout: Double): String?
    fun td_execute(request: String): String?
}

class TdError(val code: Int, message: String) : Exception(message)

/** Telegram's own library (TDLib), the same one the phone and PC apps use, talked to as JSON through JNA. */
object Td {
    private var lib: TdLib? = null
    private var client = 0
    private val extra = AtomicLong()
    private val pending = ConcurrentHashMap<String, CompletableDeferred<JSONObject>>()
    @Volatile var onUpdate: (JSONObject) -> Unit = {}

    @Synchronized
    fun start() {
        if (client != 0) return
        System.setProperty("jna.encoding", "UTF-8")
        System.loadLibrary("tdjson")
        val l = Native.load("tdjson", TdLib::class.java)
        lib = l
        l.td_execute("""{"@type":"setLogVerbosityLevel","new_verbosity_level":1}""")
        client = l.td_create_client_id()
        thread(name = "td-receive", isDaemon = true) {
            while (true) {
                val s = try { l.td_receive(2.0) } catch (_: Throwable) { null } ?: continue
                try {
                    val j = JSONObject(s)
                    val x = j.optString("@extra")
                    if (x.isNotEmpty()) pending.remove(x)?.complete(j) else onUpdate(j)
                } catch (_: Throwable) {}
            }
        }
        l.td_send(client, """{"@type":"getOption","name":"version"}""")
    }

    suspend fun call(req: JSONObject): JSONObject {
        val id = extra.incrementAndGet().toString()
        val d = CompletableDeferred<JSONObject>()
        pending[id] = d
        req.put("@extra", id)
        lib!!.td_send(client, req.toString())
        val r = d.await()
        if (r.optString("@type") == "error") throw TdError(r.optInt("code"), r.optString("message"))
        return r
    }

    suspend fun call(type: String, fill: JSONObject.() -> Unit = {}): JSONObject = call(JSONObject().put("@type", type).apply(fill))
}
