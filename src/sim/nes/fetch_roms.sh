#!/bin/bash
# The test ROMs (nes-test-roms: blargg cpu / ppu / apu tests, mmc3_test, holy mapperel, ...), outside git:
# into ../build/nes-test-roms at a fixed commit. They are freely distributable test programs of their
# authors; this repository does not carry them.
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
