#!/bin/bash
# Runs the ROMs of a test list on sim_nes, in parallel, and compares each result with the expected one.
#
#   run_tests.sh               all tests of tests.txt (needs fetch_roms.sh once; builds sim_nes)
#   run_tests.sh PATTERN       the tests whose ROM path matches PATTERN (grep -E)
#   run_tests.sh -q [PATTERN]  quick: the blargg protocol tests of up to 300 frames (53, about 4 minutes)
#   run_tests.sh -g [PATTERN]  the games of games.txt, from $NES_GAMES (default ~/Downloads; not in git)
#   JOBS=4 run_tests.sh        parallel jobs (default: the number of CPUs)
#   TESTS=list.txt run_tests.sh  another list of nes-test-roms ROMs
#
# A list has one test per line: <rom> <max frames> <expected> [joy=F:BITS,F:BITS...], the fields separated by
# blanks, or by "|" when the ROM path has blanks (games). The ROM path is relative to the ROM directory
# (nes-test-roms, or $NES_GAMES with -g). "#" starts a comment (a whole line, or " # ..." after the fields).
#   expected: the blargg result code (0 = passed) or "timeout" (no result within the frames);
#   or hash:XXXXXXXX for the ROMs that show their result on the screen only (the older blargg tests, games):
#   the hash of the palette indices of frame <max frames> (sim_nes --hash; ../build/nes/results/<rom>.ppm to
#   look at).
#   joy: joypad 1 from frame F on (sim_nes --joy), e.g. joy=400:08,410:00 presses Start for 10 frames.
#   before=ROM:N (after joy, or in its place): run ROM (of the same directory) N frames first, then load the
#   test ROM over it (sim_nes --before), as a game chosen after another one on the board.
# A test that gives another result than expected is reported as REGRESSION (worse) or CHANGED (it now passes,
# or another picture: update the list). Prints "run_tests: N tests, M unexpected" and exits 1 when M > 0.
# The output of each run is in ../build/nes/results/<rom>.log (and .ppm).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
ROMS=$HERE/../build/nes-test-roms
LIST=${TESTS:-tests.txt}
OUT=$HERE/../build/nes/results
QUICK=0
case "$1" in
-q) QUICK=1; shift ;;
-g) LIST=games.txt; ROMS=${NES_GAMES:-$HOME/Downloads}; shift ;;
esac
[ -d "$ROMS" ] || { echo "no ROM directory $ROMS (fetch_roms.sh, or NES_GAMES for -g)"; exit 1; }
./build.sh > /dev/null
mkdir -p "$OUT"
SIM=$HERE/../build/nes/obj/sim_nes

run_one() {
	line=${1%% \#*}
	if [[ "$line" == *"|"* ]]; then IFS='|' read -r rom frames expected joy before <<< "$line"
	else read -r rom frames expected joy before <<< "$line"; fi
	rom=$(echo "$rom" | sed 's/^ *//; s/ *$//'); frames=${frames// /}; expected=${expected// /}; joy=${joy// /}
	before=$(echo "$before" | sed 's/^ *//; s/ *$//')
	if [[ "$joy" == before=* ]]; then before=${joy}; joy=; fi
	joyargs=()
	if [ -n "$joy" ]; then
		for j in $(echo "${joy#joy=}" | tr , ' '); do joyargs+=(--joy "$j"); done
	fi
	if [ -n "$before" ]; then joyargs+=(--before "$ROMS/${before#before=}"); fi
	log=$OUT/$(echo "$rom" | tr '/ ' '__')${before:+_after_$(basename "${before#before=}" | tr ' ' _)}.log
	# $readmemh of ppu.v reads oam_palette.txt from the current directory
	case "$expected" in
	hash:*)
		( cd "$HERE/../../rtl/nes" && "$SIM" "$ROMS/$rom" --hash --frames "$frames" --ppm "${log%.log}.ppm" "${joyargs[@]}" > "$log" 2>&1 ) && code=0 || code=$?
		result=$(sed -n 's/^frame hash \([0-9a-f]*\)$/hash:\1/p' "$log")
		[ -n "$result" ] || result="error($code)"
		text=
		# a different picture: better or worse is for a person to see in the .ppm
		if [ "$result" = "$expected" ]; then status=ok; else status=CHANGED; fi
		;;
	*)
		( cd "$HERE/../../rtl/nes" && "$SIM" "$ROMS/$rom" --blargg --frames "$frames" "${joyargs[@]}" > "$log" 2>&1 ) && code=0 || code=$?
		line=$(grep -m1 ': frames [0-9]*, result' "$log")
		result=$(echo "$line" | sed -n 's/.*result \(timeout \)\?\(-\?[0-9]*\)$/\1\2/p')
		case "$result" in "timeout -1") result=timeout ;; "") result="error($code)" ;; esac
		text=$(sed -n '/: frames [0-9]*, result/,$p' "$log" | sed -n '2,$p' | grep -v '^$' | sed -n '2p' | cut -c1-60)
		if [ "$result" = "$expected" ]; then status=ok
		elif [ "$result" = 0 ]; then status=CHANGED
		else status=REGRESSION; fi
		;;
	esac
	printf "%-10s %-62s %-8s (expected %s) %s\n" "$status" "$rom${before:+ after $(basename "${before#before=}")}" "$result" "$expected" "$text"
}
export -f run_one
export ROMS OUT SIM HERE

grep -v '^\s*#' "$LIST" | grep -v '^\s*$' | sed 's/ #.*//' |
	awk -F'[ |]+' -v q=$QUICK '!q || ($2 <= 300 && $3 !~ /^hash:/)' |
	{ if [ -n "$1" ]; then grep -E "$1"; else cat; fi; } |
	xargs -d '\n' -P "${JOBS:-$(nproc)}" -I{} bash -c 'run_one "$1"' _ {} | sort -k2 > "$OUT/summary.txt"
cat "$OUT/summary.txt"
n=$(wc -l < "$OUT/summary.txt")
bad=$(grep -cv '^ok ' "$OUT/summary.txt" || true)
echo "run_tests: $n tests, $bad unexpected"
[ "$bad" = 0 ]
