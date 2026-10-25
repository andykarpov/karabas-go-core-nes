`timescale 1ns / 1ps
`default_nettype wire

/*
 nes_system.v

 The NES of the three tops: the game loader (iNES from the file loader of the mcu), the NES (CPU, PPU,
 APU, mapper; clocked by every 4th clk, nes_ce), the memory controller (PRG / CHR ROM in the SRAM, CPU
 RAM, VRAM and PRG RAM in block RAM) and the joypad shift registers. The simulation (src/sim/nes) runs
 the same module with a model of the SRAM.
*/

module nes_system (
	input wire clk,
	input wire reset,              // soft switch reset

	// game file from the mcu file loader
	input wire loader_reset,
	input wire [7:0] loader_data,
	input wire loader_wr,
	output wire loader_done,
	output wire loader_fail,
	output wire [15:0] debug_data,

	// joypads: A, B, Select, Start, Up, Down, Left, Right in bits 0..7, 1 = pressed
	input wire [7:0] joy_l,
	input wire [7:0] joy_r,

	// video, audio
	output wire [5:0] color,       // palette index of the pixel (cycle, scanline)
	output wire [8:0] cycle,
	output wire [8:0] scanline,
	output wire [15:0] sample,     // two's complement

	// SRAM, the low byte lane
	output wire [18:0] MA,
	inout wire [7:0] MD,
	output wire MWR_N
);

wire [21:0] memory_addr;
wire memory_read_cpu, memory_read_ppu;
wire memory_write;
wire [7:0] memory_din_cpu, memory_din_ppu;
wire [7:0] memory_dout;
wire [31:0] dbgadr;
wire [1:0] dbgctr;

wire joypad_strobe;
wire [1:0] joypad_clock;
reg [7:0] joypad_bits, joypad_bits2;
reg [1:0] last_joypad_clock;

reg [1:0] nes_ce;

// --------------- Loader

wire [21:0] loader_addr;
wire [7:0] loader_write_data;
wire loader_write;
wire [31:0] mapper_flags;

  GameLoader loader(
    clk,
    loader_reset,
	 loader_data,
	 loader_wr,
	 loader_addr,
	 loader_write_data,
	 loader_write,
	 mapper_flags,
	 loader_done,
	 loader_fail,
	 debug_data
	);

  wire reset_nes = (reset || !loader_done);
  wire run_mem = (nes_ce == 0) && !reset_nes;
  wire run_nes = (nes_ce == 3) && !reset_nes;

  // NES is clocked at every 4th cycle.
  always @(posedge clk)
    nes_ce <= nes_ce + 1;

  NES nes(clk, reset_nes, run_nes,
          mapper_flags,
          sample, color,
          joypad_strobe, joypad_clock, {joypad_bits2[0], joypad_bits[0]},
          5'b11111, // sw
          memory_addr,
          memory_read_cpu, memory_din_cpu,
          memory_read_ppu, memory_din_ppu,
          memory_write, memory_dout,
          cycle, scanline,
          dbgadr,
          dbgctr
   );

  // This is the memory controller to access the board's SRAM
  wire ram_busy;
  reg [13:0] debugaddr;
  wire [15:0] debugdata;

  MemoryController  memory( clk,
                            memory_read_cpu && run_mem,
                            memory_read_ppu && run_mem,
                            memory_write && run_mem || loader_write,
                            loader_write ? loader_addr : memory_addr,
                            loader_write ? loader_write_data : memory_dout,
                            memory_din_cpu, memory_din_ppu, ram_busy,
                            MWR_N, MA, MD,
                            debugaddr, debugdata);

  reg ramfail;
  always @(posedge clk) begin
    if (loader_reset)
      ramfail <= 0;
    else
      ramfail <= ram_busy && loader_write || ramfail;
  end

  always @(posedge clk) begin
	if (joypad_strobe) begin
		joypad_bits <= joy_l;
		joypad_bits2 <= joy_r;
	end

	if (!joypad_clock[0] && last_joypad_clock[0]) begin
		joypad_bits <= {1'b0, joypad_bits[7:1]};
	end
	if (!joypad_clock[1] && last_joypad_clock[1]) begin
		joypad_bits2 <= {1'b0, joypad_bits2[7:1]};
	end
	last_joypad_clock <= joypad_clock;
  end

endmodule
