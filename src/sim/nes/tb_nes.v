`timescale 1ns / 1ps

/*
 tb_nes.v: the top of the NES simulation (verilator, sim_nes.cpp drives it): nes_system of the tops with a
 model of the SRAM (512K x 8, the low byte lane MA / MD / MWR_N; /OE is tied low on the boards).
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
	input wire [7:0] joy_l,
	input wire [7:0] joy_r,
	output wire [5:0] color,
	output wire [8:0] cycle,
	output wire [8:0] scanline,
	output wire [15:0] sample,
	input wire [12:0] status_addr,
	output wire [7:0] status_data
);

wire [18:0] ma;
wire [7:0] md;
wire mwr_n;
wire [15:0] debug_data;

nes_system dut (
	.clk(clk), .reset(reset),
	.loader_reset(loader_reset), .loader_data(loader_data), .loader_wr(loader_wr),
	.loader_done(loader_done), .loader_fail(loader_fail), .debug_data(debug_data),
	.joy_l(joy_l), .joy_r(joy_r),
	.color(color), .cycle(cycle), .scanline(scanline), .sample(sample),
	.MA(ma), .MD(md), .MWR_N(mwr_n)
);

// asynchronous SRAM: the controller holds the address, data and /WE for three clocks
reg [7:0] sram [0:(1<<19)-1];
assign md = mwr_n ? sram[ma] : 8'bz;
always @(posedge clk)
	if (!mwr_n)
		sram[ma] <= md;

reg [7:0] cpu_6000 [0:8191];
integer i;
initial for (i = 0; i < 8192; i = i + 1) cpu_6000[i] = 8'h00;
always @(posedge clk)
	if (dut.nes.mw_int && dut.nes.addr[15:13] == 3'b011)
		cpu_6000[dut.nes.addr[12:0]] <= dut.nes.dbus;
assign status_data = cpu_6000[status_addr];

endmodule
