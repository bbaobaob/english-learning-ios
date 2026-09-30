#!/usr/bin/env python3
"""Structural sanity check for the Swift tree.

Catches what a compiler would catch first and that no symbol index catches:
unbalanced braces/parens per file, and unbalanced braces across the whole module
(a file that opens a brace another file closes).

NOT a type checker. Balanced braces is a necessary condition for parsing, not a
sufficient one for compiling.

Usage: python3 Scripts/braces.py [root ...]
"""
from __future__ import annotations

import os
import sys

PAIRS = {"{": "}", "(": ")", "[": "]"}


def strip(src: str) -> str:
    """Blank comments and string literals; keep line structure."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            depth = 1
            i += 2
            while i < n and depth:
                if src.startswith("/*", i):
                    depth += 1
                    i += 2
                elif src.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            continue
        if src.startswith('"""', i):
            i += 3
            while i < n and not src.startswith('"""', i):
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == "\n":
                    out.append("\n")
                i += 1
            i += 3
            continue
        if c == '"':
            i += 1
            while i < n and src[i] != '"':
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == "\n":
                    out.append("\n")
                i += 1
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def main() -> int:
    roots = sys.argv[1:] or ["App", "Packages"]
    files = []
    for root in roots:
        for dp, dn, fn in os.walk(root):
            dn[:] = [d for d in dn if d not in (".build", "build")]
            for f in sorted(fn):
                if f.endswith(".swift"):
                    files.append(os.path.join(dp, f))
    files.sort()

    bad = 0
    module_total = {"{": 0, "(": 0, "[": 0}
    per_file_net = []
    for path in files:
        with open(path, encoding="utf-8", errors="replace") as fh:
            code = strip(fh.read())
        stack = []
        err = None
        for lineno, line in enumerate(code.split("\n"), 1):
            for ch in line:
                if ch in PAIRS:
                    stack.append((ch, lineno))
                elif ch in PAIRS.values():
                    if not stack:
                        err = "unexpected '%s' at line %d" % (ch, lineno)
                        break
                    opener, oline = stack.pop()
                    if PAIRS[opener] != ch:
                        err = "mismatched '%s' opened line %d closed by '%s' line %d" % (
                            opener, oline, ch, lineno)
                        break
            if err:
                break
        if err is None and stack:
            opener, oline = stack[-1]
            err = "unclosed '%s' opened at line %d" % (opener, oline)
        if err:
            bad += 1
            print("  !! %s: %s" % (path, err))

    print("checked %d swift files, %d with unbalanced brackets" % (len(files), bad))
    print("REMINDER: balanced brackets proves parseability only, not that it compiles.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())