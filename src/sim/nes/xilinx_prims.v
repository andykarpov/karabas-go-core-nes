`timescale 1ns / 1ps

/*
 xilinx_prims.v: behavioural models of the Spartan-6 carry chain primitives that rtl/nes/cpu.v
 instantiates (MyAddSub), for the verilator simulation (the unisim models have timing checks).
 MUXCY: O = S ? CI : DI. XORCY: O = CI ^ LI.
*/
module MUXCY (output O, input CI, input DI, input S);
assign O = S ? CI : DI;
endmodule

module MUXCY_L (output LO, input CI, input DI, input S);
assign LO = S ? CI : DI;
endmodule

module MUXCY_D (output O, output LO, input CI, input DI, input S);
assign O = S ? CI : DI;
assign LO = O;
endmodule

module XORCY (output O, input CI, input LI);
assign O = CI ^ LI;
endmodule

module XOR2 (output O, input I0, input I1);
assign O = I0 ^ I1;
endmodule
