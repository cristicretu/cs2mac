#!/usr/bin/env python3
"""Set OverlayAppEnable 0 for app 730 in a Steam localconfig.vdf. Run with Steam stopped.

The first original is kept next to the file as <name>.cs2mac-backup; every write is atomic.
"""
import os
import re
import shutil
import sys
import tempfile

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
backup = path + ".cs2mac-backup"


def replace_atomically(dst, write):
    """Write through a private temp file in dst's directory, keep the mode, rename over dst."""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(dst)), prefix=".cs2mac-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            write(f)
        shutil.copymode(path, tmp)
        os.replace(tmp, dst)
    except BaseException:
        os.unlink(tmp)
        raise


def save(new):
    if not os.path.exists(backup):
        replace_atomically(backup, lambda f: f.write(text))
    replace_atomically(path, lambda f: f.write(new))


m = re.search(r'\n(\t+)"apps"\n\t+\{\n', text)
if not m:
    sys.exit(f"no apps section in {path}")
indent = m.group(1) + "\t"
start = m.end() - 1  # keep the newline so the first app in the section matches too
app = re.compile(r'\n' + indent + r'"730"\n' + indent + r'\{\n((?:' + indent + r'\t[^\n]*\n)*?)' + indent + r'\}\n')
entry = indent + '\t"OverlayAppEnable"\t\t"0"\n'
setting = re.compile(r'^' + indent + r'\t"OverlayAppEnable"\t\t"[^"]*"\n', re.M)

found = app.search(text, start)
if found:
    body = found.group(1)
    if entry in body:
        print("overlay already disabled")
        sys.exit(0)
    body = setting.sub(entry, body, count=1) if setting.search(body) else entry + body
    new = text[:found.start(1)] + body + text[found.end(1):]
else:
    new = text[:start + 1] + f'{indent}"730"\n{indent}{{\n{entry}{indent}}}\n' + text[start + 1:]
save(new)
print("overlay disabled for CS2")
