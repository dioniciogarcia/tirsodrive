package com.tirso.tirsodrive.wear

import android.content.Context
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** Talks to the TirsoDrive phone app over the Wear Data Layer. The watch never talks to Telegram itself. */
object PhoneLink : MessageClient.OnMessageReceivedListener {
    private val pending = ConcurrentHashMap<String, CompletableDeferred<JSONObject>>()

    fun attach(ctx: Context) { Wearable.getMessageClient(ctx).addListener(this) }
    fun detach(ctx: Context) { Wearable.getMessageClient(ctx).removeListener(this) }

    override fun onMessageReceived(ev: MessageEvent) {
        if (ev.path != "/td/res") return
        val j = try { JSONObject(String(ev.data)) } catch (_: Exception) { return }
        pending.remove(j.optString("rid"))?.complete(j)
    }

    suspend fun request(ctx: Context, op: String, fill: JSONObject.() -> Unit = {}): JSONObject {
        val nodes = Wearable.getNodeClient(ctx).connectedNodes.await()
        val node = nodes.firstOrNull { it.isNearby } ?: nodes.firstOrNull() ?: throw IOException("no phone")
        val rid = UUID.randomUUID().toString()
        val d = CompletableDeferred<JSONObject>()
        pending[rid] = d
        val body = JSONObject().put("op", op).put("rid", rid).apply(fill)
        try {
            Wearable.getMessageClient(ctx).sendMessage(node.id, "/td/req", body.toString().toByteArray()).await()
            return withTimeout(9000) { d.await() }
        } finally {
            pending.remove(rid)
        }
    }
}
