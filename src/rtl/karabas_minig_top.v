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
-- FPGA NES core for Karabas-Go Mini
--
-- @author Andy Karpov <andy.karpov@gmail.com>
-- Ukraine, 2024
------------------------------------------------------------------------------------------------------------------*/

module karabas_minig_top (
   //---------------------------
   input wire CLK_50MHZ,

	//---------------------------
	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,
	
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
   input wire [7:0] VGA_R,
   input wire [7:0] VGA_G,
   input wire [7:0] VGA_B,
   input wire VGA_HS,
   input wire VGA_VS,
	
   output wire [3:0] TMDS_P,
   output wire [3:0] TMDS_N,	
	
	//---------------------------
	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	input wire FT_DE,
	output wire FT_CLK_OUT,

	//---------------------------
	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,
	
   //---------------------------	
	output wire TAPE_OUT,
	input wire TAPE_IN,

	output wire DAC_BCK,
	output wire DAC_WS,
	output wire DAC_DAT,
	
	//---------------------------
	output wire ADC_CLK,
   inout wire ADC_BCK,
	inout wire ADC_LRCK,
   input wire ADC_DOUT,
	
	//---------------------------
	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,	
	inout wire [5:0] MCU_IO, // [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n
	
	//---------------------------
	output wire MIDI_TX,
	
	output wire ESP32_SPI_CS_N,
	input wire ESP32_PCM_BCK,
	input wire ESP32_PCM_RLCK,
	input wire ESP32_PCM_DAT,
	
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
	
assign TAPE_OUT = 1'b0;

assign ESP32_SPI_CS_N = 1'b1;

assign MIDI_TX = 1'b1;

assign FLASH_CS_N = 1'b1;
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;
assign FT_CLK_OUT = 1'b0;

// clock
wire clk, clk_vga;
wire clk_hdmi, clk_hdmi_n;
wire locked, lockedx5;
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

// hdmi serial clock: 5 x clk_vga and its inverse
kg_dcm #(
	.CLKIN_PERIOD(40.0),
	.CLKFX_MULTIPLY(5),
	.CLKFX_DIVIDE(1)
) pllx5(
	.clk_in(clk_vga),
	.rst(1'b0),
	.clk_fx(clk_hdmi),
	.clk_fx180(clk_hdmi_n),
	.clk_0(),
	.locked(lockedx5)
);	
	 
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
wire [7:0] hwid;
wire dvi_only;

// burst transfers from the mcu (karabas-go-firmware docs/burst_protocol.md)
wire mcu_burst_ready;
assign MCU_IO[1] = mcu_burst_ready;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;

// Rev.G has MCU_SCK on a global clock pin: bursts at up to 32 MHz
kg_mcu #(
	.BURST_MAX_MHZ(32),
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
	
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),
	.MCU_BURST_CS_N(MCU_IO[0]),
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
	
	.HWID(hwid),
	.DVI_ONLY(dvi_only),	
	
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
wire [31:0] audio_mix_l, audio_mix_r;

kg_pcm5102 PCM5102(
	.clk(clk),
	.reset(areset),
	.left(audio_out_l),
	.right(audio_out_r),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_WS)
);

// ------- PCM1808 ADC ---------
wire signed [23:0] adc_l, adc_r;

