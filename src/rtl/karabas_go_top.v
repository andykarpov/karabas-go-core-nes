`timescale 1ns / 1ps
`default_nettype wire

/*-------------------------------------------------------------------------------------------------------------------
-- 
-- 
-- #       #######                                                 #                                               
-- #                                                               #                                               
-- #                                                               #                                               
-- ############### ############### ############### ############### ############### ############### ############### 
-- #             #               # #                             # #             #               # #               
-- #             # ############### #               ############### #             # ############### ############### 
-- #             # #             # #               #             # #             # #             #               # 
-- #             # ############### #               ############### ############### ############### ############### 
--                                                                                                                 
--         ####### ####### ####### #######                                         ############### ############### 
--                                                                                 #               #             # 
--                                                                                 #   ########### #             # 
--                                                                                 #             # #             # 
-- https://github.com/andykarpov/karabas-go                                        ############### ############### 
--
-- FPGA NES core for Karabas-Go
--
-- @author Andy Karpov <andy.karpov@gmail.com>
-- Ukraine, 2024
------------------------------------------------------------------------------------------------------------------*/

module karabas_go_top (
   //---------------------------
   input wire CLK_50MHZ,

	//---------------------------
	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,
	inout wire ESP_RESET_N,
	inout wire ESP_BOOT_N,
	
   //---------------------------
   output wire [20:0] MA,
   inout wire [15:0] MD,
   output wire [1:0] MWR_N,
   output wire [1:0] MRD_N,

   //---------------------------
	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

   //---------------------------
   output wire SD_CS_N,
   output wire SD_CLK,
   output wire SD_DI,
   input wire SD_DO,
	input wire SD_DET_N,

   //---------------------------
   output wire [7:0] VGA_R,
   output wire [7:0] VGA_G,
   output wire [7:0] VGA_B,
   output wire VGA_HS,
   output wire VGA_VS,
	output wire V_CLK,
	
	//---------------------------
	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	output wire FT_OE_N,

	//---------------------------
	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,
	
	//---------------------------
	input wire FDC_INDEX,
	output wire [1:0] FDC_DRIVE,
	output wire FDC_MOTOR,
	output wire FDC_DIR,
	output wire FDC_STEP,
	output wire FDC_WDATA,
	output wire FDC_WGATE,
	input wire FDC_TR00,
	input wire FDC_WPRT,
	input wire FDC_RDATA,
	output wire FDC_SIDE_N,

   //---------------------------	
	output wire TAPE_OUT,
	input wire TAPE_IN,
	output wire BEEPER,
	
	//---------------------------
	output wire DAC_LRCK,
   output wire DAC_DAT,
   output wire DAC_BCK,
   output wire DAC_MUTE,
	
	//---------------------------
	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	
	input wire MCU_SPI_FT_CS_N,
	input wire MCU_SPI_SD2_CS_N,
	
	inout wire [1:0] MCU_SPI_IO,
	
	//---------------------------
	output wire MIDI_TX,
	output wire MIDI_CLK,
	output wire MIDI_RESET_N,
	
	//---------------------------
	output wire FLASH_CS_N,
	input wire  FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N	
);

// unused signals

assign SDR_BA = 2'b11;
assign SDR_A = 13'b1111111111111;
assign SDR_CLK = 1'b1;
assign SDR_DQM = 2'b11;
assign SDR_WE_N = 1'b1;
assign SDR_CAS_N = 1'b1;
assign SDR_RAS_N = 1'b1;

assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;
	
assign FDC_DRIVE = 2'b00;
assign FDC_MOTOR = 1'b0;
assign FDC_DIR = 1'b0;
assign FDC_STEP = 1'b0;
assign FDC_WDATA = 1'b0;
assign FDC_WGATE = 1'b0;
assign FDC_SIDE_N = 1'b1;

assign TAPE_OUT = 1'b0;
assign BEEPER = 1'b0;

assign ESP_RESET_N = 1'bZ;
assign ESP_BOOT_N = 1'bZ;	

assign MIDI_TX = 1'b1;
assign MIDI_CLK = 1'b1;
assign MIDI_RESET_N = 1'b1;

assign FLASH_CS_N = 1'b1;
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

assign FT_OE_N = 1'b1;

// clock
wire clk, clk_vga;
wire locked;
wire areset;

