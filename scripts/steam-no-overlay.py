#!/usr/bin/env python3
"""Set OverlayAppEnable 0 for app 730 in a Steam localconfig.vdf. Run with Steam stopped."""
import re
import shutil
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
backup = path + ".cs2mac-backup"


def write(new):
    """Keep the first original as a backup, then replace the file atomically."""
    try:
        open(backup, "x").close()
        shutil.copy2(path, backup)
    except FileExistsError:
        pass
    with open(path + ".tmp", "w", encoding="utf-8") as f:
        f.write(new)
    shutil.move(path + ".tmp", path)
m = re.search(r'\n(\t+)"apps"\n\t+\{\n', text)
if not m:
    sys.exit(f"no apps section in {path}")
indent = m.group(1) + "\t"
block = re.compile(r'(\n' + indent + r'"730"\n' + indent + r'\{\n)')
entry = indent + '\t"OverlayAppEnable"\t\t"0"\n'
if re.search(r'"730"\n' + indent + r'\{\n(?:' + indent + r'\t[^\n]*\n)*?' + re.escape(entry), text):
    print("overlay already disabled")
elif block.search(text[m.end():]):
    start = m.end()
    text = text[:start] + block.sub(lambda b: b.group(1) + entry, text[start:], count=1)
    write(text)
    print("overlay disabled for CS2")
else:
    start = m.end()
    text = text[:start] + f'{indent}"730"\n{indent}{{\n{entry}{indent}}}\n' + text[start:]
    write(text)
    print("overlay disabled for CS2")
