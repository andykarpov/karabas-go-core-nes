-------------------------------------------------------------------------------
-- Testbench: mcu.vhd burst transfers and capability query (NES / Alf mcu)
-- (karabas-go-firmware docs/burst_protocol.md)
--
-- Plays the RP2040 side: classic 3-byte frames on MCU_SS (16 MHz) and bursts
-- on MCU_BURST_CS_N (BURST_SCK_HALF_PS), mcu CLK from CLK_PERIOD_PS. Checks
-- the CMD_CAPS answer and every ROMLOAD / FILELOAD write. Run with
-- run_burst_sim.sh (ISim).
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_mcu_burst is
	generic (
		CLK_PERIOD_PS     : integer := 46560; -- mcu clock (46560 = 21.477 MHz)
		BURST_SCK_HALF_PS : integer := 31250; -- burst SCK half period (31250 = 16 MHz, 15625 = 32 MHz)
		MAX_MHZ           : integer := 0      -- BURST_MAX_MHZ of the DUT, expected in the CMD_CAPS answer
	);
end tb_mcu_burst;

architecture sim of tb_mcu_burst is

	constant CLK_PERIOD : time := CLK_PERIOD_PS * 1 ps;
	constant SCK_HALF   : time := 31.25 ns;  -- 16 MHz, classic frames
	constant BURST_HALF : time := BURST_SCK_HALF_PS * 1 ps;

	signal clk       : std_logic := '0';
	signal n_reset   : std_logic := '0';
	signal sck       : std_logic := '0';
	signal mosi      : std_logic := '0';
	signal miso      : std_logic;
	signal ss_n      : std_logic := '1';
	signal bcs_n     : std_logic := '1';
	signal ready     : std_logic;

	signal rl_active : std_logic;
	signal rl_addr   : std_logic_vector(31 downto 0);
	signal rl_data   : std_logic_vector(7 downto 0);
	signal rl_wr     : std_logic;
	signal fl_addr   : std_logic_vector(31 downto 0);
	signal fl_data   : std_logic_vector(7 downto 0);
	signal fl_wr     : std_logic;

	signal done      : boolean := false;

	-- write log: 0 = rom loader, 1 = file loader
	type wr_addr_t is array (0 to 2047) of std_logic_vector(31 downto 0);
	type wr_data_t is array (0 to 2047) of std_logic_vector(7 downto 0);
	type wr_kind_t is array (0 to 2047) of integer;
	signal wr_addr   : wr_addr_t;
	signal wr_data   : wr_data_t;
	signal wr_kind   : wr_kind_t;
	signal wr_count  : integer := 0;

	type byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

