#!/bin/bash
# Builds sim_nes (verilator) from nes_system of the tops into ../build/nes/obj/sim_nes.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
RTL=$HERE/../../rtl
M=$HERE/../../../modules/rtl
OUT=$HERE/../build/nes
mkdir -p "$OUT"
python3 -I "$HERE/gen_palette.py" "$RTL/vga/vga.vhd" "$OUT/nes_palette.h"
# the FPGANES sources warn a lot (widths, incomplete cases); errors still fail
verilator --cc --exe --build -j 0 -O3 --x-assign fast --x-initial unique --noassert \
	-Wno-fatal -Wno-lint -Wno-style -Wno-UNOPTFLAT -Wno-MULTIDRIVEN -Wno-COMBDLY -Wno-INITIALDLY \
	-I"$RTL/nes" -I"$RTL" -CFLAGS "-O2 -I$OUT" \
	--Mdir "$OUT/obj" -o sim_nes --top-module tb_nes \
	"$HERE/tb_nes.v" "$HERE/xilinx_prims.v" "$RTL/nes_system.v" "$RTL/nes/nes.v" "$RTL/nes/GameLoader.v" \
	"$RTL/nes/memorycontroller.v" "$M/mem/kg_spram.v" "$HERE/sim_nes.cpp" > "$OUT/verilator.log" 2>&1 \
	|| { grep -E "%Error|error:" "$OUT/verilator.log" | head -20; exit 1; }
echo "$OUT/obj/sim_nes"
