#!/bin/bash
# The test ROMs, outside git, freely distributable test programs of their authors (this repository does not
# carry them):
# - nes-test-roms (blargg cpu / ppu / apu tests, mmc3_test, ...) into ../build/nes-test-roms at a fixed commit;
# - Holy Mapperel v0.02 (tepples: mapper detection and bank / RAM tests, one ROM per board) into
#   ../build/nes-test-roms/holy-mapperel, so that tests.txt names its ROMs the same way. Needs 7z;
# - synth/: ROMs made from them for the loader (a trainer in front of 01-basics; two it must refuse).
set -e
cd "$(dirname "$0")"
URL=https://github.com/christopherpow/nes-test-roms.git
REV=95d8f621ae55cee0d09b91519a8989ae0e64753b
DIR=../build/nes-test-roms
if [ ! -d "$DIR/.git" ]; then
	git clone -q "$URL" "$DIR"
fi
git -C "$DIR" fetch -q origin "$REV" 2>/dev/null || true
git -C "$DIR" checkout -q "$REV"
echo "$DIR at $(git -C "$DIR" log -1 --format=%h)"

HM=$DIR/holy-mapperel
HM_URL=https://github.com/pinobatch/holy-mapperel/releases/download/v0.02/holy-mapperel-bin-0.02.7z
HM_SHA=70f85671e21f293599baebb662faeb06a4c04e9c9ceb283d96d4197f09e4ce7a
if [ ! -d "$HM/testroms" ]; then
	mkdir -p "$HM"
	curl -sL -o "$HM/hm.7z" "$HM_URL"
	echo "$HM_SHA  $HM/hm.7z" | sha256sum -c --quiet
	7z x -y -o"$HM" "$HM/hm.7z" > /dev/null
	rm "$HM/hm.7z"
fi
echo "$HM: $(ls "$HM/testroms" | grep -c '\.nes$') ROMs"

# a trainer (iNES byte 6 bit 2, 512 bytes before the PRG ROM): GameLoader writes it to $7000 and loads the game
mkdir -p "$DIR/synth"
python3 -I - "$DIR" <<'PY'
import sys
d = sys.argv[1]
rom = open(d + "/instr_test-v5/rom_singles/01-basics.nes", "rb").read()
h = bytearray(rom[:16]); h[6] |= 4
open(d + "/synth/01-basics-trainer.nes", "wb").write(bytes(h) + bytes(range(256)) * 2 + rom[16:])
# files the loader must refuse (check_loader.py): no "NES<1A>", and a NES 2.0 PRG ROM of 4 MB (256 x 16 KB)
open(d + "/synth/refuse-header.nes", "wb").write(b"NEZ\x1a" + rom[4:])
h = bytearray(rom[:16]); h[4] = 0; h[7] = (h[7] & 0xF3) | 0x08; h[9] = 0x01
open(d + "/synth/refuse-prg4m.nes", "wb").write(bytes(h) + rom[16:])
PY
echo "$DIR/synth: $(ls "$DIR/synth" | wc -l) ROMs"
