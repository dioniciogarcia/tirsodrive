# TirsoDrive 0.1.3 — Phase 1 (Android)

Your Telegram API ID and hash are built into this version, so there's no setup screen.
Just install it and sign in.

## Step 1 — Install the APK

1. Copy `TirsoDrive-0.1.3.apk` to the phone (USB cable, Google Drive, or Quick Share).
2. Tap the file. If Android asks, allow **Install unknown apps** for the app you opened it with.
3. Tap **Install**. If an older TirsoDrive is installed, this updates it and you stay signed in.

For a TV (Google TV Streamer, TCL, Fire TV), use the same APK. You can sideload it with
"Send Files to TV", "Downloader", or ADB: `adb install -r TirsoDrive-0.1.3.apk`

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

## Known limits in this phase

- Keep the app open while it uploads. Uploads that continue after you close the app come in a later phase.
- If you close the app, the transfer queue is not remembered yet.
- Windows version, sync, backup scan, global search, sharing and the rest come in the next phases.

## Keep private

- **The APK** now contains your API ID and hash. Share it with family, but don't post it publicly.
- **TirsoDrive-source.zip** holds the full app code, the API ID and hash, and the app's **signing key**
  (`android/app/tirsodrive-release.jks` and `android/key.properties`). Every future TirsoDrive update has to be
  signed with this same key, or Android won't install it over the old version.

## Changes

- **0.1.3:** Fixed uploads staying at 100% when a file went to a different channel than an earlier upload. The upload counter now counts only the current batch, and the end of each upload shows "Finishing…".
- **0.1.2:** API ID and hash built in; the setup screen is gone.
- **0.1.1:** Fixed uploads failing with "InputFile is not specified".
