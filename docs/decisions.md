# Decisions

The choices made along the way, what else was possible, and what each one cost. Newest first. When a
choice is changed, the old entry stays and says what replaced it.

First, the hard parts: what the NES makes difficult for this game in particular. Most of the choices below
are a way through one of them.

## The hard parts

**The light, and colour on a grid of 16 x 16 blocks.** *Haunted House* is a game about darkness: a small
glow round the eyes, the rest unseen. The 2600 draws that glow as a shape around the eyes; the remaster
paints it pixel by pixel with a soft edge. The NES can't change pixels one by one like that: its background
is tiles, and colour comes from four palettes of three colours (plus one black shared by all), chosen per 16
x 16 block. So the light can only switch whole blocks between palettes, and every palette spent on light is
one fewer for the art. That's the trade at the heart of the colour choices: soft light (lit, dim, unlit -
three palettes on light) left three colours for each floor; richer art (a palette for walls, one for floors)
leaves the light hard-edged. The fourth palette always goes to the status band at the top.

**The walls don't line up with the blocks.** The floor's walls come in cells of 24 x 32 pixels (the
original's 16 x 16 units, drawn 1.5 wide and 2 tall), and the colour blocks are 16 x 16. Many blocks are
part wall, part floor, and take one palette for both. That's why the two palettes share the floor's and the
walls' main colours: without that, blocks along a wall's edge drew a slice of wall in the floor's colours.
It's also why the light's edge is blocky, and why "the light doesn't reach past the room's limits" is
judged a block row at a time.

**What's seen depends on the game, and on the moment.** The rules for what may be seen are the original's:
the walls always in game 1 and only in lightning in games 2-9; items only near a lit match; monsters only in
your room. A palette has to serve all of those at once: in game 1's dark the walls must show while the
floor stays black, so the dark palette keeps only the colour slot the walls use. A lightning flash
brightens the dark palette for a few frames. The lights-on cheat breaks the light's rules entirely, so it
can't go through the light at all: it draws each block's palette from the floor's map of blocks.

**Too few tiles for rich art.** A set of tiles holds 256, and the font and the status band need 160 of
them, leaving 96 for a whole floor. Every distinct 8 x 8 piece of art is a tile, so texture must repeat: the
art is built from small motifs (brick, boards, damask) that tile cleanly, and decorations are few. Richer
art means more distinct tiles; the busiest floor now uses 84.

**The floor is taller than the screen's memory.** A floor's picture is 512 pixels tall; the NES holds 240
(30 rows of tiles). So the view keeps 30 rows loaded and streams one new row in a frame as it scrolls -
and the light, the cheat's colours and the redraws all have to agree with which floor rows are where. The
one bug of that kind so far: at a floor's bottom the view needs 20 rows, not the usual 21, and the test for
"the view has run past what's loaded" didn't know, so it redrew the floor over and over (the flashing).

**Only so much can be sent to the screen each frame.** The PPU can only be written in the vertical blank,
about 2,270 CPU cycles a frame. Into that go the sprites (513 cycles on their own), the colours, a streamed
row of the floor, the light's changed blocks, the status band's changed tiles, and a row of a hint or a full
screen's words. Sending too much runs past the blank and the picture jumps: the ending's words did that,
until they were sent a row a frame. A hint's row waits for a frame with nothing else much to send.

**And only so much work in a frame.** A frame is 29,780 cycles, and the game must finish in one or the NES
falls behind the original. The 2600 found touching (who touches what) in hardware; here it's worked out in
software, scanline by scanline, and it's the biggest single cost. The busiest moment - dying with a match
lit and all five monsters on the floor - came within a few hundred cycles of the limit, which is how two
slow paths were found: a light cache that never worked, and a redraw that did too much in its last frame.

**Sprites: eight to a line.** Everything that moves is a sprite: 64 at most, eight on a line, four palettes
of three colours. The kinds of thing on screen share those four palettes, handed out each frame; the
urn's shimmer is a palette cycling. More than eight on one line would flicker, which the house's sizes
mostly avoid.

**Splitting the screen.** The status band, the scrolling view and the band below are three regions of one
picture, split by the MMC3 cartridge's scanline counter. The scroll has to be changed partway down the
screen, inside a horizontal blank of a few dozen cycles, or a line tears.

**The checks can't see the picture.** The frame-by-frame check compares the game's state with the
remaster's model of the original - every byte, every frame - so the rules are proved. But it never looks at
the screen or listens to the sound. The flashing, the ending's first frame in the wrong colours, and every
game being the same game (the random numbers' seed) were all found by playing it.

## 2026-10-20: The browser page keeps EmulatorJS's 64 ms sound buffer

**Chose:** leave EmulatorJS's audio buffer at its 64 ms, so the sound stays a little late. The page's patch that
shortened it to 32 ms is gone.

**Why:** the emulator paces the game on that buffer, so it must be longer than the sound device's own delay.
On a MacBook Air (speakers: 40 ms) the 32 ms buffer ran the game at 49 frames a second instead of 60, in Chrome
and Safari alike, and 16 ms ran it at 25; 64 ms and 128 ms ran it at 60. On a MacBook Pro the 32 ms had
seemed fine. Measured by counting the frames the core uploads to the screen each second, with Chrome driven
over its debugging protocol.

**What else:** read the device's output latency after the start click and size the buffer to it. It's a
second reach into EmulatorJS's internals for a delay most people won't notice; not worth it.

## 2026-10-20: A cellar and four floors, not six

**Chose:** the Cellar, the Foyer (with the front door), the Gallery, the Bedrooms and the Attic. The
Library and the Nursery went.

**Why:** six storeys felt like an apartment building, not a house; a cellar below the ground floor feels
like a haunted house.

**Cost:** the original starts every game on its bottom floor, where its front door is. With a cellar below,
the front door's floor has to be the mansion's to say (`front door on floor 2` in `mansion/floors.txt`): the
engine puts a new game there, and so does the remaster's model (its `Floors.ground_floor`; for the real
ROM it's 0, so nothing there changed, and its proofs against the 2600 are still exact). The status band
counts floors from the front door's: the cellar shows as B. Every floor's stairs and locks were planned
again, and pass the checker. The fixed code bank is nearly full now (about 230 bytes): new code should
move the mansion's tables out to a bank first.

Replaces six of "more floors, each with its own plan" below - the "each with its own plan" stays.

## 2026-10-20: The name: Haunted House: By Matchlight

**Chose:** *Haunted House: By Matchlight* - the logo stays HAUNTED HOUSE, with BY MATCHLIGHT under it.

**Why:** the shareable ROM is its own game on the original's rules, and should say so; the match - a
small circle of light in a dark house - is how it plays. It also fits an SNES version later.

**What else:** plain *Haunted House* (Atari's game's name, used for an unofficial ROM); *Six Floors*, *After
Dark*, *The Urn*; a name of its own (*Matchlight*), which would avoid leading with Atari's title at all.

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

(Six floors became a cellar and four: see above.)

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
