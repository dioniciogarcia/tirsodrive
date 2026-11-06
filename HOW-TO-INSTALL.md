# TirsoDrive — Android 0.8.0 / Windows 0.1.3

Your Telegram API ID and hash are built into this version, so there's no setup screen.
Just install it and sign in.

## Step 1 — Install the APK

1. Copy `TirsoDrive-0.8.0.apk` to the phone (USB cable, Google Drive, or Quick Share).
2. Tap the file. If Android asks, allow **Install unknown apps** for the app you opened it with.
3. Tap **Install**. If an older TirsoDrive is installed, this updates it and you stay signed in.

For a TV (Google TV Streamer, TCL, Fire TV), use the same APK. You can sideload it with
"Send Files to TV", "Downloader", or ADB: `adb install -r TirsoDrive-0.8.0.apk`

## Step 2 — Sign in

- **Phone number:** type it with the country code (for example +1 809…). The code arrives in your
  Telegram app.
- **QR code:** use this if Telegram is on a different device. On that device, open Telegram,
  go to Settings › Devices › Link Desktop Device, and scan the code.
- If your account has a cloud password, TirsoDrive asks for it next.

Each person signs in with their own Telegram account and only sees their own files.

## What Phase 1 does

- **Library** with Videos, Photos, Games (APKs), Compressed, Other, and ROMs by console.
- **Channels are created automatically** ("TD - Videos", "TD - ROMs - N64", …) the first time a file goes there.
  They are private, and they're moved to the Archive folder in Telegram so your normal chat list stays clean.
- **New channel** button for your own channels ("TD - <name>").
- **Upload (+ button):** pick files and they sort themselves by type. For .iso, .chd, .rvz and similar files,
  you choose the console. Files over the size limit (2 GB, or 4 GB in Settings) are skipped and listed.
- **One file at a time**, with a progress bar, speed and time left on the Transfers tab.
  Only the file currently uploading is copied into temporary storage, so the phone doesn't fill up.
- **Tap any file** to Open it, Save it to Download/TirsoDrive, see File info, or Delete it.
- English / Spanish switch, and the screen stays on while transfers run.


## Windows

1. Double-click **TirsoDrive-Setup-0.1.3.exe**. Admin rights aren't needed.
2. Windows may show **"Windows protected your PC"**, because the installer isn't signed with a paid certificate.
   Click **More info → Run anyway**.
3. Choose a language, tick "Create a desktop shortcut" if you want one, and install.
4. Sign in with the **QR code** (scan it from Telegram on your phone: Settings › Devices › Link Desktop Device)
   or with your phone number.

On Windows:
- **Drag files** onto the open channel to upload them straight into it.
- **Drop a folder**, or click **Back up a folder**: every file inside it, including subfolders, is sorted into the right channels,
  and you review the list before anything uploads.
- Saved files go to **Downloads\TirsoDrive**.
- **TirsoDrive-0.1.3-portable.zip** is the same app without installing: unzip it anywhere and run TirsoDrive.exe.

## Known limits in this phase

- Android uploads keep going with the screen locked or in other apps (follow them in the notification).
  If you swipe TirsoDrive away from recent apps, uploads stop and resume the next time you open it.
- Sync, global search, sharing, the T: drive and the rest come in the next phases (see HANDOFF.md).

## Keep private

- **The APK** now contains your API ID and hash. Share it with family, but don't post it publicly.
- **TirsoDrive-source.zip** holds the full app code, the API ID and hash, and the app's **signing key**
  (`android/app/tirsodrive-release.jks` and `android/key.properties`). Every future TirsoDrive update has to be
  signed with this same key, or Android won't install it over the old version.

## Changes