// 50 MHz * 37 / 2 = 925 MHz VCO: clk 925 / 43 = 21.51 MHz, clk_vga 925 / 37 = 25.0 MHz
wire [5:0] pll_clk;
kg_pll #(
 .CLKIN_PERIOD(20.0),
 .DIVCLK_DIVIDE(2),
 .CLKFBOUT_MULT(37),
 .CLKOUT0_DIVIDE(43),
 .CLKOUT1_DIVIDE(37),
 .BUFG_MASK(6'b000011)
) clock_21mhz(
 .clk_in(CLK_50MHZ),
 .rst(1'b0),
 .clk_out(pll_clk),
 .locked(locked)
);
assign clk = pll_clk[0]; // 21.x
assign clk_vga = pll_clk[1]; // 25.0	
assign areset = ~locked;
	 
//---------- MCU ------------

wire [7:0] hid_kb_status, hid_kb_dat0, hid_kb_dat1, hid_kb_dat2, hid_kb_dat3, hid_kb_dat4, hid_kb_dat5;
wire [12:0] joy_l, joy_r;
wire romloader_act, fileloader_reset;
wire [31:0] romloader_addr, fileloader_addr;
wire [7:0] romloader_data, fileloader_data;
wire romloader_wr, fileloader_wr;
wire [15:0] softsw_command, osd_command;
wire ft_vga_on;
wire mcu_busy;
wire [15:0] debug_data;

// burst transfers from the mcu (karabas-go-firmware docs/burst_protocol.md)
wire mcu_burst_ready;
assign MCU_SPI_IO[0] = mcu_burst_ready;
assign MCU_SPI_IO[1] = 1'bz;

kg_mcu #(
	.BURST_MAX_MHZ(0),
	.CS_FILTER(3),
	.ENABLE_RTC(0),
	.ENABLE_UART(0),
	.ENABLE_MATRIX(0),
	.ENABLE_DEBUG(0),
	.ENABLE_IMG(1),
	.ENABLE_FILE(1),
	.FILE_CMDS(1),     // FILEBANK / FILEDATA / FILELOADER: the game for GameLoader
	.FILE_WR_EACH(0),  // a write when the address changes, as mcu.vhd did
	.FILE_TO_ROM(0),
	.ENABLE_FT(1),
	.ENABLE_SD2(1)
) mcu(
	.CLK(clk),
	.N_RESET(~areset),
	
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SCK(MCU_SCK),
	.MCU_SS(MCU_CS_N),
	
	.MCU_SPI_FT_SS(MCU_SPI_FT_CS_N),
	.MCU_SPI_SD2_SS(MCU_SPI_SD2_CS_N),
	// burst transfers: firmware IO0 (GPIO14) = MCU_SPI_IO[1] (M11), IO1 (GPIO2) = MCU_SPI_IO[0] (N9)
	.MCU_BURST_CS_N(MCU_SPI_IO[1]),
	.MCU_BURST_READY(mcu_burst_ready),
	
	.KB_STATUS(hid_kb_status),
	.KB_DAT0(hid_kb_dat0),
	.KB_DAT1(hid_kb_dat1),
	.KB_DAT2(hid_kb_dat2),
	.KB_DAT3(hid_kb_dat3),
	.KB_DAT4(hid_kb_dat4),
	.KB_DAT5(hid_kb_dat5),
	
	.JOY_L(joy_l),
	.JOY_R(joy_r),
	
	.ROMLOADER_ACTIVE(romloader_act),
	.ROMLOAD_ADDR(romloader_addr),
	.ROMLOAD_DATA(romloader_data),
	.ROMLOAD_WR(romloader_wr),
	
	.FILELOAD_RESET(fileloader_reset),
	.FILELOAD_ADDR(fileloader_addr),
	.FILELOAD_DATA(fileloader_data),
	.FILELOAD_WR(fileloader_wr),
	
	.SOFTSW_COMMAND(softsw_command),	
	.OSD_COMMAND(osd_command),
	
	.BUSY(mcu_busy),
	
	.FT_VGA_ON(ft_vga_on),
	
	.FT_CS_N(FT_SPI_CS_N),
	.FT_MOSI(FT_SPI_MOSI),
	.FT_MISO(FT_SPI_MISO),
	.FT_SCK(FT_SPI_SCK),
	
	.SD2_CS_N(SD_CS_N),
	.SD2_MOSI(SD_DI),
	.SD2_MISO(SD_DO),
	.SD2_SCK(SD_CLK),
	
	.DEBUG_ADDR(16'h00),
	.DEBUG_DATA(debug_data),

	// not used by this core
	.RTC_A(8'h00),
	.RTC_DI(8'h00),
	.RTC_CS(1'b0),
	.RTC_WR_N(1'b1),
	.UART_TX_DATA(8'h00),
	.UART_TX_WR(1'b0),
	.UART_TX_MODE(1'b0),
	.UART_DLM(8'h00),
	.UART_DLL(8'h00),
	.UART_DLM_WR(1'b0),
	.UART_DLL_WR(1'b0),
	.MATRIX_CMD(24'h000000),
	.MATRIX_CMD_WR(1'b0),
	.IMG_Q_WR(1'b0),
	.IMG_Q_DI(24'h000000),
	.ESP_UART_RX_DATA(8'h00),
	.ESP_UART_RX_WR(1'b0),
	.FLASHBOOT_START(1'b0),
	.FLASHBOOT_COREID(5'd0)
);

//---------- HID Keyboard/Joy parser ------------

wire [7:0] nes_joy_l, nes_joy_r;

hid_parser hid_parser(
	.CLK(clk),
	.RESET(areset),

	.KB_STATUS(hid_kb_status),
	.KB_DAT0(hid_kb_dat0),
	.KB_DAT1(hid_kb_dat1),
	.KB_DAT2(hid_kb_dat2),
	.KB_DAT3(hid_kb_dat3),
	.KB_DAT4(hid_kb_dat4),
	.KB_DAT5(hid_kb_dat5),
	
	.JOY_L(joy_l),
	.JOY_R(joy_r),
	
	.JOY_L_DO(nes_joy_l),
	.JOY_R_DO(nes_joy_r)
);

//---------- Soft switches ------------

wire kb_reset;
wire btn_reset_n;

// register 0, bit 0: reset
wire [7:0] softsw_regs;
kg_soft_switches #(.N(1)) soft_switches(
	.clk(clk),
	.command(softsw_command),
	.regs(softsw_regs),
	.upd()
);
assign kb_reset = softsw_regs[0];

assign btn_reset_n = ~kb_reset & ~mcu_busy;

//---------- DAC ------------

wire [15:0] audio_out_l, audio_out_r;

kg_pcm5102 PCM5102(
	.clk(clk),
	.reset(areset),
	.left(audio_out_l),
	.right(audio_out_r),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_LRCK)
);
assign DAC_MUTE = 1'b1; // soft mute, 0 = mute, 1 = unmute

//--------- OSD --------------

wire [7:0] video_r, video_g, video_b, osd_r, osd_g, osd_b;
wire video_hsync, video_vsync;

overlay overlay(
	.CLK(clk),
	.CLK_VGA(clk_vga),
	.RGB_I({video_r[7:0], video_g[7:0], video_b[7:0]}),
	.RGB_O({osd_r[7:0], osd_g[7:0], osd_b[7:0]}),
	.HSYNC_I(video_hsync),
	.VSYNC_I(video_vsync),
	.OSD_COMMAND(osd_command)
);

assign VGA_R = osd_r;
assign VGA_G = osd_g;
assign VGA_B = osd_b;
assign VGA_HS = video_hsync;
assign VGA_VS = video_vsync;

//--------- NES --------------

wire [8:0] cycle;
wire [8:0] scanline;
wire [15:0] sample;
wire [5:0] color;
wire loader_done, loader_fail;

nes_system nes_system(
	.clk(clk),
	.reset(kb_reset),
	.loader_reset(fileloader_reset),
	.loader_data(fileloader_data),
	.loader_wr(fileloader_wr),
	.loader_done(loader_done),
	.loader_fail(loader_fail),
	.debug_data(debug_data),
	.joy_l(nes_joy_l),
	.joy_r(nes_joy_r),
	.color(color),
	.cycle(cycle),
	.scanline(scanline),
	.sample(sample),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N)
);
assign MRD_N = 2'b00;

  vga vga(
	.I_CLK(clk),
	.I_CLK_VGA(clk_vga),
	.I_COLOR(color),
	.I_HCNT(cycle),
	.I_VCNT(scanline),
	.O_HSYNC(video_hsync),
	.O_VSYNC(video_vsync),
	.O_RED(video_r),
	.O_GREEN(video_g),
	.O_BLUE(video_b),
	.O_HCNT(),
	.O_VCNT(),
	.O_H(),
	.O_BLANK()
  );
				
  assign audio_out_l = {sample[15] ^ 1'b1, sample[14:0]};
  assign audio_out_r = {sample[15] ^ 1'b1, sample[14:0]};
  
	ODDR2 u_v_clk (
		.Q(V_CLK),
		.C0(clk_vga),
		.C1(~clk_vga),
		.CE(1'b1),
		.D0(1'b1),
		.D1(1'b0),
		.R(1'b0),
		.S(1'b0)
	);
	
	/*always @(posedge clk) begin
		debug_data <= {8'h00 , 3'b000, run_nes , reset_nes , loader_reset , loader_fail , loader_done};
	end;*/

endmodule
