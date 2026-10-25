#!/usr/bin/env python3
"""Checks GameLoader on .nes files: sim_nes --frames 0 loads each one; its CRC-32 must be zlib.crc32 of the
PRG and CHR ROM of the file and its mapper flags the fields of the header (the NES_MiSTer layout of
GameLoader.v). A file the loader must refuse (no header, PRG > 2 MB, CHR > 1 MB) must give a load error.

Usage: check_loader.py <sim_nes> <file or directory>...   (directories: their .nes files, recursively)
Prints "check_loader: N files, M errors"; exit 1 when M > 0.
"""
import os
import subprocess
import sys
import zlib


def expected(rom):
    h = rom[:16]
    if h[:4] != b"NES\x1a":
        return None
    nes20 = (h[7] & 0x0C) == 0x08
    dirty = not nes20 and any(h[8:16])
    prg_msb = h[9] & 0x0F if nes20 else 0
    chr_msb = h[9] >> 4 if nes20 else 0
    prg = ((h[4] & 3) * 2 + 1) << (h[4] >> 2) if prg_msb == 0xF else ((prg_msb << 8) | h[4]) * 16384
    chr_ = ((h[5] & 3) * 2 + 1) << (h[5] >> 2) if chr_msb == 0xF else ((chr_msb << 8) | h[5]) * 8192
    if prg > 0x200000 or chr_ > 0x100000:
        return None
    trainer = 512 if h[6] & 4 else 0
    body = rom[16 + trainer:16 + trainer + prg + chr_]
    prg_pages, chr_pages = prg // 16384, chr_ // 8192
    size = lambda n: next((i for i, m in enumerate((1, 2, 4, 8, 16, 32, 64)) if n <= m), 7)
    chr_ram = (h[11] & 0x0F) != 0 or chr_ == 0 if nes20 else chr_pages == 0
    mapper = (0 if dirty else h[7] & 0xF0) | (h[6] >> 4)
    f = mapper | size(prg_pages) << 8 | size(chr_pages) << 11 | (h[6] & 1) << 14 | int(chr_ram) << 15
    f |= (h[6] >> 3 & 1) << 16 | (h[8] << 17 if nes20 else 0) | (h[6] >> 1 & 1) << 25
    if nes20:
        f |= (h[10] & 0xF) << 26 | (h[10] >> 4) << 31 | 1 << 35 | (h[12] & 3) << 36 | (h[7] & 3) << 43
    return zlib.crc32(body), f


def main():
    sim, args = sys.argv[1], sys.argv[2:]
    files = []
    for a in args:
        if os.path.isdir(a):
            for d, _, fs in os.walk(a):
                files += [os.path.join(d, x) for x in sorted(fs) if x.lower().endswith(".nes")]
        else:
            files.append(a)
    errors = 0
    for f in files:
        exp = expected(open(f, "rb").read())
        out = subprocess.run([sim, f, "--frames", "0"], capture_output=True, text=True)
        text = out.stdout + out.stderr
        got = None
        for line in text.splitlines():
            if line.startswith("loaded: crc "):
                p = line.split()
                got = (int(p[2], 16), int(p[4], 16))
        if exp is None:
            ok = got is None and "load error" in text
            what = "refused" if ok else "not refused"
        else:
            ok = got == exp
            what = "crc %08x flags %016x" % got if got else "load failed"
        if not ok:
            errors += 1
            print("ERROR %s: %s, expected %s" % (f, what, "a load error" if exp is None else
                                                 "crc %08x flags %016x" % exp))
    print("check_loader: %d files, %d errors" % (len(files), errors))
    sys.exit(1 if errors else 0)


main()
