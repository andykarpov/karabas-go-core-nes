`timescale 1ns / 1ps
// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

// karabas: the 4 MB SRAM of memorycontroller.v, NES 2.0, trainers, 64 bit flags of NES_MiSTer
//
// Reads the bytes of a .nes file and writes them to the memory: PRG ROM from 0x000000, CHR ROM from 0x200000,
// a trainer (512 bytes before the PRG ROM) to $7000 of the PRG RAM (0x3C1000). Done when the PRG and CHR ROM
// are in; the bytes after them (misc ROM of NES 2.0) are ignored. Error: no "NES<1A>" header, or a PRG ROM
// of more than 2 MB or a CHR ROM of more than 1 MB (the SRAM regions).
//
// Header: iNES 1.0, NES 2.0 (byte 7 bits 3:2 = 10): mapper bits 11:8 and submapper (byte 8), the high bits of
// the PRG / CHR sizes (byte 9; F = exponent form), PRG RAM / NVRAM (byte 10), CHR RAM (byte 11), region (12).
// An iNES 1.0 header with junk in bytes 8-15 ("DiskDude!") is taken as mapper bits 3:0 only, as before.
//
// rom_crc: the CRC-32 (IEEE 802.3, as zlib) of the PRG and CHR ROM bytes, without header and trainer; for the
// header of the save states. Valid with done.
//
// prg_mask / chr_mask: the 2 KB pages of the PRG ROM and the CHR ROM (or RAM) as the mask of the address bits
// 20:11, for the mappers of NES_MiSTer (rtl/cart/cart.v), as its loader makes them.
//
// mapper_flags, the layout of NES_MiSTer (bits 16:0 as the mappers here have always had them):
//   [7:0] mapper, [10:8] prg_size, [13:11] chr_size (log2 of 16K / 8K pages, max 7), [14] mirroring (1 =
//   vertical), [15] CHR RAM, [16] four screen, [24:17] NES 2.0 byte 8 (submapper, mapper bits 11:8), [25]
//   battery, [29:26] PRG RAM shift (64 << n, NES 2.0), [34:31] PRG NVRAM shift, [35] NES 2.0, [37:36] region
//   (0 NTSC, 1 PAL, 2 multi, 3 Dendy), [44:43] console type; the others 0.
module GameLoader(input clk, input reset,
                  input [7:0] indata, input indata_clk,
                  output reg [21:0] mem_addr, output [7:0] mem_data, output mem_write,
                  output [63:0] mapper_flags,
                  output reg done,
                  output error,
                  output trainer,
                  output reg [31:0] rom_crc,   // CRC-32 of the PRG and CHR ROM (as the ROM databases)
                  output [9:0] prg_mask,
                  output [9:0] chr_mask,
						output [15:0] debug_data);
  reg [2:0] state = 0;
  reg [3:0] ctr;
  reg [7:0] ines[0:15]; // 16 bytes of iNES header
  reg [21:0] bytes_left;

  localparam S_HEADER = 0, S_TRAINER = 1, S_PRG = 2, S_CHR = 3, S_DONE = 4, S_ERROR = 5;

  wire is_nes20 = (ines[7][3:2] == 2'b10);
  // differentiate dirty iNES1.0 headers from proper iNES2.0 ones
  wire is_dirty = !is_nes20 && ((ines[8]  != 0)
									  || (ines[9]  != 0)
									  || (ines[10] != 0)
									  || (ines[11] != 0)
									  || (ines[12] != 0)
									  || (ines[13] != 0)
									  || (ines[14] != 0)
									  || (ines[15] != 0));

  // sizes in bytes (27 bits: the exponent form can say more than the SRAM has, then it is an error)
  wire [3:0] prg_msb = is_nes20 ? ines[9][3:0] : 4'h0;
  wire [3:0] chr_msb = is_nes20 ? ines[9][7:4] : 4'h0;
  wire [26:0] prg_bytes = (prg_msb == 4'hF) ? ({24'd0, ines[4][1:0], 1'b1} << ines[4][7:2]) : {1'b0, prg_msb, ines[4], 14'b0};
  wire [26:0] chr_bytes = (chr_msb == 4'hF) ? ({24'd0, ines[5][1:0], 1'b1} << ines[5][7:2]) : {2'b0, chr_msb, ines[5], 13'b0};
  wire too_big = (prg_bytes > 27'h200000) || (chr_bytes > 27'h100000);
  wire [11:0] prgrom = prg_bytes[25:14];  // 16 KB pages (exponent form: rounded down)
  wire [11:0] chrrom = chr_bytes[24:13];  // 8 KB pages

  wire has_chr_ram = is_nes20 ? (ines[11][3:0] != 0 || chr_bytes == 0) : (chrrom == 0);

  // the mask of NES_MiSTer: bit i set if the size is more than 2 KB << i
  function [9:0] mask(input [26:0] size);
    integer i;
    begin
      for (i = 0; i < 10; i = i + 1)
        mask[i] = (size[26:11] > (16'd1 << i));
    end
  endfunction
  wire [26:0] chr_ram_bytes = is_nes20 ? (27'd64 << ines[11][3:0]) : 27'h2000;
  assign prg_mask = mask(prg_bytes);
  assign chr_mask = mask(chr_bytes != 0 ? chr_bytes : chr_ram_bytes);
  assign trainer = ines[6][2];

  wire [2:0] prg_size = prgrom <= 1  ? 0 :
                        prgrom <= 2  ? 1 :
                        prgrom <= 4  ? 2 :
                        prgrom <= 8  ? 3 :
                        prgrom <= 16 ? 4 :
                        prgrom <= 32 ? 5 :
                        prgrom <= 64 ? 6 : 7;

  wire [2:0] chr_size = chrrom <= 1  ? 0 :
                        chrrom <= 2  ? 1 :
                        chrrom <= 4  ? 2 :
                        chrrom <= 8  ? 3 :
                        chrrom <= 16 ? 4 :
                        chrrom <= 32 ? 5 :
                        chrrom <= 64 ? 6 : 7;

  // Read the mapper number
  wire [7:0] mapper = {is_dirty ? 4'b0000 : ines[7][7:4], ines[6][7:4]};

  assign mapper_flags[63:45] = 0;
  assign mapper_flags[44:43] = is_nes20 ? ines[7][1:0] : 2'd0;     // console type
  assign mapper_flags[42:38] = 0;
  assign mapper_flags[37:36] = is_nes20 ? ines[12][1:0] : 2'd0;    // region
  assign mapper_flags[35]    = is_nes20;
  assign mapper_flags[34:31] = is_nes20 ? ines[10][7:4] : 4'd0;    // PRG NVRAM shift
  assign mapper_flags[30]    = 1'b0;
  assign mapper_flags[29:26] = is_nes20 ? ines[10][3:0] : 4'd0;    // PRG RAM shift
  assign mapper_flags[25]    = ines[6][1];                          // battery
  assign mapper_flags[24:17] = is_nes20 ? ines[8] : 8'd0;           // submapper, mapper bits 11:8
  assign mapper_flags[16:0]  = {ines[6][3], has_chr_ram, ines[6][0], chr_size, prg_size, mapper};

  assign error = (state == S_ERROR);
  assign mem_data = indata;
  assign mem_write = (bytes_left != 0) && (state == S_TRAINER || state == S_PRG || state == S_CHR) && indata_clk;

  assign debug_data = {ines[0], ines[6]};

  // CRC-32, reflected, polynomial EDB88320, a byte per clock
  function [31:0] crc32_byte(input [31:0] c, input [7:0] d);
    integer i;
    reg [31:0] r;
    begin
      r = c ^ {24'd0, d};
      for (i = 0; i < 8; i = i + 1)
        r = r[0] ? (r >> 1) ^ 32'hEDB88320 : r >> 1;
      crc32_byte = r;
    end
  endfunction
  reg [31:0] crc;
  always @(posedge clk) begin
    if (reset)
      crc <= 32'hFFFFFFFF;
    else if (mem_write && (state == S_PRG || state == S_CHR))
      crc <= crc32_byte(crc, indata);
    rom_crc <= ~crc;
  end

  always @(posedge clk) begin
    if (reset) begin
      state <= S_HEADER;
      done <= 0;
      ctr <= 0;
      bytes_left <= 0;
    end else begin
      case(state)
      // Read 16 bytes of ines header
      S_HEADER: if (indata_clk) begin
           ctr <= ctr + 1;
           ines[ctr] <= indata;
           if (ctr == 4'b1111) begin
             // the header bytes are in ines[] from the next clock: decide in S_TRAINER with bytes_left 0
             state <= S_TRAINER;
             bytes_left <= 0;
           end
         end
      S_TRAINER, S_PRG, S_CHR: begin // Read the next |bytes_left| bytes into |mem_addr|
          if (bytes_left != 0) begin
            if (indata_clk) begin
              bytes_left <= bytes_left - 1;
              mem_addr <= mem_addr + 1;
            end
          end else if (state == S_TRAINER && ctr == 4'b0000) begin
            // just after the header: check it, then the trainer or the PRG ROM
            ctr <= 4'b0001;
            if (!((ines[0] == 8'h4E) && (ines[1] == 8'h45) && (ines[2] == 8'h53) && (ines[3] == 8'h1A)) || too_big)
              state <= S_ERROR;
            else if (trainer) begin
              mem_addr <= 22'h3C1000;                   // $7000 of the PRG RAM
              bytes_left <= 22'd512;
            end
          end else if (state == S_TRAINER) begin
            state <= S_PRG;
            mem_addr <= 22'h000000;                     // Address for PRG
            bytes_left <= prg_bytes[21:0];
          end else if (state == S_PRG) begin
            state <= S_CHR;
            mem_addr <= 22'h200000;                     // Address for CHR
            bytes_left <= chr_bytes[21:0];
          end else begin
            state <= S_DONE;
            done <= 1;
          end
        end
      default: ;
      endcase
    end
  end
endmodule
