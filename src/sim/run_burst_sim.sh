#!/bin/bash
# Simulate tb_mcu_burst.vhd with ISim (Xilinx ISE 14.7).
# Usage: src/sim/run_burst_sim.sh [path to ISE_DS/settings64.sh]

set -e
SETTINGS=${1:-/opt/Xilinx/14.7/ISE_DS/settings64.sh}
source "$SETTINGS" > /dev/null

cd "$(dirname "$0")"
RTL=../rtl
CLK_PS=46560 # mcu clock of this core: 21.477 MHz
mkdir -p build
cd build

vhpcomp -work work ../$RTL/spi/spi_slave.vhd ../$RTL/mcu/burst_rx.vhd ../$RTL/mcu/mcu.vhd ../tb_mcu_burst.vhd
echo "run 2 ms; quit" > run.tcl

# bursts at 16 MHz (BURST_MAX_MHZ 0) and at 32 MHz (BURST_MAX_MHZ 32, Mini G); classic frames stay at 16 MHz
run_case() {
	name=$1; shift
	fuse -top work.tb_mcu_burst -o tb_$name.exe -generic_top "CLK_PERIOD_PS=$CLK_PS" "$@" > fuse_$name.log
	./tb_$name.exe -tclbatch run.tcl > sim_$name.log
	grep -E "Note:" sim_$name.log | sed "s/^/[$name] /"
	if grep -q "Error:" sim_$name.log; then
		grep "Error:" sim_$name.log | head -5
		echo "SIMULATION FAILED ($name)"
		exit 1
	fi
	grep -q "tb_mcu_burst: finished" sim_$name.log || { echo "SIMULATION DID NOT FINISH ($name)"; exit 1; }
}
run_case 16mhz
run_case 32mhz -generic_top "BURST_SCK_HALF_PS=15625" -generic_top "MAX_MHZ=32"
echo "SIMULATION PASSED"
