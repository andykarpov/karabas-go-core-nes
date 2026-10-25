# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

The NES core (FPGANES by strigeus, through its ZXDOS+ port) for the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25, ISE 14.7 (XST). One core, three tops: `src/rtl/karabas_go_top.v` (VGA, PCM5102), `karabas_mini_top.v` (HDMI, sigma-delta audio, PCM1808 ADC), `karabas_minig_top.v` (HDMI, PCM5102). The NES itself is `src/rtl/nes/nes.v` (it includes `cpu.v`, `apu.v`, `ppu.v`, `mmu.v`; `cpu.v` includes `MicroCode.v`), the game is written into the SRAM by `GameLoader.v` from the file loader of the MCU link, `memorycontroller.v` maps PRG / CHR ROM to the SRAM and CPU RAM, VRAM and PRG RAM to block RAM.

The plan of the work on this core (mappers from MiSTer, `.sav` saves, save states) is `docs/PLAN.md` (Russian). Follow its phases; update it when a decision changes. `docs/UPSTREAM.md`: the inventory of NES_MiSTer / MiST nes (files, languages, the save state bus, what `sv2v` and XST make of them); the clones go to `src/sim/build/upstream`, outside git. `src/tools/upstream/fix_wire_reg.py` fixes one class of `sv2v` output for XST.

The board modules (MCU link, memories, clocks, DACs) come from the git submodule `modules/` ([karabas-go-modules](https://github.com/andykarpov/karabas-go-modules), shared by the Karabas Go cores; clone with `--recursive` or run `git submodule update --init`). A change to them is made there and taken here by updating the submodule commit. Its `CLAUDE.md` and `docs/PLAN.md` have the rules (Verilog-2001 for XST, no coregen, tests, checks of LUTs and timing).

## Build

- `cd src && make` builds the three boards (`make go`, `mini`, `minig` one of them; `make minig-xst`, `-impl`, `-core` one step; `make minig-report` the utilization and timing of the last build). It runs the ISE command-line flow (the steps and options of the former ISE projects) and sources `/opt/Xilinx/14.7/ISE_DS/settings64.sh` (`ISE_SETTINGS=` to change it). The boards share `xst/` and `_ngo/` in `src/`, so they are built one after the other.
- Inputs per board: `karabas_<board>_top.prj` (the source list, add new files here; the shared modules as `"../modules/rtl/..."`), `karabas_<board>_top.xst`, `karabas_<board>_top.ut`, `karabas_<board>.ucf`. Files included by others (`cpu.v`, `apu.v`, `ppu.v`, `mmu.v`, `MicroCode.v`) and init files are not in the prj; they are in `INCLUDES` of the Makefile. There is no ISE GUI project (`.xise`) and no `ipcore_dir` any more.
- `core` packs `karabas_<board>_top.bin` with `core.json` (Go), `core_mini.json`, `core_minig.json` into `nes.kg1` / `kg2` / `kg3` with `make_core.py`, a symlink to karabas-go-tools (the sibling repo must be checked out next to this one). The `.bin` and `.kg*` files are committed as the release.
- Check `karabas_<board>_top_map.mrp` (LUTs, slices, block RAMs) and `karabas_<board>_top.par` (timing) after a change; `make <board>-report` prints both.
- Init files of memories are read by XST relative to `src/` (`INIT_FILE` of `kg_sdpram`: `"rtl/osd/osd_font.hex"`).

## Timing

- The three ucf have the same timing block (the end of each file): PERIOD on CLK_50MHZ, derived onto the PLL outputs (`pll_clk<0>` = clk 21.51 MHz, `pll_clk<1>` = clk_vga 25.0 MHz) and the HDMI DCM (5x clk_vga and its inverse); `TS_CLK_MCU` 32 MHz; FROM-TO DATAPATHONLY on the asynchronous crossings (clk <-> clk_vga one clk_vga period, MCU_SCK <-> clk one SCK period); the SRAM budget (20 ns out + 10 ns tAA + 20 ns in of the three clk of a MemoryController access). Each exception is explained there; do not TIG paths that are real.
- A signal of clk that the HDMI serialisers use (the encoder select `dvi_only`) goes through `kg_sync` into clk_vga first: from clk it reaches the 5x clock with the phase of two unrelated dividers of one VCO.

## Simulation

- `src/sim/nes` (verilator): `nes_system` of the tops with a model of the SRAM runs a `.nes` file; the game goes in through `GameLoader` as from the mcu. `fetch_roms.sh` once (nes-test-roms at a fixed commit into `src/sim/build/`, not in git), then `run_tests.sh [-q] [PATTERN]` runs the ROMs of `tests.txt` in parallel against their expected results (`-q`: the 53 short protocol tests, about 4 minutes on 8 cores; all of them about 35 minutes) (screen-only tests and games: `hash:` of a frame, the `.ppm` in `src/sim/build/nes/results` to look at; the blargg protocol: `$6001..3` = DE B0 61, `$6000` the result, `$81` = press reset, the text from `$6004`; read from the CPU writes on the bus, so it works with mappers without PRG RAM here). A change that makes a test pass updates `tests.txt`; one that makes it fail is a regression. `build.sh` builds `sim_nes` alone; `sim_nes game.nes --frames N --ppm out.ppm --hash --joy F:BITS` for screenshots and games. 5-7 frames per second per process (the whole design is evaluated every 21.5 MHz clock; verilator threads and -O3 do not help), so each test has its own frame limit; run it from `src/rtl/nes` (`ppu.v` reads `oam_palette.txt` from the current directory, `run_tests.sh` does that).
- `src/sim/run_burst_sim.sh` (ISim): `tb_mcu_burst.vhd`, the CMD_CAPS answer and the rom and file loaders over classic frames and bursts at 16 / 32 MHz, `kg_mcu` with the parameters of the tops.
- `src/sim/ref/ipcore`: the coregen models of the removed `ipcore_dir`, used by `modules/sim/ipcore_eq` to check the `kg_*` memories and clocks against them.
- The tests of the shared modules are in `modules/sim` (`run_all.sh`).

## Layout

- `src/rtl/karabas_*_top.v`: board glue, clocks (`kg_pll`; `kg_dcm` for HDMI), MCU link (`kg_mcu`: file loader with the FILE* commands, FT812 and SD2 chip selects passed through, file mounter on for the saves of `docs/PLAN.md`), soft switches (`kg_soft_switches`: register 0 bit 0 = reset), audio (`kg_pcm5102` / `kg_sigma_delta_dac`), joypads.
- `src/rtl/nes_system.v`: the NES part of the three tops (game loader, NES, memory controller, joypads), also the unit the simulation runs.
- `src/rtl/nes`: the NES, `GameLoader.v` (iNES), `memorycontroller.v` (SRAM `MA[18:0]`, `kg_spram` for RAM / VRAM / PRG RAM).
- `src/rtl/mcu/hid_parser.vhd`: keyboard and joysticks to the NES joypads.
- `src/rtl/osd`: the OSD of this core (`overlay.vhd`, two clocks: commands on clk, video on clk_vga; `kg_sdpram` for its font and text, `osd_font.hex` from `osd_font.coe` by `modules/tools/coe2hex.py`), `pix_dobler.vhd` (falling edge, not the `pix_doubler` of modules).
- `src/rtl/vga/vga.vhd`: 640x480 output with the frame buffer (`kg_sdpram` 64K x 6, NES palette index).
- `src/rtl/hdmi`: the HDMI / DVI encoders of the Mini / Mini G.
