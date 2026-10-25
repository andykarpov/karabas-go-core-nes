`timescale 1ns / 1ps

/*
 tb_nes.v: the top of the NES simulation (verilator, sim_nes.cpp drives it): nes_system of the tops with a
 model of the SRAM: two byte lanes of 2M x 8 (MD[7:0] / MWR_N[0], MD[15:8] / MWR_N[1]), /OE tied low as on
 the boards, so a lane drives MD while its /WE is high and takes MD while /WE is low (here: at each falling
 clock edge with /WE low, where the controller changes /WE and the data).
 status_addr / status_data read $6000 + status_addr as the CPU wrote it, for the result protocol of the
 blargg test ROMs: a copy of the CPU writes to $6000-$7FFF on the bus of the NES, so it works with mappers
 that have no PRG RAM in this core (NROM, MMC0).
*/
module tb_nes (
	input wire clk,
	input wire reset,
	input wire loader_reset,
	input wire [7:0] loader_data,
	input wire loader_wr,
	output wire loader_done,
	output wire loader_fail,
	output wire [63:0] mapper_flags,
	output wire [31:0] rom_crc,
	input wire [7:0] joy_l,
	input wire [7:0] joy_r,
	output wire [5:0] color,
	output wire [8:0] cycle,
	output wire [8:0] scanline,
	output wire [15:0] sample,
	input wire [12:0] status_addr,
	output wire [7:0] status_data
);

wire [20:0] ma;
wire [15:0] md;
wire [1:0] mwr_n;
wire [15:0] debug_data;

nes_system dut (
	.clk(clk), .reset(reset),
	.loader_reset(loader_reset), .loader_data(loader_data), .loader_wr(loader_wr),
	.loader_done(loader_done), .loader_fail(loader_fail), .debug_data(debug_data),
	.mapper_flags(mapper_flags), .rom_crc(rom_crc),
	.joy_l(joy_l), .joy_r(joy_r),
	.color(color), .cycle(cycle), .scanline(scanline), .sample(sample),
	.MA(ma), .MD(md), .MWR_N(mwr_n)
);

reg [7:0] sram_lo [0:(1<<21)-1];
reg [7:0] sram_hi [0:(1<<21)-1];
assign md[7:0] = mwr_n[0] ? sram_lo[ma] : 8'bz;
assign md[15:8] = mwr_n[1] ? sram_hi[ma] : 8'bz;
always @(negedge clk) begin
	if (!mwr_n[0]) sram_lo[ma] <= md[7:0];
	if (!mwr_n[1]) sram_hi[ma] <= md[15:8];
end

reg [7:0] cpu_6000 [0:8191];
integer i;
initial for (i = 0; i < 8192; i = i + 1) cpu_6000[i] = 8'h00;
always @(posedge clk)
	if (dut.nes.mw_int && dut.nes.addr[15:13] == 3'b011)
		cpu_6000[dut.nes.addr[12:0]] <= dut.nes.dbus;
assign status_data = cpu_6000[status_addr];

endmodule
