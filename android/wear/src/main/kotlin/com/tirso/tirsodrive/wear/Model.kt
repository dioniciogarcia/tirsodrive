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
    val noPhone get() = if (es) "Sin conexión" else "No connection"
    val retry get() = if (es) "Reintentar" else "Retry"
    val empty get() = if (es) "Sin archivos" else "No files"
    val more get() = if (es) "Más…" else "More…"
    val share get() = if (es) "Enviar a…" else "Send to…"
    val noFavs get() = if (es) "Elige contactos favoritos en el teléfono" else "Choose favorite contacts on the phone"
    val allContacts get() = if (es) "Todos los contactos" else "All contacts"
    val searchContacts get() = if (es) "Buscar contacto" else "Search contacts"
    val signIn get() = if (es) "Escanea con Telegram" else "Scan with Telegram"
    val signInHow get() = if (es) "Ajustes › Dispositivos › Vincular dispositivo" else "Settings › Devices › Link Desktop Device"
    val password get() = if (es) "Contraseña de verificación en dos pasos" else "Two-step verification password"
    val wrongPassword get() = if (es) "Contraseña incorrecta" else "Wrong password"
    val ok get() = if (es) "Aceptar" else "OK"
    val signOut get() = if (es) "Cerrar sesión" else "Sign out"
    val loading get() = if (es) "Cargando…" else "Loading…"
    val profile get() = if (es) "Perfil" else "Profile"
    val refresh get() = if (es) "Actualizar" else "Refresh"
    val pullHint get() = if (es) "Sin bibliotecas · desliza hacia abajo para actualizar" else "No libraries yet · pull down to refresh"
    val updates get() = if (es) "Actualizaciones" else "Updates"
    val version get() = if (es) "Versión" else "Version"
    val checkUpdates get() = if (es) "Buscar actualización" else "Check for updates"
    val updateNow get() = if (es) "Actualizar ahora" else "Update now"
    val upToDate get() = if (es) "Tienes la más reciente" else "You're up to date"
    val updAvailable get() = if (es) "Disponible" else "Available"
    val updNote get() = if (es) "Si el reloj no permite instalar apps, instala el APK del reloj con adb." else "If the watch won't allow installs, install the watch APK with adb."
    val allowInstall get() = if (es) "Permite instalar desde esta app y vuelve a tocar Actualizar" else "Allow installs from this app, then tap Update again"
    val sent get() = if (es) "Enviado" else "Sent"
    val finishOnPhone get() = if (es) "Abre TirsoDrive en el teléfono para terminar el envío" else "Open TirsoDrive on the phone to finish sending"
    val results get() = if (es) "Resultados" else "Results"
    val files get() = if (es) "archivos" else "files"
}
