# The faithful build: the original's mansion, from your own ROM

*Haunted House: By Matchlight* comes in two builds of one engine. The **shareable** one, which you can
download, has a mansion of our own. The **faithful** one has the original's: the 2600 game's own four floors,
their walls, doors, locks and stairs, and its rules' numbers, read from your copy of the game when you build
it. Everything you see and hear is still our own (the remaster's NES look and soundtrack); only the house and
its numbers are the original's.

It's the build that proves the engine plays exactly like the original, and it's for you alone: nothing from
the 2600 game is in this repository, and the ROM it makes must never be shared.

## What you need

- **Your own copy of Haunted House for the Atari 2600**, the NTSC cartridge (Atari CX2654), as a 4K ROM file:
  MD5 `f0a6e99f5875891246c3dbecbf2d2cea`. That's the one everything was worked out and checked on; the build
  checks the fingerprint and stops with another (its tables are read from fixed places in it).
- **cc65**, the 6502 assembler and linker: `brew install cc65` on a Mac, `apt install cc65` on Linux, or
  https://cc65.github.io.
- **Python 3.10 or newer.**
- **The remaster**, beside this repository: its model of the game, its NES look and its classic pack are
  what the build and its checks are made from.

## Step by step

```sh
# 1. The two repositories, side by side
git clone https://github.com/majonesmax/haunted-house-nes
git clone https://github.com/majonesmax/haunted-house-remastered haunted-house
cd haunted-house-nes

# 2. Python and its packages
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt

# 3. Your ROM, where the remaster keeps it
mkdir -p ../haunted-house/roms
cp /path/to/your/haunted_house.a26 ../haunted-house/roms/haunted_house.a26

# 4. Build it: build/faithful/haunted_house_faithful.nes
.venv/bin/python tools/build.py
```

Step 4 runs everything it needs the first time: `tools/extract.py` reads the original's mansion and tables
from your ROM into `build/faithful/mansion.inc`, `tools/make_art.py` draws the four floors from them, and
`tools/make_music.py` arranges the soundtrack; then the ROM is assembled.

## Playing it

Open `build/faithful/haunted_house_faithful.nes` in any NES emulator, or play it here with the keyboard:

```sh
.venv/bin/python tools/get_core.py      # once: the FCEUmm NES core, into cores/
.venv/bin/python tools/play.py          # (without --shareable: the faithful build)
```

Keys in `tools/play.py`: arrows walk, Space lights a match or puts down what you hold, Enter starts a game, Tab
chooses it (1-9), Z gives a hint (the help, on the title), O is the lights-on cheat, Escape quits.

## Checking it plays like the original

```sh
.venv/bin/python tests/verify_engine.py      # the NES beside the remaster's model, every frame of nine games
.venv/bin/python tests/test_mansion.py       # the mansion's text format gets your ROM's tables back exactly
.venv/bin/python tests/test_hints.py         # the hints say what the remaster's say
```

`verify_engine.py` plays the faithful ROM with a bot and runs the remaster's model of the original beside it
with the same controls, comparing the game's whole state after every frame. It should say every frame was
predicted exactly and none ran late.

## Good to know

- **What's the original's and what isn't.** The house, its locks and stairs per game, the touching shapes and
  the rules' numbers come from your ROM; the pictures, the music, the title, the story, the hints, the
  lights-on cheat and the ending are this project's. The title still says *By Matchlight*.
- **Changed ROM, or something odd?** Delete `build/faithful/` and build again: the extracted mansion and the
  art are made once and kept.
- **Never commit or share** anything in `build/faithful/`: the extracted tables and the ROM built from them
  are the original's.
