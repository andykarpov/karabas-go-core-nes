`timescale 1ns / 1ps
`default_nettype wire

/*
 memorycontroller.v

 Memory of the NES: the 4 MB asynchronous SRAM of the board (2M x 16, 10 ns) and the block RAMs of the CPU RAM
 and the VRAM, for two ports: the NES (CPU and PPU through MemoryMultiplex, one access per NES clock) and an aux
 port (the game loader; later the backup RAM and the save states).

 Address space: the 22 bit byte address of the mappers (as NES_MiSTer has it), which is the whole SRAM:
   0x000000-0x1FFFFF  PRG ROM (2 MB)                          SRAM
   0x200000-0x2FFFFF  CHR ROM / CHR RAM (1 MB)                SRAM
   0x300000-0x37FFFF  VRAM (2 KB, a[10:0])                    block RAM
   0x380000-0x3BFFFF  CPU RAM (2 KB, a[10:0])                 block RAM
   0x3C0000-0x3FFFFF  PRG RAM, mapper RAM (CHR RAM of TQROM)  SRAM
 The SRAM words: MA = a[21:1], the byte lane by a[0] (MWR_N[0] / MD[7:0] for even bytes). The SRAM under the
 two block RAM regions (0x300000-0x3BFFFF, 768 KB) is free for the save states.

 Timing, in the four clocks of an NES clock (phase = nes_ce of nes_system, the NES requests at phase 0, its
 flip-flops take dout_a / dout_b at the end of phase 3):
   slot N (phases 1, 2): the NES request of phase 0, else an aux request
   slot X (phases 3, 0): an aux request
 A slot: the address, lane and data go out at its first clock edge; a read takes the SRAM word into md_q at the
 second edge (one clock, 46 ns: 15 ns out + 10 ns tAA + 15 ns in, TS_SRAM_* of the ucf) and the block RAM word
 is registered there as well; a write pulls /WE low and drives MD from the falling edge in its first clock to the
 falling edge in its second clock, so the address is stable half a clock before and after /WE.
 The NES sees the read word in dout_a (CPU) / dout_b (PPU) from the end of phase 3, as the controller before this
 one had it (requested at phase 0, latched three clocks later).
 aux: aux_req held until aux_ack (one clock, two edges after the slot: aux_dout valid then); the requester drops
 or changes aux_req at the edge where it sees aux_ack.
*/

module MemoryController(
	input wire clk,
	input wire [1:0] phase,

	// NES, at phase 0
	input wire read_a,             // CPU read
	input wire read_b,             // PPU read
	input wire write,
	input wire [21:0] addr,
	input wire [7:0] din,
	output reg [7:0] dout_a = 8'd0,
	output reg [7:0] dout_b = 8'd0,

	// aux
	input wire aux_req,
	input wire aux_we,
	input wire [21:0] aux_addr,
	input wire [7:0] aux_din,
	output reg aux_ack = 1'b0,
	output reg [7:0] aux_dout = 8'd0,

	// SRAM
	output reg [20:0] MA = 21'd0,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N
);

// a slot
reg [21:0] s_addr = 22'd0;
reg [7:0] s_din = 8'd0;
reg s_we = 1'b0;
reg s_act = 1'b0;      // first clock of a slot with an access
reg s_aux = 1'b0;      // the access is the aux request
reg s_rd_a = 1'b0, s_rd_b = 1'b0;
// the slot after its second edge
reg r_valid = 1'b0, r_aux = 1'b0, r_rd_a = 1'b0, r_rd_b = 1'b0, r_vram = 1'b0, r_ram = 1'b0, r_lane = 1'b0;

wire s_vram = s_addr[21:19] == 3'b110;
wire s_ram = s_addr[21:18] == 4'b1110;
wire s_sram = !s_vram && !s_ram;

// a new slot starts at the edge that ends phase 0 (slot N) or phase 2 (slot X)
wire nes_req = read_a || read_b || write;
wire start_n = phase == 2'd0;
wire start_x = phase == 2'd2;
wire take_nes = start_n && nes_req;
reg aux_busy = 1'b0;    // an aux access in its slot, until aux_ack
wire take_aux = (start_x || (start_n && !nes_req)) && aux_req && !aux_busy && !aux_ack;

always @(posedge clk) begin
	s_act <= 1'b0;
	if (take_nes) begin
		s_addr <= addr;
		s_din <= din;
		s_we <= write;
		s_act <= 1'b1;
		s_aux <= 1'b0;
		s_rd_a <= read_a;
		s_rd_b <= read_b;
	end
	else if (take_aux) begin
		s_addr <= aux_addr;
		s_din <= aux_din;
		s_we <= aux_we;
		s_act <= 1'b1;
		s_aux <= 1'b1;
		s_rd_a <= 1'b0;
		s_rd_b <= 1'b0;
	end
	if (take_nes || take_aux)
		MA <= take_nes ? addr[21:1] : aux_addr[21:1];
	if (take_aux)
		aux_busy <= 1'b1;
	else if (r_valid && r_aux)
		aux_busy <= 1'b0;
end

// SRAM write: /WE and the data on the falling edges, for the first slot clock to the second
reg [1:0] we_n = 2'b11;
reg [15:0] md_out = 16'd0;
always @(negedge clk) begin
	we_n <= 2'b11;
	if (s_act && s_we && s_sram) begin
		we_n <= s_addr[0] ? 2'b01 : 2'b10;
		md_out <= {s_din, s_din};
	end
end
assign MWR_N = we_n;
assign MD[7:0] = !we_n[0] ? md_out[7:0] : 8'bz;
assign MD[15:8] = !we_n[1] ? md_out[15:8] : 8'bz;

// SRAM read: the word at the second slot edge
reg [15:0] md_q = 16'd0;
always @(posedge clk)
	if (s_act)
		md_q <= MD;

// block RAMs, accessed in the first slot clock (registered output at the second edge)
wire [7:0] vram_dout, ram_dout;
kg_spram #(.AW(11)) vram(clk, s_act && s_vram, s_we, s_addr[10:0], s_din, vram_dout); // VRAM in BRAM
kg_spram #(.AW(11)) ram(clk, s_act && s_ram, s_we, s_addr[10:0], s_din, ram_dout);   // RAM in BRAM

// the word of the slot after its second edge
always @(posedge clk) begin
	r_valid <= s_act;
	if (s_act) begin
		r_aux <= s_aux;
		r_rd_a <= s_rd_a && !s_we;
		r_rd_b <= s_rd_b && !s_we;
		r_vram <= s_vram;
		r_ram <= s_ram;
		r_lane <= s_addr[0];
	end
end
wire [7:0] r_word = r_vram ? vram_dout : r_ram ? ram_dout : r_lane ? md_q[15:8] : md_q[7:0];

// NES: dout at the end of phase 3 (the slot N word, ready since the end of phase 2)
reg [7:0] n_word = 8'd0;
reg n_rd_a = 1'b0, n_rd_b = 1'b0;
always @(posedge clk) begin
	aux_ack <= 1'b0;
	if (r_valid && !r_aux) begin
		n_word <= r_word;
		n_rd_a <= r_rd_a;
		n_rd_b <= r_rd_b;
	end
	if (r_valid && r_aux) begin
		aux_dout <= r_word;
		aux_ack <= 1'b1;
	end
	if (phase == 2'd3) begin
		if (n_rd_a) dout_a <= n_word;
		if (n_rd_b) dout_b <= n_word;
		n_rd_a <= 1'b0;
		n_rd_b <= 1'b0;
	end
end

endmodule
