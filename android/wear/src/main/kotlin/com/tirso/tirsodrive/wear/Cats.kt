package com.tirso.tirsodrive.wear

/** Same channels the phone app knows ("TD - Videos", "TD - ROMs - SNES", "TD - N64 APKs"...). kind: 0 library, 1 APK, 2 ROM. */
data class Cat(val key: String, val title: String, val en: String, val es: String, val kind: Int, val logo: String?)

object Cats {
    val all = listOf(
    Cat("videos", "TD - Videos", "Videos", "Videos", 0, null),
    Cat("photos", "TD - Photos", "Photos", "Fotos", 0, null),
    Cat("games", "TD - Games", "Other games (APKs)", "Otros juegos (APKs)", 0, null),
    Cat("audio", "TD - Audio", "Audio", "Audio", 0, null),
    Cat("docs", "TD - Documents", "Documents", "Documentos", 0, null),
    Cat("compressed", "TD - Compressed", "Compressed", "Comprimidos", 0, null),
    Cat("other", "TD - Other", "Other", "Otros", 0, null),
    Cat("apk_n64", "TD - N64 APKs", "Nintendo 64", "Nintendo 64", 1, "n64"),
    Cat("apk_gba", "TD - GBA APKs", "Game Boy Advance", "Game Boy Advance", 1, "gba"),
    Cat("apk_ds", "TD - DS APKs", "Nintendo DS", "Nintendo DS", 1, "ds"),
    Cat("apk_gc", "TD - GameCube APKs", "GameCube", "GameCube", 1, "gc"),
    Cat("apk_wii", "TD - Wii APKs", "Wii", "Wii", 1, "wii"),
    Cat("apk_ps1", "TD - PS1 APKs", "PlayStation", "PlayStation", 1, "ps1"),
    Cat("apk_ps2", "TD - PS2 APKs", "PlayStation 2", "PlayStation 2", 1, "ps2"),
    Cat("apk_psp", "TD - PSP APKs", "PSP", "PSP", 1, "psp"),
    Cat("rom_nes", "TD - ROMs - NES", "NES", "NES", 2, "nes"),
    Cat("rom_snes", "TD - ROMs - SNES", "SNES", "SNES", 2, "snes"),
    Cat("rom_gb", "TD - ROMs - Game Boy", "Game Boy / Color", "Game Boy / Color", 2, "gb"),
    Cat("rom_gba", "TD - ROMs - GBA", "Game Boy Advance", "Game Boy Advance", 2, "gba"),
    Cat("rom_n64", "TD - ROMs - N64", "Nintendo 64", "Nintendo 64", 2, "n64"),
    Cat("rom_ds", "TD - ROMs - DS", "Nintendo DS", "Nintendo DS", 2, "ds"),
    Cat("rom_3ds", "TD - ROMs - 3DS", "Nintendo 3DS", "Nintendo 3DS", 2, "3ds"),
    Cat("rom_gc", "TD - ROMs - GameCube", "GameCube", "GameCube", 2, "gc"),
    Cat("rom_wii", "TD - ROMs - Wii", "Wii", "Wii", 2, "wii"),
    Cat("rom_ps1", "TD - ROMs - PS1", "PlayStation", "PlayStation", 2, "ps1"),
    Cat("rom_ps2", "TD - ROMs - PS2", "PlayStation 2", "PlayStation 2", 2, "ps2"),
    Cat("rom_psp", "TD - ROMs - PSP", "PSP", "PSP", 2, "psp"),
    Cat("rom_genesis", "TD - ROMs - Genesis", "Genesis / Mega Drive", "Genesis / Mega Drive", 2, "genesis"),
    )
    fun byTitle(t: String): Cat? = all.firstOrNull { it.title.equals(t, ignoreCase = true) }
}
