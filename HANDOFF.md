# TirsoDrive — project handoff (for a new Claude conversation)

Start a new chat with: "Continue TirsoDrive. Read HANDOFF.md in my Desktop\TirsoDrive folder (or the GitHub repo dioniciogarcia/tirsodrive)."

## What it is
TirsoDrive: the user's own app that uses Telegram as an unlimited cloud drive. Android (phones and TV) + Windows.
Inspired by caamer20/Telegram-Drive but built from scratch. The user has no coding knowledge: deliver finished
APKs and installers, with step-by-step instructions. English + Spanish UI.

## Where things are
- GitHub (private): **dioniciogarcia/tirsodrive** (username has NO "a" after "dionicio").
  The workflow `.github/workflows/windows.yml` builds the Windows installer (Inno Setup) + portable zip on every push to main.
  The TDLib dll is cached by commit; the first build took about 70 min, later builds are about 10 min.
- PC folder: `C:\Users\dioni\Desktop\TirsoDrive` — APK, Windows installer, HOW-TO-INSTALL.md, TirsoDrive-source.zip.
- **Android signing key** is NOT on GitHub (gitignored). It's only in TirsoDrive-source.zip:
  `android/app/tirsodrive-release.jks` + `android/key.properties`. Every future APK must be signed with it.
- Android is built in Claude's Linux container: Flutter 3.47.9, Android SDK 36, prebuilt TDLib from
  up9cloud/android-libtdjson (libs.tar.gz, arm64-v8a + armeabi-v7a) copied to `android/app/src/main/jniLibs/` (gitignored).
  Gradle: Maven Central rate-limits → the googleapis Maven mirror is added in android/build.gradle.kts and settings.gradle.kts.

## Tech
- Flutter app; TDLib JSON via dart:ffi (`lib/td/td_client.dart`). TDLib **1.8.65**, commit a8f21f5230172634becc1739050ef23ecd6ea291
  (same on Android and Windows). Note: in this version `inputMessageDocument.document` is an `inputDocument` wrapper.
- Telegram API ID/hash are built into `lib/core/drive.dart` (builtInApiId / builtInApiHash). Private repo; don't publish the APK.
- Files: `lib/core/drive.dart` (auth, channels, files, one-at-a-time transfer queue), `categories.dart` (routing rules),
  `strings.dart` (EN/ES), `native.dart` (Android helper + Windows file ops), `lib/ui/*` (screens; `desktop_shell.dart` = Windows layout).
- Android native helper: `android/app/src/main/kotlin/com/tirso/tirsodrive/MainActivity.kt` (SAF picker, copy-to-cache, save to Downloads, open file, keep screen on).
- Design: dark navy #0E1320, accent #3BA7F5, Inter + Space Grotesk. Design canvas artifact "TirsoDrive Design Concepts". The user approved this look.

## Done (Phase 1 + most of Phase 2)
- 0.1.0–0.1.3 Android, tested by the user: QR/phone/2FA sign-in, auto-created private channels (archived),
  category routing (ISO/CHD/RVZ ask for the console), New channel, upload queue (one at a time, progress, speed, "Finishing…"),
  2 GB limit (4 GB setting) with a "too large" list, file menu (Open, Save to Downloads, Info, Delete), EN/ES.
- Fixed bugs: inputDocument wrapper (0.1.1); uploads stuck at 100% because temporary message ids repeat per channel (0.1.3).
- Windows: sidebar layout, drag-and-drop (files to the current channel; folders scanned and auto-sorted),
  "Back up a folder", installer. (The first Windows build was being delivered when this file was written.)

## Decisions the user made
- App name **TirsoDrive**; EN + ES; channel names use the prefix **"TD - "** (e.g. "TD - Videos", "TD - ROMs - N64").
- Categories: Videos, Photos, Games (APKs), Compressed, Other, ROMs per console.
- Filter out files over 2 GB for now (they may buy Premium later → 4 GB setting already exists).
- Uploads strictly one at a time.
- **Option B**: each external program (e.g. Tirso Compiler) gets its own Telegram **bot** limited to its own channels.
- Tirso Compiler's generated APKs go to per-console channels: **"TD - N64 APKs", "TD - DS APKs", "TD - PSP APKs", "TD - PS2 APKs",
  "TD - GameCube APKs", "TD - Wii APKs"**, created on the first build; TV builds sit in the same channel with " TV" only in the
  file name (e.g. "Super Mario 64 TV.apk"), never in the app name.
- The user wants ALL 11 extras: trash bin (30 days), integrity check, index backup to Saved Messages, upload rules (Wi-Fi/charging/speed/work hours),
  app lock, duplicate finder, ROM box art (libretro thumbnails), TV mode, optional encryption, favorites/collections,
  splitting files over 2 GB (keep OFF for now).

## Still to build (suggested order)
1. Global search across all channels (local index, works offline) + filters (category, type/extension, console, size, upload date, original date — stored in the caption as `mtime=`).
2. Long-press menu additions: Copy to…, Move to…, Rename (app-side display name), multi-select, bulk actions.
3. Sharing: to Telegram contacts (send as a copy, no "forwarded from"), the Android share sheet / Windows share (WhatsApp, Instagram, Drive…), and "Send to cloud" (Drive/OneDrive desktop folders; a direct Google Drive API upload later).
4. Sync (two-way folder ↔ channel, conflict prompts, no silent deletes) on Windows AND Android; background uploads on Android (foreground service) and a remembered queue.
5. Windows virtual drive (T:) — start with WebDAV + "Map network drive", maybe WinFsp later.
6. Video/image streaming without a full download; in-app image viewer.
7. The 11 extras above.
8. Tirso Compiler integration: bot per program (Option B), upload APKs to the "TD - <Console> APKs" channels.
9. Future: an all-in-one emulator launcher (libretro-style cores: NES/SNES/Genesis/GB/GBA/N64 (Mupen64Plus-Next)/DS (melonDS)/PS1/PSP (PPSSPP)/GC-Wii (Dolphin); PS2 hard).
   ROMs download from the TD - ROMs channels on launch and are deleted after the session; saves stay local and back up to "TD - Saves" + Google Drive;
   Tirso touch controls / pause menu; controller support; TV mode. Open question: a "Games" tab inside TirsoDrive, or a separate app?

## Known limits right now
- Android 0.2.0: a foreground service (TransferService.kt, dataSync) keeps transfers running in the background, with a notification and Pause/Resume.
  Unfinished uploads are saved in prefs 'queue_v1' and restored after login; a half-sent message is deleted and re-sent. Swiping the app away stops it (resumes on next open).
- TV not tested yet by the user.
- Windows 0.1.3 (portable) delivered; the user is testing it with GBA ROM uploads.
