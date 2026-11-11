# TirsoDrive

Your Telegram account as an unlimited cloud drive. Android phone/tablet, Android TV, Windows and Wear OS.

## Download

Always the newest version: **https://github.com/dioniciogarcia/tirsodrive/releases/latest**

| What | File |
| --- | --- |
| Windows installer | `TirsoDrive-Setup.exe` |
| Windows portable (no install) | `TirsoDrive-Windows-portable.zip` |
| Android phone, tablet and TV (one APK) | `TirsoDrive.apk` |
| Wear OS watch | `TirsoDrive-Wear.apk` |

## How updating works

Every time a change is pushed to GitHub, GitHub compiles everything and publishes it as a release called `v<version>`.
Inside the apps open **Settings › Updates** and press **Check for updates**, then **Update now**.
Windows reinstalls itself in place; Android downloads the APK and opens Android's installer (the first time you must allow
"install from this app"). The watch shows its version and whether a newer one exists; Wear OS often blocks installing apps,
in which case install `TirsoDrive-Wear.apk` with adb or from the PC.
Android only accepts updates signed with the same key, so the signing key is kept safe as GitHub Secrets (see HANDOFF.md).

## Changelog

The workflow uses the "Version X" section below as the release notes of version X.

## Version 0.14.2

- Fixed "Message identifiers must be in a strictly increasing order" when deleting, moving or copying several selected files at once.

## Version 0.14.1

- First release built and signed completely by GitHub: the phone/TV and watch APKs are now published in the release too.
- Use Settings › Updates › Update now to get it from version 0.14.0.

## Version 0.14.0

- **Check for updates / Update now** inside the apps (Settings › Updates): Windows, Android phone/tablet, Android TV (works with the remote) and the watch. Updates now come from GitHub Releases, built and signed automatically.
- Windows and Android check silently at startup (Android at most every 6 hours) and show a small marker next to Settings (and in the tray tooltip) when a newer version exists.
- The Windows update downloads the installer, checks it, closes TirsoDrive and reinstalls it in place. It asks before interrupting uploads or downloads.
- Upload stall watchdog (0.12.2): a stalled upload is nudged to reconnect and restarted after 3 minutes.
- Standalone Wear OS app with its own QR login, Profile page, voice search and contacts (0.13.x). The T: drive was removed (0.12.0).

## Version 0.11.0

**TirsoDrive in Android's file picker** ("Save to…", backups, game saves): pick TirsoDrive, choose a channel folder, save. The file uploads when TirsoDrive can (right away if it's open; otherwise a notification asks you to open it). Browsing shows what TirsoDrive last indexed; to open a cloud file, use the app.
**Wear OS watch app** (separate download, TirsoDrive-Watch-Installer-0.11.0.zip): swipe through categories, subcategories (APKs/ROMs by console), browse, search by voice, send to up to 6 favorite contacts. It asks the phone, so it never signs in to Telegram and uses no device slot. Setup: phone Settings › Watch & file picker.

## Version 0.10.0

**Previews:** photos and videos show a small picture in file lists (new uploads carry one; older photos under 4 MB get one on demand; videos uploaded before this show the badge until re-uploaded; Windows makes previews for photos only).
**Connect another program** (Settings › Connected programs): its own bot + its own channel(s), and "Keep separate from my personal files" keeps them out of your search, favorites and duplicates (open them from "Programs" / the lock-marked sidebar section).

## Version 0.9.1

**Games (APKs) by console** (N64, GBA, DS, GameCube, Wii, PS1, PS2, PSP + "Other games"), **console logos**, tray/start-with-Windows hardening, and a diagnostic log (`desktop.log`) for the T: drive and tray.

## Version 0.9.0

Windows tray icon + status card, Start with Windows, close-to-tray, Audio and Documents libraries, status dot, theme keeps your screen, upload-rule switches fixed, TV search focus fix.

## Version 0.8.0

