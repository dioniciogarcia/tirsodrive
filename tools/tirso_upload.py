"""
tirso_upload.py — uploads a Tirso Compiler APK to the right TirsoDrive channel, through Tirso's own bot.

Setup (once):
    1. In TirsoDrive: Settings > Connected programs > Connect Tirso Compiler.
       It saves tirso-compiler-telegram.json (in Downloads\\TirsoDrive on Windows).
    2. pip install telethon

Use (Tirso Compiler calls this after each build):
    python tirso_upload.py tirso-compiler-telegram.json "C:\\path\\Super Mario 64 TV.apk" N64

Consoles: N64, DS, PSP, PS2, GameCube, Wii. Files up to 2 GB (4 GB if the setup file allows it).
TV builds: put " TV" only in the APK file name (e.g. "Super Mario 64 TV.apk"), never in the app name.
"""
import json
import os
import sys
import time

from telethon import TelegramClient


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    cfg_path, apk, console = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(cfg_path, encoding="utf-8") as f:
        cfg = json.load(f)
    channels = {k.lower(): v for k, v in cfg["channels"].items()}
    chat_id = channels.get(console.lower())
    if chat_id is None:
        print(f"Unknown console '{console}'. Use one of: {', '.join(cfg['channels'])}")
        return 2
    size = os.path.getsize(apk)
    if size > int(cfg.get("max_file_bytes", 2000 * 1024 * 1024)):
        print(f"{os.path.basename(apk)} is too large for Telegram ({size / 1024**3:.2f} GB).")
        return 3

    session = os.path.join(os.path.dirname(os.path.abspath(cfg_path)), "tirso-bot")
    client = TelegramClient(session, int(cfg["api_id"]), cfg["api_hash"])
    client.start(bot_token=cfg["bot_token"])

    def progress(done: int, total: int) -> None:
        print(f"\rUploading {os.path.basename(apk)}: {done * 100 // max(total, 1)}%", end="", flush=True)

    with client:
        mtime = int(os.path.getmtime(apk))
        client.loop.run_until_complete(
            client.send_file(
                chat_id,
                apk,
                force_document=True,
                caption=f"tirsodrive v1 mtime={mtime} src=tirso",
                progress_callback=progress,
            )
        )
    print(f"\nDone: {os.path.basename(apk)} -> TD - {console} APKs")
    return 0


if __name__ == "__main__":
    t0 = time.time()
    code = main()
    sys.exit(code)
