#!/usr/bin/env python3
"""Makes rtl/karabas_mini_top.v and rtl/karabas_go_top.v from rtl/karabas_minig_top.v (link v2).

The NES, kg_mcu2 (the .sav of kg_bk_ram), the l2 OSD and the clocks are the same on the three
boards; the header and ports come from the last v1 tops (V1_REF), the pin glue differs:
Mini (before rev.G): MCU_IO of 4 bits (INT on MCU_IO[1]; E7 is FT_CLK_OUT, MCU_IO<4> before),
  sigma-delta audio of the NES + ADC mix on AUDIO_L / AUDIO_R, ESP / FT_RESET / MIDI pins
  inactive, HDMI as Mini G.
Go: INT on MCU_SPI_IO[0] (N9), the FT / SD2 selects on MCU_SPI_*_CS_N, VGA with the OSD and V_CLK
  (no HDMI, no DCM, no FT_CLK_OUT, no ADC), DAC_LRCK / DAC_MUTE, the floppy outputs idle.
Every replacement must match once, else this stops.
"""
import os
import subprocess
import sys

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RTL = os.path.join(SRC, "rtl")
V1_REF = "704ca45"  # master before link v2


def sub(s, old, new, what):
    if s.count(old) != 1:
        sys.exit("mktops.py: %s: %d matches of %r" % (what, s.count(old), old[:70]))
    return s.replace(old, new)


def cut(s, start, end, new, what):
    """replace from the line that starts with start up to and including end (after start)"""
    if s.count(start) != 1:
        sys.exit("mktops.py: %s: %d matches of %r" % (what, s.count(start), start[:70]))
    i = s.index(start)
    j = s.index(end, i) + len(end)
    return s[:i] + new + s[j:]


def v1(board):
    return subprocess.check_output(["git", "show", "%s:src/rtl/karabas_%s_top.v" % (V1_REF, board)],
                                   cwd=SRC).decode()


def head(s):
    i = s.index("module karabas_")
    return s[:s.index("\n);\n", i) + 4]


def body(s):
    i = s.index("module karabas_")
    return s[s.index("\n);\n", i) + 4:]


MCU_IO_G = "assign MCU_IO[1] = mcu_int;\nassign MCU_IO[0] = 1'bz;\nassign MCU_IO[5:2] = 4'bzzzz;"
NOTE = "// karabas: made by src/tools/mktops.py from karabas_minig_top.v (do not edit it, change Mini G)\n"

minig = open(os.path.join(RTL, "karabas_minig_top.v")).read()
b = body(minig)

# ---------------------------------------------------------------- Mini
m = b
m = sub(m, "assign ESP32_SPI_CS_N = 1'b1;\n", "assign ESP_RESET_N = 1'bZ;\nassign ESP_BOOT_N = 1'bZ;\n", "mini esp")
m = sub(m, "assign MIDI_TX = 1'b1;\n", "assign MIDI_TX = 1'b1;\nassign MIDI_CLK = 1'b1;\nassign MIDI_RESET_N = 1'b1;\nassign FT_RESET = 1'b1;\n", "mini midi")
m = sub(m, MCU_IO_G, "assign MCU_IO[1] = mcu_int;\nassign MCU_IO[0] = 1'bz;\nassign MCU_IO[3:2] = 2'bzz;", "mini mcu_io")
m = cut(m, "kg_pcm5102 PCM5102(", ");", """// Mini has no I2S DAC: sigma-delta outputs into an RC filter, the mix of the NES and the ADC
kg_sigma_delta_dac dac_l(.clk(clk), .reset(areset), .din({2'b00, !audio_mix_l[15], audio_mix_l[14:4], 2'b00}), .dout(AUDIO_L));
kg_sigma_delta_dac dac_r(.clk(clk), .reset(areset), .din({2'b00, !audio_mix_r[15], audio_mix_r[14:4], 2'b00}), .dout(AUDIO_R));""", "mini dac")
h = head(v1("mini"))
h = sub(h, "	inout wire [4:0] MCU_IO, // [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n, [4] ft clk (mod): input only",
        "	inout wire [3:0] MCU_IO, // [1] INT of link v2, [2] sd2 cs_n, [3] ft cs_n", "mini port mcu_io")
