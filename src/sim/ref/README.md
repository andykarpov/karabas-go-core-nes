# Reference models

`ipcore/`: the coregen cores this core used before the `kg_*` modules of `modules/` replaced them
(`ram2k`, `ram8k`, `framebuffer`, `rom_font` with `rom_font.mif`, `osd_vram`, `nes_clk`, `pllx5`),
the behavioural Verilog models of the removed `ipcore_dir`. `modules/sim/ipcore_eq` compares the
`kg_*` memories and clocks against them.
