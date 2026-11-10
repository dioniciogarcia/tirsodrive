package com.tirso.tirsodrive.wear

import org.json.JSONArray
import org.json.JSONObject

data class Group(val key: String, val title: String, val chatId: Long, val parent: String?, val logo: String?, val count: Int, val kids: Boolean)
data class WFile(val id: Long, val chat: Long, val name: String, val size: Long, val date: Long)
data class Contact(val id: Long, val name: String)

fun JSONArray?.groups(): List<Group> = if (this == null) emptyList() else List(length()) {
    val o = getJSONObject(it)
    Group(o.optString("key"), o.optString("title"), o.optLong("chatId"), if (o.isNull("parent")) null else o.optString("parent"),
        if (o.isNull("logo")) null else o.optString("logo"), o.optInt("count"), o.optBoolean("kids"))
}

fun JSONArray?.wfiles(): List<WFile> = if (this == null) emptyList() else List(length()) {
    val o = getJSONObject(it)
    WFile(o.optLong("i"), o.optLong("c"), o.optString("n"), o.optLong("s"), o.optLong("d"))
}

fun JSONArray?.contacts(): List<Contact> = if (this == null) emptyList() else List(length()) {
    val o = getJSONObject(it); Contact(o.optLong("id"), o.optString("name"))
}

fun sizeText(b: Long): String = when {
    b >= 1L shl 30 -> String.format("%.1f GB", b / 1073741824.0)
    b >= 1L shl 20 -> String.format("%.1f MB", b / 1048576.0)
    b >= 1L shl 10 -> String.format("%.0f KB", b / 1024.0)
    else -> "$b B"
}

class Strings(val es: Boolean) {
    val search get() = if (es) "Buscar" else "Search"
    val searchHint get() = if (es) "Toca para hablar" else "Tap to speak"
    val noPhone get() = if (es) "Abre TirsoDrive en el teléfono" else "Open TirsoDrive on your phone"
    val retry get() = if (es) "Reintentar" else "Retry"
    val empty get() = if (es) "Sin archivos" else "No files"
    val more get() = if (es) "Más…" else "More…"
    val share get() = if (es) "Enviar a…" else "Send to…"
    val noFavs get() = if (es) "Elige contactos favoritos en el teléfono" else "Choose favorite contacts on the phone"
    val sent get() = if (es) "Enviado" else "Sent"
    val finishOnPhone get() = if (es) "Abre TirsoDrive en el teléfono para terminar el envío" else "Open TirsoDrive on the phone to finish sending"
    val results get() = if (es) "Resultados" else "Results"
    val files get() = if (es) "archivos" else "files"
}
