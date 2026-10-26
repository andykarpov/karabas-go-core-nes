// The dpram of NES_MiSTer (dpram.vhd, an altsyncram BIDIR_DUAL_PORT) on kg_tdpram: two read / write ports, a
// clock of read latency, the new word on a port that writes (NEW_DATA_NO_NBE_READ). Only the parameters the
// mappers use: unregistered outputs, no init file, one byte lane.
module dpram #(
  parameter widthad_a = 8,
  parameter width_a = 8
) (
  input  [widthad_a-1:0] address_a,
  input  [widthad_a-1:0] address_b,
  input                  clock_a,
  input                  clock_b,
  input    [width_a-1:0] data_a,
  input    [width_a-1:0] data_b,
  input                  wren_a,
  input                  wren_b,
  input                  byteena_a,
  input                  byteena_b,
  output   [width_a-1:0] q_a,
  output   [width_a-1:0] q_b
);

  kg_tdpram #(.DW(width_a), .AW(widthad_a), .WRITE_FIRST(1)) ram(
    .clka(clock_a), .ena(1'b1), .wea(wren_a & byteena_a), .addra(address_a), .dina(data_a), .douta(q_a),
    .clkb(clock_b), .enb(1'b1), .web(wren_b & byteena_b), .addrb(address_b), .dinb(data_b), .doutb(q_b));

endmodule