**Encryption** (Settings › Encryption): set a password, then turn on "Encrypt these files" when uploading with the + button / Back up a folder.
Telegram only stores scrambled data; encrypted files show a 🔒 and are decrypted when you open, save or share them. Forget the password = the files can't be opened.
**Drive letter T: (Windows, beta)** (Settings › Drive letter): your channels appear as folders in File Explorer; copy in to upload, open to stream, delete = Trash.
Windows limits these files to 50 MB unless you press "Allow files over 50 MB" once (asks for admin permission).
**Connected programs › Connect Tirso Compiler:** creates Tirso's own bot via @BotFather, the six "TD - <Console> APKs" channels, gives the bot access to only those,
and saves tirso-compiler-telegram.json. Tirso Compiler uploads with tools/tirso_upload.py (in TirsoDrive-source.zip / on GitHub).

## Version 0.7.0

**Trash:** Delete now moves files to a "TD - Trash" channel for 30 days (restore anytime; emptied automatically after 30 days).
**Favorites** and **Collections** (file menu ★ / "Add to collection…"; saved in Telegram so every device sees them).
**Duplicates** finder (same size and type anywhere; keeps the oldest copy, extras go to the Trash).
**ROM box art** from libretro thumbnails in ROM channels (needs standard No-Intro file names).
**Upload rules** (Settings): only on Wi-Fi, only while charging, pause between hours.
**Integrity check:** every upload's size is verified in Telegram ("Verified ✓" in Transfers).
**App lock** (Settings): PIN, optionally fingerprint/face; locks again after a minute in the background.
**TV mode:** on Android TV / Google TV / Fire TV the app uses the sidebar layout and shows a focus highlight for the remote.

## Version 0.6.1

Fixed 0.6.0 freezing and closing right after opening (a color in the new theme code referred to itself).

## Version 0.6.0

**Play (stream)** for videos and music: it starts in seconds while the rest downloads, and you can jump anywhere (in-app player on Android; on Windows it opens in VLC if installed, otherwise the browser).
**View** photos in the app with pinch-zoom. Nothing stays on the device afterwards.
**Theme:** Settings › Theme › Light / Dark / Automatic (follows the phone or PC).

## Version 0.5.0

**Folder sync** (Settings › Folder sync on Android; "Folder sync" in the Windows sidebar): pair a folder with a channel.
*Back up* uploads new and changed files (subfolders kept); *Two-way* also downloads files that are only in the channel.
Runs when the app opens, every 15 min while it's open, or with Sync now. Nothing is ever deleted automatically, and files already in the channel aren't uploaded twice.
**Lighter sharing:** sharing to other apps no longer keeps copies on the phone (removed about 10 minutes after sharing). Files saved to Downloads, copied to cloud folders
or synced no longer leave a second hidden copy either.

## Version 0.4.0

**Share…** (file menu, or the share icon when several are selected): send to a Telegram chat or contact as a clean copy (instant, nothing re-uploads),
share to other apps (Android share menu: WhatsApp, Instagram, Drive…), or on Windows copy into your Google Drive / OneDrive folder.
**Sort** any channel with the ⇅ button: newest, oldest, name A–Z / Z–A, largest, smallest (remembered).

## Version 0.3.0

Global search across all channels (Library › 🔍 on Android, the search box or "Search" in the sidebar on Windows), with filters for where, type, size, date (upload or original) and sort.
New file actions: **Copy to…**, **Move to…** (instant, nothing re-uploads; the original is removed only after the copy is confirmed), **Rename** (the new name shows on every device).
**Long-press** a file to select several, then Save / Copy / Move / Delete them together.

## Version 0.2.0

Background uploads with a progress notification (Pause/Resume). Unfinished uploads are remembered and resume after the app or phone restarts. The first upload asks permission to show notifications: tap Allow.

## Version 0.1.3

Fixed uploads staying at 100% when a file went to a different channel than an earlier upload. The upload counter now counts only the current batch, and the end of each upload shows "Finishing…".

## Version 0.1.2

API ID and hash built in; the setup screen is gone.

## Version 0.1.1

Fixed uploads failing with "InputFile is not specified".
