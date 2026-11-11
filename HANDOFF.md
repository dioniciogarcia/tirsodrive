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

## STATUS 2026-11-10: 0.11.0 built too (phone DocumentsProvider TirsoDocs.kt + WearBridge.kt + lib/core/phone_bridge.dart td_index.json; Wear OS Compose module android/wear, build with `cd android && ./gradlew :wear:assembleRelease`, installed via Install-on-Watch.bat). Earlier: 0.9.0, 0.9.1, 0.10.0 built (Windows tray/autostart/T: diagnostics, Audio/Docs, APKs by console, console logos, thumbnails, program isolation).
Still open: confirm tray + Start with Windows + T: drive on the user's PC (ask for desktop.log in app support folder); 0.11.0 = Android storage provider (DocumentsProvider) + Wear OS companion (Data Layer via phone app, no Telegram session); NuORDER Client integration happens in its own chat using tools/tirso_upload.py + the program setup file.
## (original list, 2026-11-06)
1. Two new libraries/categories: **Audio** and **Documents** (channels "TD - Audio", "TD - Documents"; route mp3/m4a/flac/wav/ogg/opus… and pdf/docx/xlsx/pptx/txt/epub… there).
2. **Fix the upload-rule toggles** (Wi-Fi only / charging / quiet hours): they don't work properly.
3. **Subcategories for Games (APKs)**, like ROMs: one channel per console (ties in with the "TD - <Console> APKs" channels).
4. Remove the green "Connected to Telegram" box; instead show a small status dot/symbol right after the "TirsoDrive" title.
5. **Drive letter (T:)**: it says "WebClient service is not running" even though it IS running — fix the detection or mapping.
6. **Start with Windows** option.
7. **Changing the theme sends you back to the home screen** — keep the current screen (don't recreate MaterialApp with a new key; rebuild the colors in place).
8. **Android "connecting" status** shows a spinner almost constantly — show it only while actually connecting, and settle to "connected".
9. **Add TirsoDrive to NuORDER Client, as a separate chat/project** (do it in its own conversation; NuORDER Client = the user's work exe for Excel cleaning and image matching).
10. **A separate channel for each connected program**, so work files never mix with personal ones (a "work profile").
11. **Windows tray icon with an upload status card**, like OneDrive (click the icon near the clock → popup with current uploads and progress).
12. **Windows uploads keep going in the background** even when minimized or the window is closed (close to tray instead of quitting).
13. **Console logos** for each console (ROM and APK libraries).
14. **Thumbnails/previews** for images and videos in the file lists (Telegram's thumbnails for photos/videos, when available).

## Still to build (suggested order)
- LATER (the user postponed it): in-app updates. Recommended: GitHub builds the APK too (signing key as a GitHub secret), and a bot posts builds to a private "TD - Updates" channel; the app checks it and offers Update. Not public GitHub releases (the APK contains the API hash).
(DONE in 0.3.0: global search + filters (search_screen.dart); Copy/Move via forwardMessages send_copy (move deletes the original after the copy is confirmed); Rename = `name=<urlencoded>` in the caption; multi-select + bulk actions (file_actions.dart).)
(DONE in 0.4.0: sharing — send to chats/contacts via forwardMessages send_copy+remove_caption; Android share sheet (MainActivity.shareFiles); Windows copy into Google Drive/OneDrive/Dropbox folders (NativeBridge.cloudFolders). Channel sort with a remembered sortMode. Still possible later: a direct Google Drive API upload.)
(DONE in 0.5.0: folder sync — lib/core/sync.dart + sync_screen.dart; Android SAF tree (pickTree/listTree/writeToTree in MainActivity); state in app-support sync_v1.json; caption `sync=<id> path=<rel>`; changed files replace the old message after the upload; local deletions are never propagated. Runs at start + every 15 min while open (no background scheduling while the app is closed yet). Sharing uses ShareProvider (no copy) + automatic cleanup of TDLib's local copies (prefs temp_files).)
(DONE in 0.8.0: Windows drive letter via a loopback WebDAV server (lib/core/webdav.dart) + `net use T:`; 50 MB WebClient limit fixed with an elevated reg add; encryption (lib/core/vault.dart, AES-256-GCM 1 MB chunks, PBKDF2 key salted with the Telegram account id, caption enc=1); Connected programs (lib/core/programs.dart): BotFather automation, TD - <Console> APKs channels, bot as admin with post rights, config JSON + tools/tirso_upload.py (Telethon). Untested on real Windows/BotFather — beta.)
(DONE in 0.6.0: streaming via a local 127.0.0.1 range server (lib/core/stream_server.dart: downloadFile offset + getFileDownloadedPrefixSize + readFilePart); in-app player on Android (video_player); Windows opens VLC or the browser; image viewer; Light/Dark/Automatic theme (C.* are runtime getters; MaterialApp keyed by themeTick).)
(DONE in 0.7.0: trash (TD - Trash, caption trashed=/from=, purge >30 days at start), favorites (caption `fav`), collections (`col=`), duplicates (size+ext ≥64 KB), libretro box art (categories.boxArtUrl), upload rules (Wi-Fi/charging/quiet hours), integrity size check, app lock (PIN hash + local_auth; MainActivity is a FlutterFragmentActivity), TV layout + focus highlight. Index backup isn't needed: all metadata lives in captions. Splitting >2 GB stays OFF by request. Encryption → 0.8.0.)
8. Tirso Compiler side: call tools/tirso_upload.py (or port it) after each build — to do in the Tirso Compiler project.
9. Future: an all-in-one emulator launcher (libretro-style cores: NES/SNES/Genesis/GB/GBA/N64 (Mupen64Plus-Next)/DS (melonDS)/PS1/PSP (PPSSPP)/GC-Wii (Dolphin); PS2 hard).
   ROMs download from the TD - ROMs channels on launch and are deleted after the session; saves stay local and back up to "TD - Saves" + Google Drive;
   Tirso touch controls / pause menu; controller support; TV mode. Open question: a "Games" tab inside TirsoDrive, or a separate app?

## Known limits right now
- Android 0.2.0: a foreground service (TransferService.kt, dataSync) keeps transfers running in the background, with a notification and Pause/Resume.
  Unfinished uploads are saved in prefs 'queue_v1' and restored after login; a half-sent message is deleted and re-sent. Swiping the app away stops it (resumes on next open).
- TV not tested yet by the user.
- Windows 0.8.0 installer + portable delivered (GitHub run 42311045096). Windows CMakeLists defines _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS for local_auth_windows (newest MSVC on the runners refuses /await otherwise).

## STATUS 2026-11-10 (later): 0.12.0 removed the T: drive (webdav.dart deleted; Windows rejected every mapping with error 67). Windows close-to-tray is native (flutter_window.cpp reads %TEMP%\tirsodrive-tray.flag) and setSkipTaskbar was removed (it crashed the app on tray click).
0.13.0 Wear OS app is STANDALONE: its own TDLib session (libtdjson.so via JNA, files Td.kt/Tg.kt), QR login (zxing), 2FA password screen, vertical snapping pager + crown, voice search for files and contacts, sends with forwardMessages send_copy. It shows only the known categories (custom/program channels are not shown, which keeps work files off the watch). Untested on a real watch. Build: `cd android && ./gradlew :wear:assembleRelease`; libtdjson.so copied to android/wear/src/main/jniLibs (gitignored). Install on the watch via adb/Install-on-Watch.bat.

## STATUS 2026-11-10 (night): 0.14.0 = in-app updates + automatic releases
- Workflow `.github/workflows/release.yml` (replaces windows.yml): on every push to main (except .md/tools changes) it builds Windows (installer + portable), the Android phone/TV APK and the Wear APK, and publishes/updates the GitHub Release `v<pubspec version>` with FIXED names: `TirsoDrive-Setup.exe`, `TirsoDrive-Windows-portable.zip`, `TirsoDrive.apk`, `TirsoDrive-Wear.apk`. Release notes = the `## Version X` section of README.md (tools/release_notes.py, UTF-8).
- ALWAYS bump the version in BOTH `pubspec.yaml` (version: X.Y.Z+CODE) and `lib/core/drive.dart` (appVersion) — the workflow fails if they differ — and add a `## Version X.Y.Z` section to README.md. Android versionCode = major*10000 + minor*100 + patch (0.14.0 -> 1400).
- GitHub Secrets (Settings > Secrets and variables > Actions): ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD. Without them the workflow still builds Android but does NOT publish the APKs (it would otherwise publish apps Android refuses to update). The key = android/app/tirsodrive-release.jks (also inside TirsoDrive-source.zip). BACK IT UP: losing it means nobody can update the installed apps.
- The repo must be PUBLIC for the apps to read releases without a token.
- Update code: lib/core/updater.dart (self-contained kit), lib/ui/update_section.dart, native helpers in MainActivity.kt (apkInfo/canInstallApks/openInstallSettings/installApk/openUrl), REQUEST_INSTALL_PACKAGES + FileProvider `${applicationId}.files`. Windows updates by running the Inno Setup installer silently (the installer closes and restarts the app). Watch: android/wear/.../Upd.kt (PackageInstaller; Wear OS often blocks installs, so adb is the fallback).
- Sandbox limits I hit: Claude's session cannot set Secrets, change repo visibility, or upload binary release assets through the proxy; the user does those in the GitHub website.
