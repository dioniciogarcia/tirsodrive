"""Prints the "## Version X" section of README.md (the release notes for version X).
Usage: python tools/release_notes.py 0.14.0 > notes.md
Always reads and writes UTF-8 (arrows, dashes and accents are fine on any runner)."""
import re
import sys

version = sys.argv[1]
text = open("README.md", encoding="utf-8").read()
m = re.search(r"^## Version " + re.escape(version) + r"\s*$(.*?)(?=^## |\Z)", text, re.S | re.M)
notes = m.group(1).strip() if m else ""
if not notes:
    notes = f"Version {version}"
notes += "\n\nInside the app: Settings › Updates › Update now."
sys.stdout.reconfigure(encoding="utf-8")
print(notes)
