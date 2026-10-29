# Список поддерживаемых мапперов ядра NES

В ядре Karabas-Go NES мапперы работают через гибридный диспетчер в `nes.v`:
1. При попадании номера маппера в список `cart_hit` управление передаётся в модуль `cart_top` (`src/rtl/cart/cart.v`), перенесённый и сгенерированный из [MiSTer-devel/NES_MiSTer](https://github.com/MiSTer-devel/NES_MiSTer).
2. Для остальных мапперов используется встроенный диспетчер `MultiMapper` (`src/rtl/nes/mmu.v`), основанный на кодовой базе FPGANES (Ludvig Strigeus).

---

## 1. Мапперы из NES_MiSTer (`src/rtl/cart/cart.v`)

Генерируются скриптом `src/tools/upstream/gen_cart.py` на основе исходников MiSTer (`cart.sv` и `mappers/*.sv`) с трансляцией через `sv2v`.

| iNES # | Название / Чип | Дополнительный звук | Популярные игры / Примеры |
|:------:|:----------------|:-------------------:|:---------------------------|
| **18** | Jaleco SS88006 | — | *Pizza Pop!*, *The Lord of King (Astyanax)*, *Magic John* |
| **19** | Namco 163 (129) | **8-канальный табличный звук (N163)** | *Final Lap*, *Megami Tensei II*, *Mappy Kids*, *Rolling Thunder* |
| **21** | Konami VRC4a, VRC4c | — | *Wai Wai World 2*, *Ganbare Goemon Gaiden 2* |
| **22** | Konami VRC2a | — | *TwinBee 3* |
| **23** | Konami VRC2b, VRC4e, VRC4f | — | *Akumajou Special: Boku Dracula-kun*, *Crisis Force*, *Tiny Toon Adventures* |
| **24** | Konami VRC6a | **Синтез VRC6 (2 пульса + пила)** | *Akumajou Densetsu (Castlevania III JP)* |
| **25** | Konami VRC4b, VRC4d | — | *Gradius II*, *Bio Miracle Bokutte Upa*, *Ganbare Goemon 2* |
| **26** | Konami VRC6b | **Синтез VRC6 (2 пульса + пила)** | *Madara*, *Esper Dream 2* |
| **27** | Konami VRC4 (World Hero) | — | *World Hero* |
| **30** | UNROM-512 | — | *Micro Mages*, *Lizard*, *Black Box Challenge*, современные homebrew-игры |
| **32** | Irem G-101 | — | *Image Fight*, *Major League*, *Kaiketsu Yanchamaru 2* |
| **65** | Irem H-3001 | — | *Spartan X 2*, *Daiku no Gen-san 2*, *Kaitei Daisensou* |
| **67** | Sunsoft-3 | — | *Fantasy Zone 2* |
| **68** | Sunsoft-4 | — | *After Burner II*, *Maharaja* |
| **69** | Sunsoft-5A, 5B, FME-7 | **Синтез 5B (3 канала SSG / YM2149)** | *Gimmick!*, *Batman: Return of the Joker*, *Hebereke* |
| **70** | Irem 74HC161/32 (вариант) | — | *Kamen Rider Club*, *Space Hunter* |
| **73** | Konami VRC3 | — | *Salamander* |
| **75** | Konami VRC1 | — | *Tetsuwan Atom (Astro Boy)*, *Ganbare Goemon!* |
| **78** | Irem 74HC161/32 | — | *Holy Diver*, *Cosmo Carrier*, *Uchuu Keibi-tai SDF* |
| **81** | Irem 74HC161/32 (вариант) | — | *Monopoly* |
| **89** | Sunsoft дискретный (верт.) | — | *Mito Koumon* |
| **93** | Sunsoft дискретный | — | *Fantasy Zone* |
| **111** | GTROM | — | *Cheapocabra*, *Spook-o'-Tron* |
| **152** | Irem 74HC161/32 (вариант) | — | *Saint Seiya: Ougon Densetsu* |
| **184** | Sunsoft дискретный | — | *Wing of Madoola* |
| **190** | Sunsoft-3 (вариант) | — | *Magic John (bootleg)* |
| **210** | Namco 175, 340 | — | *Chibi Maruko-chan*, *Famista '91-'92*, *Splatterhouse: Wanpaku Graffiti* |

---

## 2. Базовые мапперы ядра FPGANES (`src/rtl/nes/mmu.v`)

Реализация FPGANES (Ludvig Strigeus) с доработками для Karabas-Go.

| iNES # | Название / Чип | Популярные игры / Описание |
|:------:|:----------------|:---------------------------|
| **0** | NROM | *Super Mario Bros.*, *Pac-Man*, *Duck Hunt*, *Bomberman* |
| **1** | MMC1 (SxROM, SNROM, SUROM) | *The Legend of Zelda*, *Metroid*, *Mega Man 2*, *Tetris* |
| **2** | UxROM (UNROM, UOROM) | *Contra*, *Castlevania*, *Duck Tales*, *Mega Man 1* |
| **3** | CNROM | *Gradius*, *Solomon's Key*, *Arkanoid* |
| **4** | MMC3 (TxROM, HKROM) | *Super Mario Bros. 3*, *Mega Man 3-6*, *Kirby's Adventure*, *Ninja Gaiden 1-3* |
| **5** | MMC5 (ExROM) | *Castlevania III (US)*, *Just Breed*, *Romance of the Three Kingdoms II* |
| **7** | AxROM (AMROM, AOROM) | *Battletoads*, *Marble Madness*, *Double Dragon 2 (bootleg)* |
| **9** | MMC2 (PxROM) | *Mike Tyson's Punch-Out!!* |
| **10** | MMC4 (FxROM) | *Fire Emblem*, *Fire Emblem Gaiden*, *Famicom Wars* |
| **11** | Color Dreams | *Crystal Mines*, *Baby Boomer*, *Captain Comic* |
| **13** | CPROM | *Videomation* |
| **15** | 100-in-1 multicart | Сборники пиратских многоигровок |
| **28** | Action 53 | Современные сборники композитов homebrew |
| **34** | BNROM / NINA-001 | *Deadly Towers*, *Impossible Mission II* |
| **41** | Caltron 6-in-1 | Сборник *Caltron 6 in 1* |
| **64** | RAMBO-1 | *Klax*, *Skull & Crossbones*, *Hard Drivin'* |
| **66** | GxROM / MHROM | *Super Mario Bros. / Duck Hunt*, *Doraemon* |
| **71** | Camerica / Codemasters | *Micro Machines*, *Fire Hawk*, *The Fantastic Adventures of Dizzy* |
| **79** | AVE NINA-03 / NINA-06 | *Krazy Kreatures*, *Dudes with Attitude*, *F-15 City War* |
| **105** | NES-EVENT | *Nintendo World Championships 1990* |
| **118** | TxSROM (MMC3 variant) | *Armadillo*, *Ys III: Wanderers from Ys*, *Goal! Two* |
| **119** | TQROM (MMC3 variant) | *High Stakes Gambling*, *Pinbot* |
| **158** | RAMBO-1 variant | *Alien Syndrome* |
| **228** | Active Enterprises | *Action 52*, *Cheetahmen II* |
| **234** | Maxi 15 | Сборник *Maxi 15* |

---

## 3. Источники кодовой базы

1. **[MiSTer-devel/NES_MiSTer](https://github.com/MiSTer-devel/NES_MiSTer)** (коммит `49a0a66`):
   - Исходники всех мапперов `cart.sv` и `mappers/*.sv`.
   - Звуковые модули расширения картриджей: VRC6 (`snd_vrc6.sv`), Namco 163 (`n163.sv`), Sunsoft 5B (`snd_5bm.sv`).
   - Логика мапперов сохранений (savestates bus ports).
2. **FPGANES** (Ludvig Strigeus, 2012–2013):
   - Базовая архитектура ядра (`cpu.v`, `MicroCode.v`, `ppu.v`, `apu.v`, `mmu.v`).
3. **Karabas-Go Framework** (`modules/`):
   - Контроллер памяти SRAM (`kg_spram`, `kg_sdpram`, `kg_tdpram`).
   - Модули связи с MCU RP2040 (`kg_mcu_*`).
   - Модули энергонезависимых сохранений (`kg_bk_ram`).