begin

	clk <= not clk after CLK_PERIOD / 2 when not done;

	DUT: entity work.mcu
	generic map (
		BURST_MAX_MHZ => MAX_MHZ
	)
	port map (
		CLK => clk,
		N_RESET => n_reset,
		MCU_MOSI => mosi,
		MCU_MISO => miso,
		MCU_SCK => sck,
		MCU_SS => ss_n,
		MCU_SPI_FT_SS => '1',
		MCU_SPI_SD2_SS => '1',
		MCU_BURST_CS_N => bcs_n,
		MCU_BURST_READY => ready,
		ROMLOADER_ACTIVE => rl_active,
		ROMLOAD_ADDR => rl_addr,
		ROMLOAD_DATA => rl_data,
		ROMLOAD_WR => rl_wr,
		FILELOAD_ADDR => fl_addr,
		FILELOAD_DATA => fl_data,
		FILELOAD_WR => fl_wr
	);

	process (clk)
	begin
		if rising_edge(clk) then
			if rl_wr = '1' and rl_active = '1' then
				wr_addr(wr_count) <= rl_addr;
				wr_data(wr_count) <= rl_data;
				wr_kind(wr_count) <= 0;
				wr_count <= wr_count + 1;
			elsif fl_wr = '1' then
				wr_addr(wr_count) <= fl_addr;
				wr_data(wr_count) <= fl_data;
				wr_kind(wr_count) <= 1;
				wr_count <= wr_count + 1;
			end if;
			assert not (rl_wr = '1' and rl_active = '1' and fl_wr = '1') report "rom and file write in the same clock" severity error;
		end if;
	end process;

	stimulus: process

		procedure spi_byte_at(tx : in std_logic_vector(7 downto 0); rx : out std_logic_vector(7 downto 0); half : in time) is
			variable r : std_logic_vector(7 downto 0);
		begin
			for i in 7 downto 0 loop
				mosi <= tx(i);
				wait for half;
				sck <= '1';
				r(i) := miso;
				wait for half;
				sck <= '0';
			end loop;
			rx := r;
		end procedure;

		procedure frame(c, a, d : in std_logic_vector(7 downto 0); rc, ra, rd : out std_logic_vector(7 downto 0)) is
		begin
			ss_n <= '0';
			wait for 100 ns;
			spi_byte_at(c, rc, SCK_HALF);
			spi_byte_at(a, ra, SCK_HALF);
			spi_byte_at(d, rd, SCK_HALF);
			wait for 50 ns;
			ss_n <= '1';
			wait for 500 ns;
		end procedure;

		procedure burst(btype : in std_logic_vector(7 downto 0); addr : in unsigned(31 downto 0); data : in byte_array) is
			variable dummy : std_logic_vector(7 downto 0);
			variable a : std_logic_vector(31 downto 0);
		begin
			if ready /= '1' then
				wait until ready = '1';
			end if;
			a := std_logic_vector(addr);
			bcs_n <= '0';
			wait for 100 ns;
			spi_byte_at(btype, dummy, BURST_HALF);
			spi_byte_at(a(31 downto 24), dummy, BURST_HALF);
			spi_byte_at(a(23 downto 16), dummy, BURST_HALF);
			spi_byte_at(a(15 downto 8), dummy, BURST_HALF);
			spi_byte_at(a(7 downto 0), dummy, BURST_HALF);
			for i in data'range loop
				spi_byte_at(data(i), dummy, BURST_HALF);
			end loop;
			bcs_n <= '1';
			wait for 1 us;
		end procedure;

		procedure expect_writes(first : in integer; kind : in integer; addr : in unsigned(31 downto 0); data : in byte_array) is
		begin
			for i in data'range loop
				assert wr_kind(first + i) = kind
					report "write " & integer'image(first + i) & ": wrong loader" severity error;
				assert wr_addr(first + i) = std_logic_vector(addr + to_unsigned(i, 32))
					report "write " & integer'image(first + i) & ": wrong address" severity error;
				assert wr_data(first + i) = data(i)
					report "write " & integer'image(first + i) & ": wrong data" severity error;
			end loop;
		end procedure;

		variable rc, ra, rd : std_logic_vector(7 downto 0);
		variable caps_seen : boolean := false;
		variable before : integer;
		constant d16 : byte_array(0 to 15) := (x"AA", x"55", x"01", x"02", x"03", x"04", x"05", x"06",
		                                       x"F0", x"0F", x"80", x"7F", x"00", x"FF", x"12", x"34");
		variable d512 : byte_array(0 to 511);

	begin
		n_reset <= '0';
		wait for 1 us;
		n_reset <= '1';
		wait for 2 us;

		-- 1. capability query
		frame(x"F7", x"00", x"01", rc, ra, rd);
		for i in 1 to 8 loop
			frame(x"FF", x"00", x"00", rc, ra, rd);
			if rc = x"F7" then
				caps_seen := true;
				assert ra = x"03" report "caps: expected 03" severity error;
				assert rd = std_logic_vector(to_unsigned(MAX_MHZ, 8)) report "caps: wrong max_mhz" severity error;
				report "caps answer after " & integer'image(i) & " polls";
				exit;
			end if;
		end loop;
		assert caps_seen report "no CMD_CAPS answer" severity error;

		-- 2. rom burst (rom loader active)
		frame(x"08", x"00", x"01", rc, ra, rd);
		before := wr_count;
		burst(x"07", x"00001234", d16);
		assert wr_count - before = 16 report "rom burst: expected 16 writes, got " & integer'image(wr_count - before) severity error;
		expect_writes(before, 0, x"00001234", d16);
		frame(x"08", x"00", x"00", rc, ra, rd); -- rom loader off

		-- 3. file burst (cartridge from the file loader), from address 0
		frame(x"0E", x"00", x"03", rc, ra, rd); -- file loader: active + reset
		frame(x"0E", x"00", x"02", rc, ra, rd); -- active
		before := wr_count;
		burst(x"0D", x"00000000", d16);
		assert wr_count - before = 16 report "file burst: expected 16 writes, got " & integer'image(wr_count - before) severity error;
		expect_writes(before, 1, x"00000000", d16);

		-- 4. classic file frames still work after a burst
		before := wr_count;
		frame(x"0C", x"00", x"01", rc, ra, rd); -- filebank addr[15:8] = 01
		frame(x"0C", x"01", x"00", rc, ra, rd);
		frame(x"0C", x"02", x"00", rc, ra, rd);
		frame(x"0D", x"10", x"5A", rc, ra, rd); -- filedata 0x00000110 = 5A
		wait for 1 us;
		assert wr_count - before = 1 report "classic file: expected 1 write" severity error;
		assert wr_kind(before) = 1 and wr_addr(before) = x"00000110" and wr_data(before) = x"5A" report "classic file: wrong write" severity error;

		-- 5. unknown burst type: ignored
		before := wr_count;
		burst(x"55", x"00003000", d16);
		assert wr_count = before report "unknown type: unexpected writes" severity error;

		-- 6. full size file burst (512 bytes)
		for i in d512'range loop
			d512(i) := std_logic_vector(to_unsigned((i * 7 + 3) mod 256, 8));
		end loop;
		before := wr_count;
		burst(x"0D", x"00000200", d512);
		assert wr_count - before = 512 report "file burst 512: expected 512 writes, got " & integer'image(wr_count - before) severity error;
		expect_writes(before, 1, x"00000200", d512);
		frame(x"0E", x"00", x"00", rc, ra, rd); -- file loader off

		report "tb_mcu_burst: finished, " & integer'image(wr_count) & " writes";
		done <= true;
		wait;
	end process;

end sim;
