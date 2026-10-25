// sim_nes.cpp: runs a .nes file on nes_system (tb_nes.v, verilator).
//
// Usage: sim_nes <game.nes> [options]
//   --frames N        stop after N frames (default 600; 0: load only)
//   --blargg          stop when the blargg result protocol says done: $6001..$6003 = DE B0 61 and
//                     $6000 < $80 (the result code; $80 = running, $81 = press reset after 100 ms)
//   --ppm FILE        write the last frame as a PPM (256x240, the palette of rtl/vga/vga.vhd)
//   --ppm-at N FILE   write frame N as well (repeatable)
//   --hash            print the FNV-1a hash of the palette indices of the last frame
//   --joy F:BITS      hold joypad 1 BITS (hex, A B Select Start Up Down Left Right = bits 0..7) from
//                     frame F on (repeatable, a later F replaces it)
//   --trace F N       print the CPU bus accesses of frames F..F+N-1
//   --before GAME:N   first load GAME and run it N frames (the memories keep what it left there, as on the
//                     board when a game is chosen after another one), then load <game.nes> (repeatable)
//
// Exit code: 0 done (blargg result 0, or the frame count reached without --blargg), 1 blargg failure
// code, 2 load error or timeout, 3 usage. The blargg text ($6004..) is printed.
//
// The game goes in as the mcu file loader does: loader_reset, then a byte with a one clock loader_wr
// every 8 clocks (the memory controller takes 4 clocks per write). The frame is taken as vga.vhd writes
// its frame buffer: every clock, the pixel (cycle, scanline) for cycle < 256, scanline < 240.

#include "Vtb_nes.h"
#include "verilated.h"
#include "nes_palette.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>

static Vtb_nes *top;
static uint64_t clocks = 0;

static void tick() {
	top->clk = 0;
	top->eval();
	top->clk = 1;
	top->eval();
	clocks++;
}

static uint8_t prg_ram(int a) {
	top->status_addr = a;
	top->eval();
	return top->status_data;
}

static bool write_ppm(const char *name, const uint8_t *fb) {
	FILE *f = fopen(name, "wb");
	if (!f) { perror(name); return false; }
	fprintf(f, "P6\n256 240\n255\n");
	for (int i = 0; i < 256 * 240; i++) {
		uint32_t c = nes_palette[fb[i] & 63];
		uint8_t rgb[3] = { (uint8_t)(c >> 16), (uint8_t)(c >> 8), (uint8_t)c };
		fwrite(rgb, 1, 3, f);
	}
	fclose(f);
	return true;
}

static std::vector<uint8_t> read_file(const char *name) {
	std::vector<uint8_t> rom;
	FILE *f = fopen(name, "rb");
	if (!f) { perror(name); return rom; }
	int c;
	while ((c = fgetc(f)) != EOF) rom.push_back((uint8_t)c);
	fclose(f);
	return rom;
}

// loads a game as the mcu does (also over a running one)
static bool load(const char *name) {
	std::vector<uint8_t> rom = read_file(name);
	if (rom.empty()) return false;
	top->loader_reset = 1;
	for (int i = 0; i < 16; i++) tick();
	top->loader_reset = 0;
	for (int i = 0; i < 16; i++) tick();
	for (size_t i = 0; i < rom.size(); i++) {
		top->loader_data = rom[i];
		top->loader_wr = 1;
		tick();
		top->loader_wr = 0;
		for (int k = 0; k < 7; k++) tick();
		if (top->loader_fail) break;
	}
	for (int i = 0; i < 64; i++) tick();
	if (top->loader_fail || !top->loader_done) {
		fprintf(stderr, "%s: load %s (%zu bytes)\n", name, top->loader_fail ? "error" : "not done", rom.size());
		return false;
	}
	return true;
}

