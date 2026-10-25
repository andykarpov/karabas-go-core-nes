`timescale 1ns / 1ps
`default_nettype wire

/*
 nes_system.v

 The NES of the three tops: the game loader (iNES from the file loader of the mcu), the NES (CPU, PPU,
 APU, mapper; clocked by every 4th clk, nes_ce), the memory controller (the 4 MB SRAM: PRG / CHR ROM,
 PRG RAM; CPU RAM and VRAM in block RAM; see memorycontroller.v) and the joypad shift registers. The
 simulation (src/sim/nes) runs the same module with a model of the SRAM.
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

	// SRAM, 2M x 16 (/OE tied low by the tops)
	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N
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
reg aux_req = 1'b0;

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

  // (the last byte of the loader may still wait for its slot when it says done)
  wire reset_nes = (reset || !loader_done || aux_req);
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

  // the loader writes through the aux port of the memory controller: a byte held until the controller took it
  reg [21:0] aux_addr = 22'd0;
  reg [7:0] aux_din = 8'd0;
  wire aux_ack;
  reg ramfail = 1'b0; // a loader byte came before the one before it was written (not seen at the speed of the mcu)
  always @(posedge clk) begin
    if (aux_ack)
      aux_req <= 1'b0;
    if (loader_write) begin
      aux_req <= 1'b1;
      aux_addr <= loader_addr;
      aux_din <= loader_write_data;
    end
    if (loader_reset)
      ramfail <= 1'b0;
    else if (loader_write && aux_req && !aux_ack)
      ramfail <= 1'b1;
  end

  MemoryController memory(
    .clk(clk), .phase(nes_ce),
    .read_a(memory_read_cpu && run_mem), .read_b(memory_read_ppu && run_mem), .write(memory_write && run_mem),
    .addr(memory_addr), .din(memory_dout), .dout_a(memory_din_cpu), .dout_b(memory_din_ppu),
    .aux_req(aux_req), .aux_we(1'b1), .aux_addr(aux_addr), .aux_din(aux_din), .aux_ack(aux_ack), .aux_dout(),
    .MA(MA), .MD(MD), .MWR_N(MWR_N));

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
