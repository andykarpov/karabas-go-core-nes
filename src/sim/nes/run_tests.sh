#!/bin/bash
# Runs the test ROMs of tests.txt on sim_nes, in parallel, and compares each result with the expected one.
#
#   run_tests.sh               all tests of tests.txt (needs fetch_roms.sh once; builds sim_nes)
#   run_tests.sh PATTERN       the tests whose ROM path matches PATTERN (grep -E)
#   run_tests.sh -q [PATTERN]  quick: the blargg protocol tests of up to 300 frames (53, about 4 minutes)
#   JOBS=4 run_tests.sh        parallel jobs (default: the number of CPUs)
#
# tests.txt, one test per line: <rom path in nes-test-roms> <max frames> <expected>
#   expected: the blargg result code (0 = passed) or "timeout" (no result within the frames);
#   or hash:XXXXXXXX for the ROMs that show their result on the screen only (the older blargg tests, games):
#   the hash of the palette indices of frame <max frames> (sim_nes --hash; ../build/nes/results/<rom>.ppm to
#   look at). # comments, also after the three fields.
# A test that gives another result than expected is reported as REGRESSION (worse) or CHANGED (it now
# passes: update tests.txt). Prints "run_tests: N tests, M unexpected" and exits 1 when M > 0.
# The output of each run is in ../build/nes/results/<rom>.log.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
ROMS=$HERE/../build/nes-test-roms
OUT=$HERE/../build/nes/results
QUICK=0
[ "$1" = -q ] && { QUICK=1; shift; }
[ -d "$ROMS" ] || { echo "no test ROMs: run fetch_roms.sh"; exit 1; }
./build.sh > /dev/null
mkdir -p "$OUT"
SIM=$HERE/../build/nes/obj/sim_nes

run_one() {
	rom=$1; frames=$2; expected=$3
	log=$OUT/$(echo "$rom" | tr / _).log
	# $readmemh of ppu.v reads oam_palette.txt from the current directory
	case "$expected" in
	hash:*)
		( cd "$HERE/../../rtl/nes" && "$SIM" "$ROMS/$rom" --hash --frames "$frames" --ppm "${log%.log}.ppm" > "$log" 2>&1 ) && code=0 || code=$?
		result=$(sed -n 's/^frame hash \([0-9a-f]*\)$/hash:\1/p' "$log")
		[ -n "$result" ] || result="error($code)"
		text=
		# a different picture: better or worse is for a person to see in the .ppm
		if [ "$result" = "$expected" ]; then status=ok; else status=CHANGED; fi
		;;
	*)
		( cd "$HERE/../../rtl/nes" && "$SIM" "$ROMS/$rom" --blargg --frames "$frames" > "$log" 2>&1 ) && code=0 || code=$?
		line=$(grep -m1 ': frames [0-9]*, result' "$log")
		result=$(echo "$line" | sed -n 's/.*result \(timeout \)\?\(-\?[0-9]*\)$/\1\2/p')
		case "$result" in "timeout -1") result=timeout ;; "") result="error($code)" ;; esac
		text=$(sed -n '/: frames [0-9]*, result/,$p' "$log" | sed -n '2,$p' | grep -v '^$' | sed -n '2p' | cut -c1-60)
		if [ "$result" = "$expected" ]; then status=ok
		elif [ "$result" = 0 ]; then status=CHANGED
		else status=REGRESSION; fi
		;;
	esac
	printf "%-10s %-62s %-8s (expected %s) %s\n" "$status" "$rom" "$result" "$expected" "$text"
}
export -f run_one
export ROMS OUT SIM HERE

grep -v '^\s*#' tests.txt | grep -v '^\s*$' | awk -v q=$QUICK '!q || ($2 <= 300 && $3 !~ /^hash:/)' | { if [ -n "$1" ]; then grep -E "$1"; else cat; fi; } |
	xargs -P "${JOBS:-$(nproc)}" -L 1 bash -c 'run_one "$@"' _ | sort -k2 > "$OUT/summary.txt"
cat "$OUT/summary.txt"
n=$(wc -l < "$OUT/summary.txt")
bad=$(grep -cv '^ok ' "$OUT/summary.txt" || true)
echo "run_tests: $n tests, $bad unexpected"
[ "$bad" = 0 ]
