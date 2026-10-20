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
4. **The picture** - done: the screen split into a status band, the view and a band below (MMC3 scanline
   interrupts); each floor's tiles and map made from the remaster's floor pictures (`tools/make_art.py`),
   streamed in as the view scrolls; the dark, the match's light and lightning by palettes; the cast as
   sprites, all of them every frame, with sprite palettes handed out to what's on screen and the urn
   shimmering by palette; the status band as the remaster's - the burning match, the held item, the urn so
   far, lives - sending only what changed. The busiest frame (dropping by a wall with a match lit) keeps
   about 5,800 of its 29,780 cycles spare (`tools/profile.py`). Possible later: a rounder light.
5. **The sound** - done: `tools/make_music.py` arranges the remaster's classic soundtrack by its own synth's
   rules as note streams for the NES's four voices (a chord on one voice played as a fast arpeggio, the
   NES way), and its 20 remastered effects as frame-by-frame lists; `src/audio.s` plays them - the song
   follows the moment (a floor's tune carrying on after a monster's visit), the effects follow what just
   happened (the remaster's events). `tools/record_sound.py` saves what's heard as a WAV. Possible later:
   the 2600's own sound as a choice, and the house's ambience (rain, the attic's quiet).
6. **The remaster's extras** - done: the story at power-on; the title with its mansion, moon, lightning and
   the eyes in the tower window, the game and the help (B); game over; the ending at dawn with the eyes
   walking off and the verdict (`src/screens.s`, pictures from `tools/screens.py`). In play, B gives the
   remaster's hint and two notes come by themselves - the urn whole, and one thing held at a time - in the
   band under the view (`src/hints.s`; `tests/test_hints.py` checks their words against the remaster's
   game/hints.py). B with Select is the lights-on cheat (`src/cheat.s`): while B is held, Select is never the
   game's. Lightning is in the picture and the sound. Possible later: "YOU ESCAPED!" at the door.
7. **The new mansion** - done: a cellar and four floors, each with its own plan, walls, doors, locks and stairs
   (games 1-8, and game 9's), drawn as text in `mansion/floors.txt` (chosen 2026-10-20 over more floors on
   one plan, or bigger floors). The pieces:
   - the engine reads every mansion table floor by floor (`src/mansion.s`); the faithful build gives each
     floor the original's one plan, and its check is still exact;
   - `tools/mansion.py` works the tables out from the text, as the original's are from its plan
     (`tests/test_mansion.py` gets the original's bytes back from it exactly);
   - `tools/check_mansion.py` checks a mansion plays: the plan's shape, doorways, monsters' walks clear of
     walls, stairs that meet, the start, and every room reachable without the key in every game - the
     original's own rule (`tests/test_check_mansion.py` breaks it five ways and expects each caught);
     `tools/draw_mansion.py` draws the plans;
   - `tools/shareable.py` makes the shareable build's mansion with nothing from the ROM: our floors, touching
     shapes from our own pictures, and our own numbers where the spec leaves them to the ROM;
   - the remaster's model can run a mansion of its own (its `game/rom.py` Floors), so
     `tests/verify_engine.py --shareable` checks the new mansion frame by frame, as the original is;
   - the house, from the bottom: the Cellar, the Foyer (the front door's floor, where a game starts), the
     Gallery, the Bedrooms and the Attic; the status band shows the Cellar as floor B;
   - the floors' pictures are text art (`mansion/art.py`): the Foyer and the Attic as the classic pack draws
     them, the Cellar, the Gallery and the Bedrooms our own; `tools/mansion_pack.py` makes them a pack for
     the remaster's look to draw;
   - the Cellar, the Gallery and the Bedrooms have songs of their own (`mansion/music.json`), in a second
     music bank (bank 4 at $A000, switched in while one of them plays; both banks start with the same
     tables).
8. **Release** - ready: `.github/workflows/build.yml` builds the shareable ROM on GitHub, with nothing but this
   repository and the remaster, and checks it (the code, the mansion, boot, the frame-by-frame check, the
   hints); a `v*` tag makes the release, with the notes in `docs/release-notes/`. The faithful build stays a
   recipe. Licences: MIT for the code, CC BY 4.0 for the art and music, as the remaster's.

Then the SNES: the same engine idea on the SNES's 65816 processor, with the remaster's SNES look.

## The picture: decisions

- **Improve where the real NES allows**, rather than copying the remaster's imitation of it.
- **The board: MMC3** (mapper 4). Its scanline counter splits the screen - a fixed status band, the
  scrolling view, a fixed band below - and its banks give each floor its own tiles.
- **Colours: a palette for walls and one for floors** (docs/decisions.md has why, and what it replaced):
  four NES colours and black per floor, each 16x16 block in whichever palette fits it
  (`tools/floor_colours.py`); the art draws its fine detail in black.
- **The light: palettes on 16x16 blocks, hard-edged.** The blocks around the eyes take their own lit
  palette; the rest the dark one: black in games 2-9, only the walls (dim) in game 1, as the original; a
  lightning flash shows the walls. Only a few attribute bytes change a frame. Choices like these are logged
  in docs/decisions.md.
- **Sprites for everything that moves**, all drawn every frame (no flicker unless more than 8 share a line).

The cartridge: 64K of program (the floors' maps in banks 0 and 3) and 64K of tiles, for both builds. The
fixed bank is nearly full: new code or tables go in a bank of their own.

Still open: animating decorations by switching tile
banks (candles, portraits' eyes) - something the remaster can't do the NES way.
