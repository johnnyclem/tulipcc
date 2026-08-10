#!/usr/bin/env python3
"""Regenerate Sources/PatchBanks.swift from tulip/shared/py/patches.py."""
from __future__ import annotations

import re
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
PATCHES_PY = ROOT / "tulip" / "shared" / "py" / "patches.py"
OUT = pathlib.Path(__file__).resolve().parent / "Sources" / "PatchBanks.swift"


def main() -> None:
    text = PATCHES_PY.read_text()
    start = text.index("patches =")
    start = text.index("[", start)
    depth = 0
    i = start
    while i < len(text):
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
            if depth == 0:
                i += 1
                break
        i += 1
    body = text[start:i]
    names = re.findall(r'"([^"]*)"', body)
    if len(names) < 256:
        raise SystemExit(f"expected >=256 patch names, got {len(names)}")

    juno = names[:128]
    dx7 = names[128:256]

    def esc(s: str) -> str:
        return s.replace("\\", "\\\\").replace('"', '\\"')

    lines = [
        "// Auto-generated from tulip/shared/py/patches.py — do not hand-edit",
        "// Regenerate: python3 tools/amyboard-starter/gen_patch_banks.py",
        "import Foundation",
        "",
        "enum PatchBanks {",
        "    /// JUNO-6 style factory bank (AMY patches 0–127)",
        "    static let juno: [String] = [",
    ]
    for n in juno:
        lines.append(f'        "{esc(n)}",')
    lines += [
        "    ]",
        "",
        "    /// DX7 factory bank (AMY patches 128–255)",
        "    static let dx7: [String] = [",
    ]
    for n in dx7:
        lines.append(f'        "{esc(n)}",')
    lines += ["    ]", "}", ""]
    OUT.write_text("\n".join(lines))
    print(f"Wrote {OUT} ({len(juno)} juno + {len(dx7)} dx7)")


if __name__ == "__main__":
    main()