h = sub(h, "	output wire FT_RESET,", "	output wire FT_RESET,\n	output wire FT_CLK_OUT,", "mini port ft clk")
mini = h + NOTE + m

# ---------------------------------------------------------------- Go
g = b
g = sub(g, "assign ESP32_SPI_CS_N = 1'b1;\n", """assign ESP_RESET_N = 1'bZ;
assign ESP_BOOT_N = 1'bZ;
assign BEEPER = 1'b0;
assign FT_OE_N = 1'b1;
assign FDC_DRIVE = 2'b00;
assign FDC_MOTOR = 1'b0;
assign FDC_DIR = 1'b0;
assign FDC_STEP = 1'b0;
assign FDC_WDATA = 1'b0;
assign FDC_WGATE = 1'b0;
assign FDC_SIDE_N = 1'b1;
""", "go pins")
g = sub(g, "assign MIDI_TX = 1'b1;\n", "assign MIDI_TX = 1'b1;\nassign MIDI_CLK = 1'b1;\nassign MIDI_RESET_N = 1'b1;\n", "go midi")
g = sub(g, "wire locked, lockedx5;", "wire locked;", "go locked")
g = sub(g, "wire clk_hdmi, clk_hdmi_n;\n", "", "go hdmi clk decl")
g = cut(g, "// the clock of the FT812 (925 / 115", "ODDR2 oddr_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8), .C1(~clk_8), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));",
        "// Go has no FT_CLK_OUT", "go ft clk")
g = cut(g, "// hdmi serial clock: 5 x clk_vga and its inverse", ".locked(lockedx5)\n);", "// no HDMI on Go", "go dcm")
g = sub(g, MCU_IO_G, "// Go: INT on MCU_SPI_IO[0] (N9, the IO1 line of the firmware)\nassign MCU_SPI_IO[0] = mcu_int;\nassign MCU_SPI_IO[1] = 1'bz;", "go mcu_io")
g = sub(g, ".MCU_SPI_FT_SS(MCU_IO[3]),", ".MCU_SPI_FT_SS(MCU_SPI_FT_CS_N),", "go ft ss")
g = sub(g, ".MCU_SPI_SD2_SS(MCU_IO[2]),", ".MCU_SPI_SD2_SS(MCU_SPI_SD2_CS_N),", "go sd2 ss")
g = sub(g, "	.lrck(DAC_WS)\n);", "	.lrck(DAC_LRCK)\n);\nassign DAC_MUTE = 1'b1; // soft mute, 0 = mute, 1 = unmute", "go dac")
g = cut(g, "// ------- PCM1808 ADC ---------", "assign audio_mix_r = audio_out_r[15:0] + adc_r[23:8];", "// no ADC on Go", "go adc")
g = sub(g, "wire [31:0] audio_mix_l, audio_mix_r;\n", "", "go mix decl")
i = g.index("// ------------ HDMI ----------------")
j = g.index("endmodule", i)
g = g[:i] + """// ------------ VGA ----------------

assign VGA_R = osd_r;
assign VGA_G = osd_g;
assign VGA_B = osd_b;
assign VGA_HS = osd_hs;
assign VGA_VS = osd_vs;
ODDR2 oddr_v_clk (.Q(V_CLK), .C0(clk_vga), .C1(~clk_vga), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

""" + g[j:]
go = head(v1("go")) + NOTE + g

open(os.path.join(RTL, "karabas_mini_top.v"), "w").write(mini)
open(os.path.join(RTL, "karabas_go_top.v"), "w").write(go)
print("mktops.py: karabas_mini_top.v, karabas_go_top.v")