// runs n frames (the RAM clear after the load, then the game), no joypad
static void run_frames(long n) {
	int last = top->scanline;
	for (long fr = 0; fr < n; ) {
		tick();
		if (top->scanline == 240 && last == 239) fr++;
		last = top->scanline;
	}
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 2) {
		fprintf(stderr, "usage: %s game.nes [--frames N] [--blargg] [--ppm F] [--ppm-at N F] [--hash] [--joy F:BITS]\n", argv[0]);
		return 3;
	}
	const char *rom_name = argv[1];
	long max_frames = 600;
	bool blargg = false, hash = false;
	const char *ppm = nullptr;
	std::map<long, std::string> ppm_at;
	std::map<long, int> joy;
	std::vector<std::pair<std::string, long>> before;
	long trace_from = -1, trace_n = 0;
	for (int i = 2; i < argc; i++) {
		if (!strcmp(argv[i], "--frames") && i + 1 < argc) max_frames = atol(argv[++i]);
		else if (!strcmp(argv[i], "--blargg")) blargg = true;
		else if (!strcmp(argv[i], "--hash")) hash = true;
		else if (!strcmp(argv[i], "--ppm") && i + 1 < argc) ppm = argv[++i];
		else if (!strcmp(argv[i], "--ppm-at") && i + 2 < argc) { long n = atol(argv[++i]); ppm_at[n] = argv[++i]; }
		else if (!strcmp(argv[i], "--joy") && i + 1 < argc) {
			long f; int b;
			if (sscanf(argv[++i], "%ld:%x", &f, &b) != 2) { fprintf(stderr, "bad --joy %s\n", argv[i]); return 3; }
			joy[f] = b;
		}
		else if (!strcmp(argv[i], "--trace") && i + 2 < argc) { trace_from = atol(argv[++i]); trace_n = atol(argv[++i]); }
		else if (!strcmp(argv[i], "--before") && i + 1 < argc) {
			std::string a = argv[++i];
			size_t k = a.rfind(':');
			if (k == std::string::npos) { fprintf(stderr, "bad --before %s\n", a.c_str()); return 3; }
			before.push_back({a.substr(0, k), atol(a.c_str() + k + 1)});
		}
		else if (argv[i][0] == '+') ; // verilator options
		else { fprintf(stderr, "unknown option %s\n", argv[i]); return 3; }
	}

	top = new Vtb_nes;
	top->reset = 0;
	top->joy_l = 0;
	top->joy_r = 0;
	top->loader_wr = 0;
	top->loader_data = 0;
	for (auto &b : before) {
		if (!load(b.first.c_str())) return 2;
		run_frames(b.second);
	}
	if (!load(rom_name)) return 2;

	// the loader result (check_loader.py compares it with the header and the file)
	printf("loaded: crc %08x flags %016llx\n", top->rom_crc, (unsigned long long)top->mapper_flags);

	static uint8_t fb[256 * 240];
	memset(fb, 0, sizeof fb);
	long frame = 0;
	int last_scanline = top->scanline;
	int result = -1;
	// the reset of the blargg protocol: held for 100 ms of clk (the PPU stops while it is held, so the
	// frames do not count it); the run also ends after the clocks of max_frames frames plus resets
	const uint64_t clk_hz = 21511628, frame_clocks = clk_hz / 60;
	uint64_t reset_until = 0, resets = 0;
	long released = -100; // the frame after the last release: $81 stays until the ROM writes $80 again
	const uint64_t start = clocks; // after the games of --before
	while (frame < max_frames && clocks - start < (max_frames + resets * 6 + 60) * frame_clocks) {
		tick();
		if (reset_until && clocks >= reset_until) {
			top->reset = 0;
			reset_until = 0;
			released = frame;
		}
		int x = top->cycle, y = top->scanline;
		if (x < 256 && y < 240) fb[y * 256 + x] = top->color;
		if (y == 240 && last_scanline == 239) {
			frame++;
			top->trace_on = frame >= trace_from && frame < trace_from + trace_n;
			auto j = joy.find(frame);
			if (j != joy.end()) top->joy_l = j->second;
			auto p = ppm_at.find(frame);
			if (p != ppm_at.end()) write_ppm(p->second.c_str(), fb);
			if (blargg && prg_ram(1) == 0xDE && prg_ram(2) == 0xB0 && prg_ram(3) == 0x61) {
				int st = prg_ram(0);
				if (st < 0x80) { result = st; break; }
				// $81: press reset (100 ms, as the reset button) once for each request
				if (st == 0x81 && !reset_until && !top->reset && frame > released + 10) {
					top->reset = 1;
					reset_until = clocks + clk_hz / 10;
					resets++;
					fprintf(stderr, "reset at frame %ld\n", frame);
				}
			}
		}
		last_scanline = y;
	}

	if (ppm) write_ppm(ppm, fb);
	if (hash) {
		uint32_t h = 2166136261u;
		for (int i = 0; i < 256 * 240; i++) { h ^= fb[i]; h *= 16777619u; }
		printf("frame hash %08x\n", h);
	}
	if (blargg) {
		std::string text;
		for (int a = 4; a < 0x1000; a++) {
			uint8_t ch = prg_ram(a);
			if (!ch) break;
			text += (char)ch;
		}
		while (!text.empty() && (text.back() == '\n' || text.back() == ' ')) text.pop_back();
		printf("%s: frames %ld, result %s%d\n%s\n", rom_name, frame, result < 0 ? "timeout " : "", result,
			text.c_str());
		delete top;
		return result < 0 ? 2 : result == 0 ? 0 : 1;
	}
	printf("%s: frames %ld\n", rom_name, frame);
	delete top;
	return 0;
}
