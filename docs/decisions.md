# Decisions

The choices made along the way, what else was possible, and what each one cost. Newest first. When a
choice is changed, the old entry stays and says what replaced it.

## 2026-10-20: The floors' colours: a palette for walls and one for floors (option 2)

**Chose:** each floor gets two lit palettes - one for walls, one for floors - and each 16 x 16 block of the
picture takes whichever fits it. Both share the floor's main colour and the wall's main colour (so a block
across a wall's edge draws both); each has a third colour of its own: the wall's second shade, or the
floor's. The art draws its fine detail - mortar, seams, grout - in black, which every palette has free.

**Why:** played, the first scheme looked flat: one set of three colours for walls, floor and decorations
alike, so a wall's two shades of brick became one. And in the dark (game 1) the whole floor showed dimly,
a different colour on every level - where the original shows only the walls.

**What else:** (1) keep three colours, with black details: most of the texture back, cheaply, but in the
dark the floor still shows where it shares a colour with the walls. (3) as 2, keeping the soft dim ring
round the match by changing the status band's colours partway down the screen: possible, but delicate.
The choice was made from mock-ups of all three, made from the real floors.

**Cost:**
- The light is hard-edged - a block is lit or not - since the dim palette is now the floor's.
- Four colours and black per floor, not six: the two palettes share two, or blocks across a wall's edge
  drew slices of wall in the floor's colours (the first mock-up's grey strips).
- The lights-on cheat can't borrow a palette any more: it writes each block's palette from the floor's
  map of blocks (`tools/floor_colours.py` makes it), redrawing the floor when it's switched on or off.
- A maps bank holds three floors' maps instead of four (each floor's block map and colours go first in both
  banks).

Can still be added: option 3's soft ring, if the hard edge bothers.

Replaces "three colours per floor, soft light" below.

## 2026-10-20: The monsters' speeds (shareable build)

**Chose:** the original's counts: chasing, the ghost steps on 4 frames in 8, the bat 3, the tarantulas 2;
in games 8-9 the ghost and bat 4, the tarantulas 3. Which frames is our own.

**Why:** the first numbers, chosen without the original's, were faster (bat 5, tarantulas 3); played, the
monsters felt too quick. The counts are in the remaster's notes; the ROM's table isn't copied.

## 2026-10-20: The random numbers at power-on

**Chose:** keep whatever the NES's RAM holds at `$EB`/`$EC` at power-on, as the 2600 does (it never
clears them), and seed them with a fixed value if that's all zeros (as an emulator's RAM is).

**Why:** clearing them left a shift register of zeros, which stays zeros: every game was the same game,
the urn's pieces always on the first floor. The checks couldn't see it, since the model is given the NES's
RAM each frame. Now the time the player takes to press Start decides the game.

**Cost:** on an emulator, two players who press Start on the same frame get the same game - as on a 2600
whose RAM came up the same.

## 2026-10-20: The shareable mansion: more floors, each with its own plan

**Chose:** six floors, each with its own walls, doors, locks and stairs, in the original's floor size and
2 x 3 rooms. The engine reads every mansion table floor by floor; the faithful build gives each floor the
original's one plan.

**What else:** more floors sharing one plan (the original's way: the new floors would feel like copies);
bigger floors (positions would need two bytes, so the state would no longer match the 2600's and the
frame-by-frame check would cover only the faithful build); new layouts on four floors.

**Cost:** the remaster's model had to learn to read a mansion floor by floor (its `Floors`), so the new
mansion has the same frame-by-frame proof. Rooms stay a 2 x 3 grid on every floor.

## 2026-10-20: Light and colour: three colours per floor, soft light (option A) - replaced

**Chose:** each floor's picture in three NES colours plus black, and the light done by palettes - the
same three colours lit, dimmed for a soft ring round the match, and unlit.

**What else:** (B) six colours, with hard-edged light.

**Cost:** flat walls and coloured floors in the dark, found when the game was played. Replaced by "a palette
for walls and one for floors" above.

## 2026-10-19: Two builds, one engine

**Chose:** a faithful build, its mansion read from the player's own 2600 ROM when they build it (never
shared), and a shareable build with a mansion of our own - "it's a more capable system so building onto
the mansion seems fair".

**Why:** a ROM that can be shared mustn't hold anything from the original; a faithful build proves the
engine against the original frame for frame.

## 2026-10-19: The engine: written from the spec, checked against the model

**Chose:** the engine is written in 6502 from the remaster's spec and its model of the game (which predicts
the original's every byte), never translated from the original's code; the game's state lives at the
2600's addresses, so the check can compare it with the model after every frame.

**Cost:** the check sees only the game's state - never the picture or the sound. Those need looking at
(and, as above, playing).
