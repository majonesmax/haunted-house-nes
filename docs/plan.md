# The plan

A native NES version of Atari 2600 *Haunted House*: the same game, rule for rule, drawn the way the
[remaster](https://github.com/majonesmax/haunted-house-remastered)'s NES look draws it. Later, an SNES one.

## What it's built from

- **The rules**: the remaster's [docs/spec.md](../../haunted-house/docs/spec.md), and the same rules as code
  in its `game/player.py`, `game/monsters.py` and `game/sounds.py`. Those models predict the real game's
  every byte, every frame, so they are the reference this port is checked against.
- **The look**: the remaster's NES look - its art, light, status line, title and ending - fitted to what the
  NES can really do.
- **Not the original's code.** The engine is written from the spec and the models, never translated from the
  disassembly.

## Two builds, one engine

| | Mansion | Art | Can be shared |
|---|---|---|---|
| **Faithful** | the original's: its walls, doors, stairs and waypoints, read from your own 2600 ROM when you build | our own | no - build it yourself |
| **Shareable** | a new, bigger mansion of our own, built on the same rules | our own | yes |

The faithful build is how the engine is proved: with the original's mansion and the same controls, it must
match `game/player.py` frame for frame. The shareable build then runs the same engine on a mansion of its own.
So the engine reads the mansion as data - floors, rooms, doors, stairs, waypoints - rather than assuming the
original's sizes.

Nothing from the 2600 ROM is ever committed, and neither is a faithful ROM.

## How the engine is checked

The game's state lives where the 2600 kept it: the NES's zero page `$80`-`$FF` holds the same bytes, with the
same meanings, at the same addresses. So the check is simple: play the faithful build in an emulator
(`tools/nes.py`) and run `game/player.py` beside it with the same controls; after every frame, compare
`$80`-`$FF`. Only the 2600's drawing bytes are left out (spec, "Checking a port").

Two places where the port doesn't copy the original:

- **The crash** (spec, "A crash in the original"): the port doesn't crash. On those frames the check skips,
  as it does for the original.
- **Touching** was the 2600's hardware; here it's worked out in software, by the spec's scanline rule, so
  the outcome is the same.

The controller: the D-pad is the joystick, A the button, Start is RESET and Select is SELECT. The left
difficulty switch (lightning on or off) becomes a setting on the title screen.

## Steps

1. **The tools** - done: cc65 builds the ROM, `tools/nes.py` runs it in FCEUmm (libretro) with no window, and
   `tests/test_boot.py` checks it boots.
2. **The mansion as data** - done: `tools/extract.py` reads the original's tables from your ROM into
   `build/faithful/mansion.inc` (never committed): the walls, doors, stairs and waypoints, the rules'
   numbers, and the shapes touching is worked out from. The new mansion will come in the same form, from a
   file of our own.
3. **The engine** - done: the whole game in 6502 (`src/`), written from the models. `tests/verify_engine.py`
   is the remaster's own check with the NES in place of the 2600: over three runs of 90,000 frames the
   NES's state matches the model on every frame it compares, and the NES never takes longer than a frame.
   Nothing is drawn yet; the game runs without a picture or sound.
4. **The picture** - mostly done: the screen split into a status band, the view and a band below (MMC3
   scanline interrupts); each floor's tiles and map made from the remaster's floor pictures
   (`tools/make_art.py`), streamed in as the view scrolls; the dark, the match's light and lightning by
   palettes; the cast as sprites, all of them every frame, with palettes handed out to what's on screen.
   Still to do: the status band's item slots, the urn's shimmer, an art pass (the bat lost its green eyes and
   the hand its flame in three colours), and trimming the sprites' work before the sound needs time - the
   busiest frame has about 5,000 cycles to spare (`tools/profile.py`).
5. **The sound**: the NES's sound chip playing the remaster's NES-look effects and music.
6. **The remaster's extras**: the title screen and story, G's hints, the lights-on cheat, the storm, the
   ending.
7. **The new mansion**: designed for the NES, bigger than the original, with a check that its waypoints keep
   monsters out of the walls and every door and stairway works.
8. **Release**: the shareable ROM, built and checked by GitHub; the faithful build stays a recipe.

Then the SNES: the same engine idea on the SNES's 65816 processor, with the remaster's SNES look.

## The picture: decisions

- **Improve where the real NES allows**, rather than copying the remaster's imitation of it.
- **The board: MMC3** (mapper 4). Its scanline counter splits the screen - a fixed status band, the
  scrolling view, a fixed band below - and its banks give each floor its own tiles.
- **Colours: three per floor, plus black** (chosen 2026-10-20 from mocks in shots/). The view's art is the
  remaster's floor picture cut down to three NES colours, so that the light can work by palettes alone.
- **The light: palettes on 16x16 blocks.** Three palettes hold the same three colours lit, dim and unlit; the
  blocks around the eyes are switched to lit at the core and dim in a ring. Unlit is black in games 2-9,
  dim in game 1 (the walls are always seen); a lightning flash brightens the unlit palette. Only a few
  attribute bytes change a frame.
- **Sprites for everything that moves**, all drawn every frame (no flicker unless more than 8 share a line).

Still open: a bigger cartridge for the new mansion, if it needs one; animating decorations by switching tile
banks (candles, portraits' eyes) - something the remaster can't do the NES way.
