# Karabas Go NES Core

NES core port to Karabas Go based on FPGANES project port to ZXDOS+.

## How to start:

1. Put some iNES games into the /nes/ directory on the SD1
2. Use Menu+ESC (or Start+C) to show the file selector OSD, use Enter (or A/B) to load file
3. Use your MD2 joypads or keyboard to play a game

### Keyboard joypads:

- WASDZXCV for Up/Left/Down/Right/A/B/Start/Select
- IJKLOPNM for Up/Left/Down/Right/A/B/Start/Select

### Additional notes and limits:

1. NES filenames should be max 32 characters long
2. The core supports max 256 nes files
3. First boot will take some time to read a file list and create index.db file
4. To recreate the index press R on the keyboard
5. F12 reboots the core
