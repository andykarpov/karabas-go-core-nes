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
// karabas: made by src/tools/mktops.py from karabas_minig_top.v (do not edit it, change Mini G)

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
	
assign TAPE_OUT = 1'b0;

assign ESP_RESET_N = 1'bZ;
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

assign MIDI_TX = 1'b1;
assign MIDI_CLK = 1'b1;
assign MIDI_RESET_N = 1'b1;

assign FLASH_CS_N = 1'b1;
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

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
 .CLKOUT2_DIVIDE(115),
 .BUFG_MASK(6'b000111)
) clock_21mhz(
 .clk_in(CLK_50MHZ),
 .rst(1'b0),
 .clk_out(pll_clk),
 .locked(locked)
);
assign clk = pll_clk[0]; // 21.x
assign clk_vga = pll_clk[1]; // 25.0	
assign areset = ~locked;

// Go has no FT_CLK_OUT

// no HDMI on Go	
	 
//---------- MCU: link v2 (karabas-go-firmware docs/link_v2.md, kg_mcu2); INT on IO1 ------------

wire [55:0] hid_kbd;
wire [7:0] hid_kb_status = hid_kbd[7:0], hid_kb_dat0 = hid_kbd[15:8], hid_kb_dat1 = hid_kbd[23:16],
	hid_kb_dat2 = hid_kbd[31:24], hid_kb_dat3 = hid_kbd[39:32], hid_kb_dat4 = hid_kbd[47:40],
	hid_kb_dat5 = hid_kbd[55:48];
wire [15:0] joy_l16, joy_r16;
wire [12:0] joy_l = joy_l16[12:0], joy_r = joy_r16[12:0];
wire [1:0] ld_kind;
wire [7:0] ld_data;
wire [31:0] ld_addr;
wire ld_start, ld_wr;
wire [7:0] softsw_regs;
wire mcu_busy;
wire [15:0] debug_data;
wire dvi_only;
wire osd_wr, osd_en, osd_zoom;
wire [11:0] osd_waddr;
wire [7:0] osd_wdata;
wire [23:0] osd_fg, osd_bg;
wire [1:0] osd_alpha, osd_place;
wire [4:0] osd_px, osd_ph;
wire [3:0] osd_py;
wire [5:0] osd_pw;
// the .sav file of kg_bk_ram (nes_system, slot 0) on the mounter of kg_mcu2
wire [7:0] img_flush, sdc_img_mounted, sdc_rd, sdc_wr, sdc_byte_in_data, sdc_byte_out_data, bk_kind, bk_result;
wire [63:0] sdc_img_size;
wire [31:0] sdc_sector, bk_size;
wire sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe, bk_mount, bk_flushed;
wire [2:0] sdc_slot;
wire [8:0] sdc_byte_addr;

wire mcu_int;
// Go: INT on MCU_SPI_IO[0] (N9, the IO1 line of the firmware)
assign MCU_SPI_IO[0] = mcu_int;
assign MCU_SPI_IO[1] = 1'bz;

// the game: the file loader (LD kind 1); fileloader_reset of v1 = its START
wire fileloader_reset = ld_start && ld_kind == 2'd1;
wire fileloader_wr = ld_wr && ld_kind == 2'd1;
wire [31:0] fileloader_addr = ld_addr;
wire [7:0] fileloader_data = ld_data;

// clk 21.5 MHz: below 4 x the 16 MHz sck anyway (and kg_l2_link has no bound since modules #41)
kg_mcu2 #(
	.CAPS(16'h0002),     // backup RAM: the firmware flushes the .sav before a new game
	.SW_N(1),
	.CS_FILTER(3),
	.ENABLE_OSD(1),
	.ENABLE_IMG(1),      // the .sav files of kg_bk_ram
	.IMG_OUT_LATENCY(2), // the sector buffer of kg_bk_ram
	.ENABLE_AUX(1),      // DEBUG_DATA
	.ENABLE_FT(1),
	.ENABLE_SD2(1)
) mcu(
	.CLK(clk),
	.N_RESET(~areset),

	.MCU_SCK(MCU_SCK),
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SS(MCU_CS_N),
	.MCU_INT(mcu_int),
	.MCU_SPI_FT_SS(MCU_SPI_FT_CS_N),
	.MCU_SPI_SD2_SS(MCU_SPI_SD2_CS_N),

	.SW(softsw_regs), .SW_WR(), .SW_INDEX(), .SW_VALUE(), .HW_ID(), .DVI_ONLY(dvi_only), .CORE_BUILD(), .FW_BUILD(),
	.BUSY(mcu_busy), .BTNS(), .RELOAD_REQ(1'b0), .RELOAD_CORE(8'd0),

	.KBD(hid_kbd), .KBD_WR(), .PS2_CODE(), .PS2_KIND(), .PS2_WR(),
	.MS_X(), .MS_Y(), .MS_Z(), .MS_B(), .MS_WR(),
	.JOY_L(joy_l16), .JOY_R(joy_r16), .JOY_WR(),
	.PS2_CMD(16'h0000), .PS2_CMD_WR(1'b0),

	.LD_KIND(ld_kind), .LD_SLOT(), .LD_SIZE(), .LD_START(ld_start), .LD_ACTIVE(), .LD_END(),
	.LD_ADDR(ld_addr), .LD_DATA(ld_data), .LD_WR(ld_wr), .LD_READY(1'b1),

	.OSD_WR(osd_wr), .OSD_WADDR(osd_waddr), .OSD_WDATA(osd_wdata), .OSD_EN(osd_en),
	.OSD_FG(osd_fg), .OSD_BG(osd_bg), .OSD_ALPHA(osd_alpha), .OSD_PX(osd_px), .OSD_PY(osd_py),
	.OSD_PW(osd_pw), .OSD_PH(osd_ph), .OSD_PLACE(osd_place), .OSD_ZOOM(osd_zoom),

	.SDC_IMG_MOUNTED(sdc_img_mounted), .SDC_IMG_SIZE(sdc_img_size),
	.SDC_RD(sdc_rd), .SDC_WR(sdc_wr), .SDC_SECTOR(sdc_sector),
	.SDC_BUSY(sdc_busy), .SDC_DONE(sdc_done), .SDC_ERROR(sdc_error), .SDC_SLOT(sdc_slot),
	.SDC_BYTE_IN_STROBE(sdc_byte_in_strobe), .SDC_BYTE_ADDR(sdc_byte_addr),
	.SDC_BYTE_IN_DATA(sdc_byte_in_data), .SDC_BYTE_OUT_DATA(sdc_byte_out_data),
	.IMG_WP(), .IMG_PHYS_WR(), .IMG_PHYS(), .IMG_FLUSH(img_flush), .FDD_CHNG_WR(), .FDD_CHNG(),
	.FDD_CHNG_REQ(1'b0), .FDD_CHNG_DS(2'd0),
	.BK_MOUNT(bk_mount), .BK_FLUSHED(bk_flushed), .BK_SLOT(3'd0), .BK_SIZE(bk_size),
	.BK_KIND(bk_kind), .BK_RESULT(bk_result),
	.IMG_ACTIVE(),

	.PORT_OUT_DATA(), .PORT_OUT_WR(), .PORT_OUT_READY(4'b1111), .PORT_IN_DATA(32'd0), .PORT_IN_WR(4'd0),
	.PORT_CFG(128'd0), .PORT_IN_FULL(), .PORT_STAT(), .PORT_STAT_WR(),
	.RTC_A(8'd0), .RTC_DI(8'd0), .RTC_CS(1'b0), .RTC_WR_N(1'b1), .RTC_DO(),
	.MATRIX_CMD(24'd0), .MATRIX_CMD_WR(1'b0), .DEBUG_ADDR(16'd0), .DEBUG_DATA(debug_data),

	.FT_SPI_ON(), .FT_VGA_ON(), .FT_RESET(),
	.FT_SCK(FT_SPI_SCK), .FT_MOSI(FT_SPI_MOSI), .FT_MISO(FT_SPI_MISO), .FT_CS_N(FT_SPI_CS_N),
	.SD2_SCK(SD_CLK), .SD2_MOSI(SD_DI), .SD2_MISO(SD_DO), .SD2_CS_N(SD_CS_N)
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

// register 0, bit 0: reset (the SW registers of kg_mcu2)
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

// no ADC on Go

//--------- OSD --------------

wire [7:0] video_r, video_g, video_b, osd_r, osd_g, osd_b;
wire video_hsync, video_vsync, video_blank;

// the bitmap OSD of link v2 (kg_l2_osd_overlay): written in clk, drawn in clk_vga, centred in de,
// 2 clocks of latency with its syncs and de (negative syncs of vga.vhd pass through)
wire osd_hs, osd_vs, osd_de;
kg_l2_osd_overlay osd (
	.wclk(clk),
	.osd_wr(osd_wr), .osd_waddr(osd_waddr), .osd_wdata(osd_wdata), .osd_en(osd_en),
	.osd_fg(osd_fg), .osd_bg(osd_bg), .osd_alpha(osd_alpha), .osd_px(osd_px), .osd_py(osd_py),
	.osd_pw(osd_pw), .osd_ph(osd_ph), .osd_place(osd_place), .osd_zoom(osd_zoom),
	.icon_on(8'd0), .icon_act(8'd0),
	.clk(clk_vga),
	.rgb_i({video_r, video_g, video_b}), .hs_i(video_hsync), .vs_i(video_vsync), .de_i(~video_blank),
	.rgb_o({osd_r, osd_g, osd_b}), .hs_o(osd_hs), .vs_o(osd_vs), .de_o(osd_de)
);

//--------- NES --------------

wire [8:0] cycle;
wire [8:0] scanline;
wire [15:0] sample;
wire [5:0] color;
wire loader_done, loader_fail;

nes_system #(.LINK(2)) nes_system(
	.clk(clk),
	.reset(kb_reset),
	.loader_reset(fileloader_reset),
	.loader_data(fileloader_data),
	.loader_wr(fileloader_wr),
	.loader_done(loader_done),
	.loader_fail(loader_fail),
	.debug_data(debug_data),
	.img_mounted(8'd0),
	.img_size(64'd0),
	.img_data_wr(1'b0),
	.img_data_addr(9'd0),
	.img_data(8'd0),
	.img_result_wr(1'b0),
	.img_result(8'd0),
	.img_sum(16'd0),
	.img_flush(img_flush),
	.img_q_wr(),
	.img_q_di(),
	.img_q_ack(1'b0),
	.sdc_img_mounted_i(sdc_img_mounted), .sdc_img_size_i(sdc_img_size), .sdc_rd_o(sdc_rd), .sdc_wr_o(sdc_wr),
	.sdc_sector_o(sdc_sector), .sdc_busy_i(sdc_busy), .sdc_done_i(sdc_done), .sdc_error_i(sdc_error),
	.sdc_slot_i(sdc_slot), .sdc_byte_in_strobe_i(sdc_byte_in_strobe), .sdc_byte_addr_i(sdc_byte_addr),
	.sdc_byte_in_data_i(sdc_byte_in_data), .sdc_byte_out_data_o(sdc_byte_out_data),
	.bk_mount_o(bk_mount), .bk_flushed_o(bk_flushed), .bk_size_o(bk_size), .bk_kind_o(bk_kind),
	.bk_result_o(bk_result),
	.bk_mounted(),
	.bk_saving(),
	.bk_error(),
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
	.O_BLANK(video_blank)
  );
				
  assign audio_out_l = {sample[15] ^ 1'b1, sample[14:0]};
  assign audio_out_r = {sample[15] ^ 1'b1, sample[14:0]};
  
// ------------ VGA ----------------

assign VGA_R = osd_r;
assign VGA_G = osd_g;
assign VGA_B = osd_b;
assign VGA_HS = osd_hs;
assign VGA_VS = osd_vs;
ODDR2 oddr_v_clk (.Q(V_CLK), .C0(clk_vga), .C1(~clk_vga), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

endmodule