- **0.8.0:** **Encryption** (Settings › Encryption): set a password, then turn on "Encrypt these files" when uploading with the + button / Back up a folder.
  Telegram only stores scrambled data; encrypted files show a 🔒 and are decrypted when you open, save or share them. Forget the password = the files can't be opened.
  **Drive letter T: (Windows, beta)** (Settings › Drive letter): your channels appear as folders in File Explorer; copy in to upload, open to stream, delete = Trash.
  Windows limits these files to 50 MB unless you press "Allow files over 50 MB" once (asks for admin permission).
  **Connected programs › Connect Tirso Compiler:** creates Tirso's own bot via @BotFather, the six "TD - <Console> APKs" channels, gives the bot access to only those,
  and saves tirso-compiler-telegram.json. Tirso Compiler uploads with tools/tirso_upload.py (in TirsoDrive-source.zip / on GitHub).
- **0.7.0:** **Trash:** Delete now moves files to a "TD - Trash" channel for 30 days (restore anytime; emptied automatically after 30 days).
  **Favorites** and **Collections** (file menu ★ / "Add to collection…"; saved in Telegram so every device sees them).
  **Duplicates** finder (same size and type anywhere; keeps the oldest copy, extras go to the Trash).
  **ROM box art** from libretro thumbnails in ROM channels (needs standard No-Intro file names).
  **Upload rules** (Settings): only on Wi-Fi, only while charging, pause between hours.
  **Integrity check:** every upload's size is verified in Telegram ("Verified ✓" in Transfers).
  **App lock** (Settings): PIN, optionally fingerprint/face; locks again after a minute in the background.
  **TV mode:** on Android TV / Google TV / Fire TV the app uses the sidebar layout and shows a focus highlight for the remote.
- **0.6.1:** Fixed 0.6.0 freezing and closing right after opening (a color in the new theme code referred to itself).
- **0.6.0:** **Play (stream)** for videos and music: it starts in seconds while the rest downloads, and you can jump anywhere (in-app player on Android; on Windows it opens in VLC if installed, otherwise the browser).
  **View** photos in the app with pinch-zoom. Nothing stays on the device afterwards.
  **Theme:** Settings › Theme › Light / Dark / Automatic (follows the phone or PC).
- **0.5.0:** **Folder sync** (Settings › Folder sync on Android; "Folder sync" in the Windows sidebar): pair a folder with a channel.
  *Back up* uploads new and changed files (subfolders kept); *Two-way* also downloads files that are only in the channel.
  Runs when the app opens, every 15 min while it's open, or with Sync now. Nothing is ever deleted automatically, and files already in the channel aren't uploaded twice.
  **Lighter sharing:** sharing to other apps no longer keeps copies on the phone (removed about 10 minutes after sharing). Files saved to Downloads, copied to cloud folders
  or synced no longer leave a second hidden copy either.
- **0.4.0:** **Share…** (file menu, or the share icon when several are selected): send to a Telegram chat or contact as a clean copy (instant, nothing re-uploads),
  share to other apps (Android share menu: WhatsApp, Instagram, Drive…), or on Windows copy into your Google Drive / OneDrive folder.
  **Sort** any channel with the ⇅ button: newest, oldest, name A–Z / Z–A, largest, smallest (remembered).
- **0.3.0:** Global search across all channels (Library › 🔍 on Android, the search box or "Search" in the sidebar on Windows), with filters for where, type, size, date (upload or original) and sort.
  New file actions: **Copy to…**, **Move to…** (instant, nothing re-uploads; the original is removed only after the copy is confirmed), **Rename** (the new name shows on every device).
  **Long-press** a file to select several, then Save / Copy / Move / Delete them together.
- **0.2.0 (Android):** Background uploads with a progress notification (Pause/Resume). Unfinished uploads are remembered and resume after the app or phone restarts. The first upload asks permission to show notifications: tap Allow.
- **0.1.3:** Fixed uploads staying at 100% when a file went to a different channel than an earlier upload. The upload counter now counts only the current batch, and the end of each upload shows "Finishing…".
- **0.1.2:** API ID and hash built in; the setup screen is gone.
- **0.1.1:** Fixed uploads failing with "InputFile is not specified".
