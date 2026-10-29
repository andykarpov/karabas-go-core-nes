`timescale 1ns / 1ps
`default_nettype wire

/*
 nes_system.v

 The NES of the three tops: the game loader (iNES from the file loader of the mcu), the NES (CPU, PPU,
 APU, mapper; clocked by every 4th clk, nes_ce), the memory controller (the 4 MB SRAM: PRG / CHR ROM,
 PRG RAM; CPU RAM and VRAM in block RAM; see memorycontroller.v) and the joypad shift registers. The
 simulation (src/sim/nes) runs the same module with a model of the SRAM.
 The backup RAM of a game with a battery (its PRG RAM at 0x3C0000) is kept in a .sav file on the sd card
 by kg_bk_ram on the file mounter of the mcu (img slot 0): loaded before the CPU starts, its written
 sectors saved back.
*/

module nes_system #(
	parameter BK_IDLE_CLOCKS = 27'd21500000,  // ~1 s at 21.5 MHz: save after the last write
	parameter BK_MAX_CLOCKS = 27'd86000000,   // ~4 s: at the latest after the first write
	parameter BK_MOUNT_CLOCKS = 27'd21500000, // ~1 s: no answer to CMD_BK_MOUNT, go on without a save
	parameter BK_GRACE_CLOCKS = 27'd215000    // ~10 ms: no file
) (
	input wire clk,
	input wire reset,              // soft switch reset

	// game file from the mcu file loader
	input wire loader_reset,
	input wire [7:0] loader_data,
	input wire loader_wr,
	output wire loader_done,
	output wire loader_fail,
	output wire [63:0] mapper_flags, // of the game (GameLoader, NES_MiSTer layout)
	output wire [31:0] rom_crc,      // CRC-32 of its PRG and CHR ROM
	output wire [15:0] debug_data,

	// the file mounter of kg_mcu (ENABLE_IMG, ENABLE_BK): the .sav file in img slot 0
	input wire [7:0] img_mounted,
	input wire [63:0] img_size,
	input wire img_data_wr,
	input wire [8:0] img_data_addr,
	input wire [7:0] img_data,
	input wire img_result_wr,
	input wire [7:0] img_result,
	input wire [15:0] img_sum,
	input wire [7:0] img_flush,
	output wire img_q_wr,
	output wire [23:0] img_q_di,
	input wire img_q_ack,
	output wire bk_mounted,        // the game has a .sav file
	output wire bk_saving,         // a sector of it is being written
	output wire bk_error,          // a write of it failed

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
// mapper_flags: the layout of NES_MiSTer (MultiMapper uses bits 16:0, the mappers of rtl/cart all)
wire loader_trainer;
wire [9:0] prg_mask, chr_mask;     // for the mappers of NES_MiSTer
reg aux_req = 1'b0;
reg clear_done = 1'b0;

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
	 loader_trainer,
	 rom_crc,
	 prg_mask,
	 chr_mask,
	 debug_data
	);

  // (the last byte of the loader may still wait for its slot when it says done; then the RAMs are cleared,
  // then the backup RAM is loaded)
  wire bk_busy;
  wire reset_nes = (reset || !loader_done || aux_req || !clear_done || bk_busy);
  wire run_mem = (nes_ce == 0) && !reset_nes;
  wire run_nes = (nes_ce == 3) && !reset_nes;

  // NES is clocked at every 4th cycle.
  always @(posedge clk)
    nes_ce <= nes_ce + 1;

  NES nes(clk, reset_nes, run_nes,
          mapper_flags, prg_mask, chr_mask,
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

  // the loader writes through the aux port of the memory controller: a byte held until the controller took it.
  // After the game is in, the PRG RAM (0x3C0000, 32 KB, but the trainer at 0x3C1000), the mapper RAM (0x3FE000,
  // 8 KB), the VRAM and the CPU RAM (block RAM, 2 KB each) are cleared to 0, as NES_MiSTer does with RAM Clear
  // $00: the SRAM starts with junk, and the block RAMs keep what the game before left there (some games hang
  // on it, as Tetris after Contra).
  reg [21:0] aux_addr = 22'd0;
  reg [7:0] aux_din = 8'd0;
  wire aux_ack;
  reg ramfail = 1'b0; // a loader byte came before the one before it was written (not seen at the speed of the mcu)
  reg [15:0] clear_ctr = 16'd0; // 0-32767 PRG RAM, 32768-40959 mapper RAM, -43007 VRAM, -45055 CPU RAM
  wire [21:0] clear_addr = !clear_ctr[15] ? {7'b11_1100_0, clear_ctr[14:0]} :
                           !clear_ctr[13] ? {9'b11_1111_111, clear_ctr[12:0]} :
                           !clear_ctr[11] ? {11'b11_0000_0000_0, clear_ctr[10:0]} :
                                            {11'b11_1000_0000_0, clear_ctr[10:0]};
  wire clear_skip = loader_trainer && clear_ctr[15:9] == 7'b0000_100; // 0x1000-0x11FF: the trainer
  always @(posedge clk) begin
    if (aux_ack)
      aux_req <= 1'b0;
    if (loader_write) begin
      aux_req <= 1'b1;
      aux_addr <= loader_addr;
      aux_din <= loader_write_data;
    end
    if (loader_reset) begin
      ramfail <= 1'b0;
      clear_ctr <= 16'd0;
      clear_done <= 1'b0;
    end
    else begin
      if (loader_write && aux_req && !aux_ack)
        ramfail <= 1'b1;
      if (loader_done && !clear_done && !aux_req && !loader_write) begin
        if (!clear_skip) begin
          aux_req <= 1'b1;
          aux_addr <= clear_addr;
          aux_din <= 8'h00;
        end
        clear_ctr <= clear_ctr + 1'd1;
        if (clear_ctr == 16'd45055)
          clear_done <= 1'b1;
      end
    end
  end

  // --------------- Backup RAM
  // the size: the PRG NVRAM of an NES 2.0 header (64 << n bytes, at least a sector, at most the 32 KB of
  // the PRG RAM), else 8 KB with the battery bit
  wire [3:0] nvram_shift = mapper_flags[34:31];
  wire [6:0] nvram_sectors = nvram_shift <= 4'd9 ? 7'd1 : nvram_shift >= 4'd15 ? 7'd64 : 7'd1 << (nvram_shift - 4'd9);
  wire [6:0] bk_size = !mapper_flags[25] ? 7'd0 : (mapper_flags[35] && nvram_shift != 0) ? nvram_sectors : 7'd16;
  // kg_bk_ram has the aux port once the clear has written its last byte
  wire bk_own = clear_done && !aux_req;
  reg bk_own_d = 1'b0;
  always @(posedge clk)
    bk_own_d <= bk_own;
  wire bk_start = bk_own && !bk_own_d;
  wire bk_req, bk_we;
  wire [14:0] bk_addr;
  wire [7:0] bk_din, aux_dout;
  // the CPU writes the PRG RAM (the mappers put it at 0x3C0000)
  wire bk_wr = memory_write && run_mem && memory_addr[21:15] == 7'b11_1100_0;

  kg_bk_ram #(.SLOT(3'd0), .IDLE_CLOCKS(BK_IDLE_CLOCKS), .MAX_CLOCKS(BK_MAX_CLOCKS), .MOUNT_CLOCKS(BK_MOUNT_CLOCKS),
    .GRACE_CLOCKS(BK_GRACE_CLOCKS), .TIMEOUT(24'd4300000)) bk_ram(
    .clk(clk), .reset(loader_reset),
    .start(bk_start), .size(bk_size), .kind(8'h00), .busy(bk_busy), .mounted(bk_mounted), .saving(bk_saving),
    .save_error(bk_error),
    .wr(bk_wr), .wr_addr(memory_addr[14:0]),
    .mem_req(bk_req), .mem_we(bk_we), .mem_addr(bk_addr), .mem_din(bk_din), .mem_ack(aux_ack), .mem_dout(aux_dout),
    .img_mounted(img_mounted), .img_size(img_size), .img_data_wr(img_data_wr), .img_data_addr(img_data_addr),
    .img_data(img_data), .img_result_wr(img_result_wr), .img_result(img_result), .img_sum(img_sum),
    .img_flush(img_flush), .img_q_wr(img_q_wr), .img_q_di(img_q_di), .img_q_ack(img_q_ack));

  MemoryController memory(
    .clk(clk), .phase(nes_ce),
    .read_a(memory_read_cpu && run_mem), .read_b(memory_read_ppu && run_mem), .write(memory_write && run_mem),
    .addr(memory_addr), .din(memory_dout), .dout_a(memory_din_cpu), .dout_b(memory_din_ppu),
    .aux_req(bk_own ? bk_req : aux_req), .aux_we(bk_own ? bk_we : 1'b1),
    .aux_addr(bk_own ? {7'b11_1100_0, bk_addr} : aux_addr), .aux_din(bk_own ? bk_din : aux_din),
    .aux_ack(aux_ack), .aux_dout(aux_dout),
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
