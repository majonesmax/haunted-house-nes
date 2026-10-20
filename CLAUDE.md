# Working on Haunted House for the NES with an AI assistant

Notes for Claude Code (or any coding assistant); for people, a quick tour. The plan and its steps:
[docs/plan.md](docs/plan.md).

This is a native NES game written in 6502 assembly (ca65), from the rules in the remaster's
`../haunted-house/docs/spec.md` and its models (`game/player.py`, `game/monsters.py`, `game/sounds.py`), which
predict the original game exactly. Python here is for tools and checks only.

## Commands

```sh
.venv/bin/python tools/extract.py        # the original mansion from your 2600 ROM -> build/faithful/ (never commit)
.venv/bin/python tools/make_art.py       # the tiles and sprites from the remaster's NES look -> build/art/
.venv/bin/python tools/make_music.py     # the soundtrack and effects from the remaster's -> build/sound/
.venv/bin/python tools/build.py          # build/faithful/haunted_house_faithful.nes (ca65 + ld65, src/mmc3.cfg)
.venv/bin/python tools/build.py --shareable   # build/shareable/haunted_house.nes: our mansion, nothing from the ROM
                                         # (the other tools and tests take --shareable too)
.venv/bin/python tools/get_core.py       # the FCEUmm core into cores/ (libretro's nightly)
.venv/bin/python tools/check_mansion.py  # mansion/floors.txt plays as the original does (after any change to it)
.venv/bin/python tools/draw_mansion.py   # its plans as a picture: shots/mansion.png
.venv/bin/python tests/test_mansion.py   # the text format gets the original's tables back exactly
.venv/bin/python tests/test_check_mansion.py  # the checker catches broken mansions
.venv/bin/python tools/record_sound.py NAME 30 6:start 600   # play some frames, save shots/sound/NAME.wav
.venv/bin/python tools/screenshot.py NAME 30 6:start 60   # play some frames, save shots/NAME.png
.venv/bin/python tools/profile.py 30 6:start 30 5:a      # cycles per routine for one frame (py65)
.venv/bin/python tests/test_boot.py      # it boots in the emulator (tools/nes.py, FCEUmm in cores/)
.venv/bin/python tests/verify_engine.py  # the engine against the remaster's model, frame by frame (run it after
                                         # any change to src/, on both builds; it also fails if a frame runs
                                         # late - the NES counts them, and its spare time, in late_frames)
.venv/bin/python tests/test_hints.py     # B's hints and the two notes say what the remaster's say, in random scenes
.venv/bin/python tools/readability.py    # the Python readability rules (a hook runs it after each edit)
```

## Rules

- **Write the engine from the spec and the models, never from the disassembly.** The original's code is
  Atari's; the rules aren't.
- **Never commit anything from the 2600 ROM**: its tables, its pictures, or a faithful build. They're made in
  `build/faithful/` from the user's own ROM and stay there. The shareable build (`build/shareable/`) must
  hold nothing from it: its mansion, shapes and numbers are our own (`tools/shareable.py`).
- **Change the mansion as text**: `mansion/floors.txt`, then `tools/check_mansion.py`, then the shareable
  engine check.
- **Keep the game's state where the 2600 kept it**: zero page `$80`-`$FF`, same bytes, same meanings. The
  check compares it with the model frame by frame. Put everything the NES needs besides in `$00`-`$7F` and
  the rest of RAM.
- **Prove each routine before the next.** A routine is done when the check agrees with the model on it.
- **Art is our own**, drawn as text and generated into tiles, like the remaster's packs.

## Readable code

The person who owns this reads it rather than writes it. Assembly especially: a comment on each routine
saying what it does and which part of the spec it follows, names for every address and constant
(`player_x`, not `$AA`), short routines. Python follows the remaster's rules: names of 3 letters or more,
lines of 110 or less, types on every signature; `tools/readability.py` keeps it at zero.
