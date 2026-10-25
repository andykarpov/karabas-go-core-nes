# Инвентаризация upstream (Ф0, п. 5)

Снято 2026-10-25. Исходники для сравнения берутся вне git: `src/sim/build/upstream/` (клоны ниже), туда же скрипты Ф3 будут класть результат `sv2v`.

| Репозиторий | Коммит | Дата |
|---|---|---|
| [MiSTer-devel/NES_MiSTer](https://github.com/MiSTer-devel/NES_MiSTer) | `49a0a66` | 2026-09-30 |
| [mist-devel/nes](https://github.com/mist-devel/nes) | `c276b36` | 2024-10-08 |

## NES_MiSTer: файлы `rtl/`

«ss» — сколько раз в файле встречается шина снапшотов (`SaveState*`, `SS_*`): есть ли у модуля состояние для save states.

| Файл | Язык | Строк | ss | Что это, что с ним делать |
|---|---|---|---|---|
| `nes.v` | Verilog | 1178 | 142 | Верх NES: CPU, PPU, APU, DMA, cart, шина снапшотов, Vs. System. Переписывать наш `nes.v` по нему (Ф5). |
| `t65/*.vhd` | VHDL | 2546 | 94 | **CPU — T65** (VHDL, с шиной снапшотов). XST берёт как есть. У нас CPU strigeus (`cpu.v` + `MicroCode.v`). |
| `ppu.sv` | SV | 2366 | 264 | PPU. `sv2v` (с `regs_savestates.sv`) переводит без ошибок. 24 tri-state выхода. |
| `apu.sv` | SV | 1290 | 128 | APU. `sv2v` падает: у `DmcChan` параметры `SSREG_INDEX_DMC1/2` без значений по умолчанию — правка вручную перед переводом. |
| `regs_savestates.sv` | SV | 43 | — | Пакет индексов регистров снапшотов (`package`), нужен `sv2v` вместе с модулями. |
| `cart.sv` | SV | 2592 | 348 | Диспетчер мапперов (`cart_top`) и часть мапперов. Выходы мапперов — общие tri-state шины `*_b` (`assign x_b = enable ? x : 'hZ`), без мультиплексора. |
| `mappers/*.sv` (14 файлов) | SV | 12722 | ~2200 | Остальные мапперы: generic, misc, MMC1/2/3/5, VRC, Namco, Sunsoft, Sachen, JYCompany, Mapper99, FDS. |
| `EEPROM_24C0x.sv` | SV | 204 | 43 | I2C EEPROM 24C01 / 24C02 / X24C01 для Bandai (Ф4). |
| `SOUND/OPLL/` (VM2413) | VHDL | ~3500 | 0 | FM-синтез VRC7 (85). VHDL, XST берёт как есть. Без шины снапшотов. |
| `dpram.vhd` | VHDL | 239 | 11 | Обёртка Altera `altsyncram` (+ снапшоты). Заменить на `kg_tdpram` / `kg_sdpram`. |
| `savestates.vhd`, `statemanager.vhd`, `bus_savestates.vhd`, `savestate_ui.sv` | VHDL / SV | 739 | — | Машина снапшотов MiSTer: DMA регистров и памяти в DDR (`Savestate_SDRAM*`). Для нас — образец, буфер в SRAM (Ф6). |
| `sdram.sv`, `ddram.sv` | SV | 411 | — | Память MiSTer. Не нужны: у нас SRAM. |
| `video.sv`, `composite_*.sv` | SV | ~1400 | — | Видео MiSTer и композит. Не нужны (у нас `vga.vhd` + framebuffer). |
| `zapper.sv`, `miracle.sv`, `keyboard.sv` | SV | ~840 | — | Zapper, Miracle Piano, Family BASIC keyboard. Позже, по желанию. |
| `cheatcodes.sv` | SV | 80 | — | Game Genie. Позже, по желанию. |
| `dsp.v`, `compat.v` | Verilog | ~240 | — | Как у нас. |

Интерфейс NES MiSTer к памяти: раздельные порты CPU (`cpumem_*`, адрес 25 бит) и PPU (`ppumem_*`, 22 бита), `prg_mask` / `chr_mask`, переопределение в BRAM (`bram_*`). Наш `MemoryController` даёт одну шину и 22-битный адрес — в Ф1 расширить, чтобы `cart_top` подключался без переделки.

### Шина снапшотов

Каждый модуль с состоянием имеет порты:

```
input  [63:0] SaveStateBus_Din,  input [9:0] SaveStateBus_Adr,  input SaveStateBus_wren,
input         SaveStateBus_rst,  input       SaveStateBus_load, output [63:0] SaveStateBus_Dout
```

Регистры модуля упакованы в 64-битные слова (`SS_MAP1[...]`), индекс слова — из `regs_savestates.sv`. Чтение — `SS_*_BACK`, загрузка по `SaveStateBus_load`. Порты переводятся вместе с модулями сразу (Ф3, п. 3.1), даже если машина снапшотов будет в Ф6.

### Мапперы

`cart.sv` + `mappers/*.sv`: 61 блок «Mappers:» в заголовках, 76 модулей, порядка 120 номеров мапперов (включая 30, 111 с flash-сейвами, 16/153/159 с EEPROM, 20 FDS, 31 NSF). Статус у многих в самом upstream — «Needs evaluation».

### Перевод (проба `sv2v` v0.0.12)

- `cart.sv` + `mappers/*.sv` + `EEPROM_24C0x.sv` → 15 794 строк Verilog-2005 без ошибок (одно предупреждение о литерале в `JYCompany.sv`).
- `ppu.sv` → без ошибок (вместе с `regs_savestates.sv`).
- `apu.sv` → ошибка параметров `DmcChan` (см. выше).
- XST на переведённом `cart_top` (проба 2026-10-25, временные заглушки: `dpram` → инферируемая память, OPLL, `APU` звука MMC5 и `IIR_filter` FDS — пустые). Что пришлось править, по классам:
  1. `SSREG_INDEX_*` не объявлены: часть файлов использует пакет `regs_savestates` без `import` — перед `sv2v` добавить `import regs_savestates::*;` в каждый файл и передать `regs_savestates.sv` первым.
  2. `eReg_SavestateV` — сущность из `bus_savestates.vhd` (VHDL), добавить в prj.
  3. «Procedural assignment to a non-register» (HDLCompiler:1660): `sv2v` оставляет `wire` у сигналов, которые SV присваивает в `always`. ~30 мест, правятся автоматически `src/tools/upstream/fix_wire_reg.py` (итерации: XST → `wire` → `reg` по отчёту).
  4. `tri0` / `tri1` (общие шины диспетчера): XST не синтезирует. Для пробы заменены на `wire`; по-настоящему — мультиплексор по `enable` в диспетчере (Ф3.2).
  5. Смешанные `=` и `<=` одной переменной (HDLCompiler:1511) — 3 места в мапперах, вручную.
  6. VM2413 `controller.vhd`: `array (ch_type'range)` от подтипа integer XST не понимает — вручную, при переносе VRC7.
  7. `APU` нужен и мапперу MMC5 (звук): перевод `apu.sv` (ручная правка параметров `DmcChan`) нужен уже в Ф3, а не только в Ф5.

  После этого XST элаборирует весь `cart_top`, но падает с `INTERNAL_ERROR` (`cmain.c:3423`) на синтезе после `fds_mixed`. **Оценки LUT всего набора мапперов пока нет**: в Ф3 синтезировать мапперы по одному (каждый с мультиплексорным диспетчером), считать LUT по группам и решать, какие брать.

## mist-devel/nes

Более старый форк того же кода (`cart.sv` 1900 строк, те же `mappers/`, `T65`, `OPLL`, свой `GameLoader.sv`). **Снапшотов нет.** Полезен как образец сохранений без HPS: backup RAM пишется через секторный интерфейс `user_io` (`sd_lba`, `sd_rd`, `sd_wr`, `sd_ack`, буфер `sd_buff_*`) по OSD-триггеру `bk_save` и при монтировании образа (`img_mounted`) — это близко к нашему file mounter (`CMD_IMG_*`) и образец для `kg_bk_ram` (Ф2).

## Выводы для плана

1. CPU MiSTer — T65 на VHDL: переносится без перевода. Ф5 — замена нашего CPU на T65 + перевод PPU / APU.
2. Мапперы и `cart_top` переводятся `sv2v` автоматически; ручная работа — tri-state шины `tri0`/`tri1` (XST их не берёт: мультиплексор), `dpram` → `kg_*`, классы правок выше (большая часть автоматизируется). Весь `cart_top` целиком XST не синтезирует (internal error) — переносить мапперы группами, как и планировалось, с замером LUT после каждой.
3. APU требует ручной правки перед `sv2v`.
4. Машину снапшотов MiSTer (DDR) не переносить, а сделать свою на SRAM с той же шиной в модулях.