i2s_transceiver adc(
	.reset_n(~areset),
	.mclk(clk),
	.sclk(ADC_BCK),
	.ws(ADC_LRCK),
	.sd_tx(),
	.sd_rx(ADC_DOUT),
	.l_data_tx(24'b0),
	.r_data_tx(24'b0),
	.l_data_rx(adc_l),
	.r_data_rx(adc_r)
);

// ------- ADC_CLK output buf
ODDR2 oddr_adc2(
	.Q(ADC_CLK),
	.C0(clk_bus),
	.C1(~clk_bus),
	.CE(1'b1),
	.D0(1'b1),
	.D1(1'b0),
	.R(1'b0),
	.S(1'b0)
);

// ------- audio mix host + adc
assign audio_mix_l = audio_out_l[15:0] + adc_l[23:8];
assign audio_mix_r = audio_out_r[15:0] + adc_r[23:8];

//--------- OSD --------------

wire [7:0] video_r, video_g, video_b, osd_r, osd_g, osd_b;
wire video_hsync, video_vsync, video_blank;

overlay overlay(
	.CLK(clk),
	.CLK_VGA(clk_vga),
	.RGB_I({video_r[7:0], video_g[7:0], video_b[7:0]}),
	.RGB_O({osd_r[7:0], osd_g[7:0], osd_b[7:0]}),
	.HSYNC_I(video_hsync),
	.VSYNC_I(video_vsync),
	.OSD_COMMAND(osd_command)
);

//--------- NES --------------

// NES Palette -> RGB332 conversion
reg [14:0] pallut[0:63];
initial $readmemh("nes_palette.txt", pallut);
  
wire [8:0] cycle;
wire [8:0] scanline;
wire [15:0] sample;
wire [5:0] color;
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
wire loader_done, loader_fail;

assign loader_reset = fileloader_reset;
  
  GameLoader loader(
    clk, 
    loader_reset, 
	 fileloader_data, 
	 fileloader_wr,
	 loader_addr, 
	 loader_write_data, 
	 loader_write,
	 mapper_flags,
	 loader_done,
	 loader_fail,
	 debug_data
	);
	
  wire reset_nes = (kb_reset || !loader_done);
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
                            MWR_N[0], MA[18:0], MD[7:0],
                            debugaddr, debugdata);
  assign MWR_N[1] = 1'b1;
  assign MRD_N = 2'b00;
  assign MA[20:19] = 2'b00;

  reg ramfail;
  always @(posedge clk) begin
    if (loader_reset)
      ramfail <= 0;
    else
      ramfail <= ram_busy && loader_write || ramfail;
  end
				
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
  
  always @(posedge clk) begin
	if (joypad_strobe) begin
		joypad_bits <= nes_joy_l;
		joypad_bits2 <= nes_joy_r;
	end
	
	if (!joypad_clock[0] && last_joypad_clock[0]) begin 
		joypad_bits <= {1'b0, joypad_bits[7:1]};
	end
	if (!joypad_clock[1] && last_joypad_clock[1]) begin
		joypad_bits2 <= {1'b0, joypad_bits2[7:1]};
	end
	last_joypad_clock <= joypad_clock;
  end
  
// ------------ HDMI ----------------

wire [9:0] tmds_red, tmds_green, tmds_blue;

hdmi hdmi(
	.I_CLK_PIXEL(clk_vga),
	.I_R(osd_r),
	.I_G(osd_g),
	.I_B(osd_b),
	.I_BLANK(video_blank),
	.I_HSYNC(video_hsync),
	.I_VSYNC(video_vsync),
	.I_AUDIO_ENABLE(1'b1),
	.I_AUDIO_PCM_L(audio_out_l[15:0]),
	.I_AUDIO_PCM_R(audio_out_r[15:0]),
	.O_RED(tmds_red),
	.O_GREEN(tmds_green),
	.O_BLUE(tmds_blue)
);

wire [9:0] dvi_red, dvi_green, dvi_blue;

dvi dvi(
	.CLK(clk_vga),
	.RESET(areset),
	.RGB({osd_r,osd_g,osd_b}),
	.HSYNC(video_hsync),
	.VSYNC(video_vsync),
	.DE(~video_blank),
	.ENC_RED(dvi_red),
	.ENC_GREEN(dvi_green),
	.ENC_BLUE(dvi_blue)
);

hdmi_out_xilinx hdmiio(
	.clock_pixel_i(clk_vga),
	.clock_tdms_i(clk_hdmi),
	.clock_tdms_n_i(clk_hdmi_n),
	.red_i(dvi_only ? dvi_red : tmds_red),
	.green_i(dvi_only ? dvi_green : tmds_green),
	.blue_i(dvi_only ? dvi_blue : tmds_blue),
	.tmds_out_p(TMDS_P),
	.tmds_out_n(TMDS_N)
);	

endmodule
