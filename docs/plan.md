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
2. **The mansion as data**: `tools/extract.py` reads the original's tables from your ROM into
   `build/faithful/` (never committed); the same format for the new mansion, from a file of our own.
3. **The engine**, a routine at a time, each checked against the model before the next: the random numbers,
   a new game, moving, doors and stairs, the match and the button, the monsters, items and the urn, dropping,
   touching, dying and winning, the switches. The check grows with it until it compares the whole state.
4. **The picture**: the floor as background tiles that scroll, the eyes, items and monsters as sprites (all of
   them every frame - no flicker), the status line, the dark and the match's light, lightning. The art comes
   from the remaster's NES look, redrawn as 8×8 tiles in four colours.
5. **The sound**: the NES's sound chip playing the remaster's NES-look effects and music.
6. **The remaster's extras**: the title screen and story, G's hints, the lights-on cheat, the storm, the
   ending.
7. **The new mansion**: designed for the NES, bigger than the original, with a check that its waypoints keep
   monsters out of the walls and every door and stairway works.
8. **Release**: the shareable ROM, built and checked by GitHub; the faithful build stays a recipe.

Then the SNES: the same engine idea on the SNES's 65816 processor, with the remaster's SNES look.

## Things to decide along the way

- **The dark.** The NES can't light a soft circle pixel by pixel. A match could light the tiles around the
  eyes (updated a few tiles a frame), with sprites softening the edge. To try in step 4.
- **The mapper.** Mapper 0 (32K of code, 8K of tiles) may be enough; if the art or the new mansion needs more,
  a common mapper such as MMC1.
- **The bigger mansion**: more floors, more rooms a floor, or both, and what that means for the waypoints and
  the monsters' speed.
