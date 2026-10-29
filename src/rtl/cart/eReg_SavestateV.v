// A register of the save state bus of NES_MiSTer (eReg_SavestateV of bus_savestates.vhd) in Verilog:
// word Adr of the bus, loaded by BUS_wren, def after BUS_rst; Dout holds it, BUS_Dout reads back Din.
// With the bus tied off (no save states yet) XST keeps nothing of it but the constant def.
module eReg_SavestateV #(
  parameter        Adr = 0,
  parameter [63:0] def = 64'd0
) (
  input             clk,
  input      [63:0] BUS_Din,
  input       [9:0] BUS_Adr,
  input             BUS_wren,
  input             BUS_rst,
  output     [63:0] BUS_Dout,
  input      [63:0] Din,
  output reg [63:0] Dout = def
);

  always @(posedge clk)
    if (BUS_rst)
      Dout <= def;
    else if (BUS_Adr == Adr && BUS_wren)
      Dout <= BUS_Din;

  assign BUS_Dout = (BUS_Adr == Adr) ? Din : 64'd0;

endmodule
