"""The picture's tiles, made from the remaster's NES look: each floor drawn by the remaster's own scenery code
with its classic pack, cut down to three NES colours plus black (docs/plan.md, "The picture"), split into
8x8 tiles; and the remaster's NES font. The faithful build's floors carry the original's wall plan, so its
art is never committed; the shareable build's floors are our own (mansion/floors.txt), drawn with the pack
tools/mansion_pack.py makes.

Makes, in build/faithful/art or build/shareable/art:
  tiles.chr     the cartridge's tile memory (CHR): per floor a 4K set (font, then the floor's tiles), then
                the sprites' 4K, the title's and the ending's
  art.inc       the maps' banks: each starts with the floors' colours and names and the light's shape, then
                the maps (the tile on every 8x8 of a floor's 240 x 512 picture) of its three floors
  floors.inc    by floor: where its map, colours and name are, its maps bank, its song
  font.inc      the font's character map, so text in the code is written as text
  sprites.inc   the cast: each picture as 8x16 pieces, and each kind's three colours
  screens.inc   the full screens

Usage: python tools/make_art.py [--shareable]
"""

import json
import os
import sys
from typing import NamedTuple

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REMASTER = os.path.join(os.path.dirname(ROOT), "haunted-house")
sys.path.insert(0, REMASTER)
import looks  # noqa: E402
from game import rom as R  # noqa: E402
from game import guide  # noqa: E402
from looks.nes import look as NL  # noqa: E402
from shared import hud  # noqa: E402
import content  # noqa: E402
import floor_colours as FC  # noqa: E402
import mansion as M  # noqa: E402
import mansion_pack  # noqa: E402
import rom_image as I  # noqa: E402
import screens  # noqa: E402
from shared import palettes as PAL  # noqa: E402

FAITHFUL_FLOORS = 4
TILE = 8
TILES_PER_SET = 256
FONT_TILES = 160           # tiles 0-159 of each set: the font (white, then grey) and the status band's pieces
FONT_ORDER = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!.,-:'?<>/"
SET_BYTES = TILES_PER_SET * 16
CHR_BYTES = 64 * 1024      # up to eight floor sets, the sprites' set, the title's and the ending's
MAPS_SEGMENTS = ("MAPS", "MAPS_2")   # the floors' maps: three to a bank (src/mmc3.cfg)...
MAPS_BANKS = (0, 3)                  # ...in program banks 0 and 3
FLOORS_PER_BANK = 3        # (with every floor's colours, blocks, names and light first: see shared_block)
FAITHFUL_SONGS = ["floor1", "floor2", "floor3", None]   # the classic floors' songs; the attic is quiet
MANSION_MUSIC = os.path.join(ROOT, "mansion", "music.json")   # the shareable build's: its floor_songs
BLACK = 0x0F
COLOURS = 3
KMEANS_ROUNDS = 25
NES = np.array(PAL.NES, int)
LIGHT_HALF_WIDTH, LIGHT_HALF_HEIGHT = 24, 28   # px: the match's reach (the remaster's 16 units by 14 lines)
LIGHT_REACH = 1.1                   # a block is lit within this much of the match's reach
LIGHT_STEP = 4                      # the light table's steps, in px
LIGHT_STEPS = 16

Indices = np.ndarray       # a picture as colour numbers 0-3
SPRITE_W, SPRITE_H = 8, 16  # the NES's sprites, in 8x16 mode
SPRITE_PAIRS = 128         # tile pairs in the sprites' 4K
# Each kind of thing and its pictures (the remaster's cast names; frames after the colon). A kind shares
# three colours. Right-facing pictures the cast doesn't draw are the left ones mirrored, by the code.
CAST_KINDS = {
    "eyes": ["eyes_centre", "eyes_left", "eyes_right", "eyes_up", "eyes_down", "eyes_blink",
             "patch/16x8", "patch/18x12"],   # black: the lit window's room behind the eyes; the window, dark
    "light": ["hood", "match_hand_right:0", "match_hand_right:1"],
    "key": ["key"],
    "scepter": ["scepter"],
    "urn": [f"urn{shape}:0" for shape in range(2, 9)],
    "stairs": ["stairs_up", "stairs_down"],
    "ghost": [f"ghost_{facing}:{frame}" for facing in ("down", "left", "up") for frame in (0, 1)],
    "bat": [f"bat_{facing}:{frame}" for facing in ("down", "left", "up") for frame in range(4)],
    "tarantula2": [f"tarantula2_{facing}:{frame}" for facing in ("down", "left", "right", "up")
                   for frame in (0, 1)],
    "tarantula3": [f"tarantula3_{facing}:{frame}" for facing in ("down", "left", "right", "up")
                   for frame in (0, 1)],
    "tarantula4": [f"tarantula4_{facing}:{frame}" for facing in ("down", "left", "right", "up")
                   for frame in (0, 1)],
    "moon": ["world/title_moon@2"],        # the title's moon (the world's picture, at twice size)...
    "sun": ["sunrise/title_moon@2"],       # ...and warmed, the ending's rising sun
}


def nes_code(rgb: np.ndarray) -> int:
    """The NES colour nearest an RGB colour (not one of the duplicate blacks)."""
    distances = ((NES - rgb) ** 2).sum(axis=1).astype(float)
    distances[[0x0D, 0x0E, 0x1D, 0x1E, 0x1F, 0x2E, 0x2F, 0x3E, 0x3F]] = np.inf
    return int(distances.argmin())


def tile_bytes(tile: Indices) -> bytes:
    """An 8x8 tile of colour numbers as the NES stores it: 8 bytes of low bits, then 8 of high bits."""
    def plane(bit: int) -> list[int]:
        return [int(sum(((tile[row, column] >> bit & 1) << (7 - column)) for column in range(TILE)))
                for row in range(TILE)]
    return bytes(plane(0) + plane(1))


STATUS_COLOURS = [BLACK, 0x30, 0x10, 0x27]   # the status band's palette: white, grey, gold (view.s)
WHITE_INK, GREY_INK, GOLD_INK = 1, 2, 3
SLOT = 16                  # an item slot: 2 x 2 tiles with a grey frame
BAR_TILES = 3              # the burning match: up to 20 px of ember and 3 of flame
FLAME = 3
EMBER_ROWS, FLAME_ROWS = (3, 4), (1, 2, 3, 4, 5, 6)
SLOT_ITEMS = ["key", "scepter"] + [f"urn{shape}:0" for shape in range(2, 9)]


def font_glyphs(ink: int) -> list[bytes]:
    """The remaster's 5x7 font, one glyph a tile in one colour, in FONT_ORDER."""
    tiles = []
    for letter in FONT_ORDER:
        glyph = hud.GLYPHS[letter]
        tile = np.zeros((TILE, TILE), np.uint8)
        for row in range(7):
            for column in range(5):
                if glyph[row * 5 + column] == "#":
                    tile[row, column + 1] = ink
        tiles.append(tile_bytes(tile))
    return tiles


def picture_tiles(picture: Indices) -> list[bytes]:
    """A picture's 8x8 tiles, row by row."""
    return [tile_bytes(picture[top:top + TILE, left:left + TILE])
            for top in range(0, picture.shape[0], TILE) for left in range(0, picture.shape[1], TILE)]


def status_ink(picture: np.ndarray) -> Indices:
    """A cast picture in the status band's colours: transparent and black are 0, the rest the nearest."""
    choices = np.array([NES[code] for code in STATUS_COLOURS[1:]])
    pixels = picture[..., :3].reshape(-1, 3).astype(int)
    nearest = ((pixels[:, None] - choices[None]) ** 2).sum(axis=2).argmin(axis=1) + 1
    solid = (picture[..., 3].reshape(-1) > 0) & (pixels.sum(axis=1) > 0)
    return np.where(solid, nearest, 0).reshape(picture.shape[:2]).astype(np.uint8)


def slot(picture: np.ndarray | None) -> Indices:
    """A 16 x 16 slot: a grey frame, and the picture (if any) centred in it."""
    tile = np.zeros((SLOT, SLOT), np.uint8)
    if picture is not None:
        inked = status_ink(picture)[:SLOT, :SLOT]
        top, left = (SLOT - inked.shape[0]) // 2, (SLOT - inked.shape[1]) // 2
        area = tile[top:top + inked.shape[0], left:left + inked.shape[1]]
        np.copyto(area, inked, where=inked > 0)
    tile[0, :] = tile[-1, :] = tile[:, 0] = tile[:, -1] = GREY_INK
    return tile


def bar_tile(ember: int, flame_from: int, flame_to: int) -> bytes:
    """One tile of the burning match: ember in its first `ember` columns, flame in [flame_from, flame_to)."""
    tile = np.zeros((TILE, TILE), np.uint8)
    for row in EMBER_ROWS:
        tile[row, :ember] = GOLD_INK
    for row in FLAME_ROWS:
        tile[row, flame_from:flame_to] = WHITE_INK
    return tile_bytes(tile)


def status_tiles(look: "looks.FloorLook") -> tuple[list[bytes], list[str]]:
    """The font in white and in grey, then the status band's pieces; and their numbers for the code."""
    tiles = font_glyphs(WHITE_INK) + font_glyphs(GREY_INK)
    names = [f"GREY_TEXT = {len(FONT_ORDER)}"]
    names.append(f"SLOT_EMPTY = {len(tiles)}")
    tiles += picture_tiles(slot(None))
    names.append(f"SLOT_ITEMS = {len(tiles)}   ; 4 tiles each: the key, the scepter, urn shapes 2-8")
    for entry in SLOT_ITEMS:
        tiles += picture_tiles(slot(cast_picture(look, entry)))
    names.append(f"BAR_EMBER = {len(tiles)}")
    tiles.append(bar_tile(TILE, 0, 0))
    names.append(f"BAR_END = {len(tiles)}   ; + where in the tile the ember ends")
    tiles += [bar_tile(end, end, min(end + FLAME, TILE)) for end in range(TILE)]
    names.append(f"BAR_FLAME = {len(tiles) - 1}   ; + how many columns of flame spill into the next tile")
    tiles += [bar_tile(0, 0, spill) for spill in (1, 2)]
    names.append(f"LIVES_EYES = {len(tiles)}")
    eyes = np.zeros((TILE, SLOT), np.uint8)
    inked = status_ink(cast_picture(look, "eyes_centre"))
    eyes[1:1 + inked.shape[0], 1:1 + inked.shape[1]] = inked
    tiles += picture_tiles(eyes)
    if len(tiles) > FONT_TILES:
        raise ValueError(f"the status band needs {len(tiles)} tiles; there's room for {FONT_TILES}")
    return tiles + [bytes(16)] * (FONT_TILES - len(tiles)), names


def floor_tiles(indices: Indices) -> tuple[list[bytes], list[int]]:
    """The floor's distinct tiles, and its map: the tile number (after the font's) of each 8x8, row by row."""
    distinct: dict[bytes, int] = {}
    tiles: list[bytes] = []
    tile_map: list[int] = []
    rows, columns = indices.shape[0] // TILE, indices.shape[1] // TILE
    for row in range(rows):
        for column in range(columns):
            data = tile_bytes(indices[row * TILE:(row + 1) * TILE, column * TILE:(column + 1) * TILE])
            if data not in distinct:
                distinct[data] = FONT_TILES + len(tiles)
                tiles.append(data)
            tile_map.append(distinct[data])
    if FONT_TILES + len(tiles) > TILES_PER_SET:
        raise ValueError(f"a floor needs {len(tiles)} tiles; there's room for {TILES_PER_SET - FONT_TILES}")
    return tiles, tile_map


def light_table() -> list[int]:
    """The light at a block whose centre is (across, down) px from the eyes, in LIGHT_STEP steps of each:
    2 lit, 0 unlit (hard-edged: there's no palette for dim - docs/decisions.md). Row by row of `down`."""
    levels = []
    for down in range(LIGHT_STEPS):
        for across in range(LIGHT_STEPS):
            centre_x, centre_y = (across + 0.5) * LIGHT_STEP, (down + 0.5) * LIGHT_STEP
            reach = np.hypot(centre_x / LIGHT_HALF_WIDTH, centre_y / LIGHT_HALF_HEIGHT)
            levels.append(2 if reach <= LIGHT_REACH else 0)
    return levels


SUN_TINT = np.array([1.25, 0.95, 0.45])   # the remaster's warming of the moon into the sun


def cast_picture(look: "looks.FloorLook", entry: str) -> np.ndarray:
    """A picture (RGBA) through the NES look's colours: a cast picture, "name" or "name:frame"; a world
    picture "world/name@scale", or warmed into the sun "sunrise/name@scale"; or a black "patch/WxH"."""
    kind, _, rest = entry.rpartition("/")
    if kind == "patch":
        width, height = (int(number) for number in rest.split("x"))
        patch = np.zeros((height, width, 4), np.uint8)
        patch[..., 3] = 255
        return patch
    if kind in ("world", "sunrise"):
        name, _, scale = rest.partition("@")
        picture = look.pack.world.must(name)[0].copy()
        if kind == "sunrise":
            shade = picture[..., :3].astype(float).mean(axis=2, keepdims=True) / 255
            picture[..., :3] = np.clip(shade * 255 * SUN_TINT, 0, 255).astype(np.uint8)
        size = int(scale or 1)
        return look.adapt(picture).repeat(size, axis=0).repeat(size, axis=1)
    name, _, frame = rest.partition(":")
    frames = look.pack.cast.must(name)
    return look.adapt(frames[int(frame) if frame else 0])


def picture_label(entry: str) -> str:
    return "".join(letter if letter.isalnum() else "_" for letter in entry)


def sprite_indices(picture: np.ndarray, codes: list[int]) -> Indices:
    """Transparent 0; every other pixel the nearest of the kind's three colours, 1-3."""
    choices = np.array([NES[code] for code in codes])
    pixels = picture[..., :3].reshape(-1, 3).astype(int)
    nearest = ((pixels[:, None] - choices[None]) ** 2).sum(axis=2).argmin(axis=1) + 1
    solid = picture[..., 3].reshape(-1) > 0
    return np.where(solid, nearest, 0).reshape(picture.shape[:2]).astype(np.uint8)


KIND_COLOURS_CHOSEN = {       # kinds whose three colours are chosen, where the automatic choice lost too much
    "bat": [BLACK, 0x14, 0x2A],          # purple, with its green eyes
    "light": [0x07, 0x27, 0x37],         # the hood's brown, the flame's orange, the hand
    "sun": [0x28, 0x38, 0x30],           # pale yellows: a rising sun, brighter than the orange sky
}


def kind_colours(pictures: list[np.ndarray]) -> list[int]:
    """Three NES colours for a kind: its pictures' colours (black counts here: it's their outline)."""
    solid = np.vstack([picture[..., :3][picture[..., 3] > 0] for picture in pictures])
    colours, counts = np.unique(solid, axis=0, return_counts=True)
    if len(colours) <= COLOURS:
        codes = [nes_code(colour) if colour.sum() else BLACK for colour in colours]
        return (codes + [BLACK] * COLOURS)[:COLOURS]
    centres = colours[np.argsort(-counts)[:COLOURS]].astype(float)
    for _ in range(KMEANS_ROUNDS):
        nearest = ((colours[:, None] - centres[None]) ** 2).sum(axis=2).argmin(axis=1)
        for index in range(COLOURS):
            mine = nearest == index
            if mine.any():
                centres[index] = (colours[mine] * counts[mine, None]).sum(axis=0) / counts[mine].sum()
    return [nes_code(centre) if centre.sum() > 30 else BLACK for centre in centres]


class SpriteTiles:
    """The sprites' tile pairs (8x16), each made once - a mirrored copy counts as the same."""

    def __init__(self) -> None:
        self.pairs: list[bytes] = []
        self.found: dict[bytes, tuple[int, bool]] = {}

    def pair(self, piece: Indices) -> tuple[int, bool]:
        """(pair number, mirrored) for an 8x16 piece."""
        data = tile_bytes(piece[:TILE]) + tile_bytes(piece[TILE:])
        if data not in self.found:
            mirrored = tile_bytes(piece[:TILE, ::-1]) + tile_bytes(piece[TILE:, ::-1])
            if mirrored in self.found:
                number, _flipped = self.found[mirrored]
                return number, True
            self.found[data] = (len(self.pairs), False)
            self.pairs.append(data)
        return self.found[data]


def sprite_pieces(indices: Indices, tiles: SpriteTiles) -> list[tuple[int, int, int, int]]:
    """(top, left, tile, attributes) of each 8x16 piece with anything in it, the picture padded to whole
    pieces. The tile number is for 8x16 sprites from the second pattern table: pair * 2 + 1."""
    height = -(-indices.shape[0] // SPRITE_H) * SPRITE_H
    width = -(-indices.shape[1] // SPRITE_W) * SPRITE_W
    padded = np.zeros((height, width), np.uint8)
    padded[:indices.shape[0], :indices.shape[1]] = indices
    pieces = []
    for top in range(0, height, SPRITE_H):
        for left in range(0, width, SPRITE_W):
            piece = padded[top:top + SPRITE_H, left:left + SPRITE_W]
            if piece.any():
                number, mirrored = tiles.pair(piece)
                pieces.append((top, left, number * 2 + 1, 0x40 if mirrored else 0))
    return pieces


def sprite_include(look: "looks.FloorLook", tiles: SpriteTiles) -> list[str]:
    """Each kind's colours, and each picture: width, height, piece count, then (top, left, tile, attributes)
    for each piece; and the monsters' pictures by facing and step."""
    lines = ["; Made by tools/make_art.py from the remaster's classic pack: the cast as NES sprites.", ""]
    colour_lines = ["kind_colours:   ; three colours a kind, in KIND_ order"]
    for number, (kind, entries) in enumerate(CAST_KINDS.items()):
        pictures = [cast_picture(look, entry) for entry in entries]
        codes = KIND_COLOURS_CHOSEN.get(kind) or kind_colours(pictures)
        lines.append(f"KIND_{kind.upper()} = {number}")
        colour_lines += byte_lines(codes)
        for entry, picture in zip(entries, pictures):
            pieces = sprite_pieces(sprite_indices(picture, codes), tiles)
            label = picture_label(entry)
            lines.append(f"picture_{label}:   ; {picture.shape[1]} x {picture.shape[0]}")
            lines += byte_lines([picture.shape[1], picture.shape[0], len(pieces)])
            lines += byte_lines([value for piece in pieces for value in piece], 16)
    if len(tiles.pairs) > SPRITE_PAIRS:
        raise ValueError(f"the cast needs {len(tiles.pairs)} sprite tile pairs; there's room for 128")
    return lines + [""] + colour_lines + [""] + monster_tables() + [""] + urn_shimmer(look)


URN_SHIMMER = [[BLACK, 0x2C, 0x1C], [BLACK, 0x3C, 0x2C], [BLACK, 0x30, 0x3C], [BLACK, 0x3C, 0x2C]]


def urn_shimmer(look: "looks.FloorLook") -> list[str]:
    """The urn's colours as they cycle - it shimmers, as on the 2600 (where its colour runs off the frame
    clock): the first is the urn's own (its tiles were cut to it), a step every 8 video frames."""
    first = kind_colours([cast_picture(look, f"urn{shape}:0") for shape in range(2, 9)])
    lines = ["urn_shimmer:   ; three colours a step, a step every 8 video frames"]
    for step in [first] + URN_SHIMMER[1:]:
        lines += byte_lines(step)
    return lines + [f"URN_SHIMMER_STEPS = {len(URN_SHIMMER)}"]


MONSTER_CAST = ("ghost", "bat", "tarantula2", "tarantula3", "tarantula4")   # monsters 0-4
FACINGS = ("down", "left", "right", "up")
STEPS = 4


def monster_tables() -> list[str]:
    """monster_pictures: per monster, per facing, 4 steps of its walk (a picture's address); and
    monster_mirrored: per monster and facing, 1 if those pictures are the opposite facing's, mirrored."""
    pointers, mirrored = [], []
    for name in MONSTER_CAST:
        frames = {entry.split(":")[0].split("_")[1]: [] for entry in CAST_KINDS[name]}
        for entry in CAST_KINDS[name]:
            facing = entry.split(":")[0].split("_")[1]
            frames[facing].append(entry.replace(":", "_"))
        for facing in FACINGS:
            drawn = facing if facing in frames else "left"   # the cast has no right: the left, mirrored
            mirrored.append(0 if drawn == facing else 1)
            steps = frames[drawn]
            pointers += [f"picture_{steps[step % len(steps)]}" for step in range(STEPS)]
    lines = ["monster_pictures:   ; per monster, per facing (down, left, right, up), 4 steps"]
    for start in range(0, len(pointers), STEPS):
        lines.append("    .word " + ", ".join(pointers[start:start + STEPS]))
    lines += ["monster_mirrored:"] + byte_lines(mirrored, len(FACINGS))
    return lines


def font_map() -> str:
    lines = ["; Made by tools/make_art.py: the font's tiles, so the code's text is the tiles' numbers"]
    lines += [f".charmap ${ord(letter):02X}, {number}" for number, letter in enumerate(FONT_ORDER)]
    lines += [f"DIGIT_ZERO = {FONT_ORDER.index('0')}"]
    return "\n".join(lines) + "\n"


def byte_lines(data: list[int], per_line: int = 30) -> list[str]:
    return ["    .byte " + ", ".join(f"${value:02X}" for value in data[start:start + per_line])
            for start in range(0, len(data), per_line)]



def screen_sets(look: "looks.FloorLook") -> tuple[bytes, list[str]]:
    """The title's and the ending's tile sets, and their nametables, attributes and colours."""
    mansion = look.adapt(look.pack.world.must("title_mansion")[0])
    mansion_colours = screens.mansion_palettes(mansion)
    title = screens.Screen()
    title.place_mansion(mansion, mansion_colours)
    title.place_stars(NL.STARS)
    title.grey_rows(0, 1)                  # the hints
    title.grey_rows(6, 13)                 # the game's rules, or the matches used
    ending = screens.Screen()
    ending.place_mansion(mansion, mansion_colours)
    ending.place_dawn()
    chr_data = b""
    lines = ["; Made by tools/make_art.py: the full screens. Never commit this file."]
    for name, screen, backing, colours in (("title", title, False, [screens.TITLE_WORDS, screens.TITLE_GREY]),
                                           ("ending", ending, True, [screens.ENDING_WORDS, screens.DAWN])):
        tiles, names = screens.word_tiles(FONT_ORDER, backing, tile_bytes)
        distinct: dict[bytes, int] = {}
        for number, data in enumerate(tiles):
            distinct.setdefault(data, number)
        extra: list[bytes] = []
        table = screen.tiles(len(tiles), distinct, extra, tile_bytes)
        if len(tiles) + len(extra) > TILES_PER_SET:
            raise ValueError(f"the {name} screen needs {len(tiles) + len(extra)} tiles")
        chr_data += b"".join(tiles + extra).ljust(SET_BYTES, b"\0")
        lines += [f"{name}_nametable:   ; {len(tiles) + len(extra)} tiles"] + byte_lines(table, 32)
        lines += [f"{name}_attributes:"] + byte_lines(screen.attributes())
        words, grey_or_dawn = colours
        backdrop = screens.TITLE_SKY if name == "title" else screens.ENDING_BACKDROP
        palette = [backdrop, *words, backdrop, *mansion_colours[0], backdrop, *mansion_colours[1],
                   backdrop, *grey_or_dawn]
        lines += [f"{name}_colours:"] + byte_lines(palette)
    lines += names + [f"TITLE_FLASH = ${screens.TITLE_FLASH:02X}"]
    return chr_data, lines + text_lines()


def text(line: str) -> str:
    """A line as the assembler writes it: the font's tiles (font.inc's character map), $FF at the end."""
    return f'.byte "{line}", $FF' if line else ".byte $FF"


KEYS_TO_BUTTONS = [("SPACE", "A")]   # the help's keyboard words, as the NES's controller says them


def on_the_controller(line: str) -> str:
    for key, button in KEYS_TO_BUTTONS:
        line = line.replace(key, button)
    return line


def text_lines() -> list[str]:
    """The words the screens show, from the remaster's game/guide.py: the story, the help (each line's
    first byte: 1 a heading, 0 not), each game's rules (an empty line ends a game's), the verdicts by
    matches used."""
    lines = ["story_lines:"] + [f"    {text(line)}" for line in guide.STORY] + ["    .byte $FE"]
    lines += ["help_lines:"]
    for line, kind in guide.HOW_TO_PLAY:
        lines.append(f"    .byte {1 if kind == 'title' else 0}")
        lines.append(f"    {text(on_the_controller(line))}")
    lines += ["    .byte $FE", "game_rules:   ; where each game's rules start"]
    lines += ["    .word " + ", ".join(f"game{game}_rules" for game in range(1, 10))]
    for game in range(1, 10):
        lines += [f"game{game}_rules:"] + [f"    {text(rule)}" for rule in guide.game_rules(game)]
        lines += ["    .byte $FE"]
    lines += ["verdicts:   ; the most matches for each line ($FF: any), then the line"]
    for most, line in guide.VERDICTS:
        lines += [f"    .byte {most if most is not None else 255}", f"    {text(line)}"]
    return lines


class FloorArt(NamedTuple):
    """One floor's pictures, made: its tile map, its palettes, which blocks take the floor's, its name."""
    tile_map: list[int]
    tiles: list[bytes]
    colours: list[int]
    kinds: list[int]
    name: str


def floor_looks(shareable: bool) -> tuple[list["looks.FloorLook"], list[str]]:
    """The look that draws each floor, and the floors' names. The faithful build's floors share one plan, so
    one look draws them all; the shareable build's each have a look of their own, reading a stand-in ROM
    (tools/rom_image.py) with that floor's plan, and the pack tools/mansion_pack.py makes."""
    if not shareable:
        look = looks.make("nes", R.load())
        names = look.pack.info.get("floors", [f"FLOOR {number + 1}" for number in range(FAITHFUL_FLOORS)])
        return [look] * FAITHFUL_FLOORS, names
    mansion_pack.main()
    with open(mansion_pack.MANSION_TEXT) as mansion_file:
        mansion_text = mansion_file.read()
    floors = M.parse(mansion_text)
    ground_floor = M.front_door_floor(mansion_text)
    per_floor = [M.floor_tables(floor) for floor in floors]
    tables = {label: b"".join(made[label] for made in per_floor) for label in per_floor[0]}
    pack = content.Pack(mansion_pack.OUTPUT, bytes(I.IMAGE_SIZE))
    images = [I.floor_image(tables, number, [], bytes(I.RANDOM_BYTES // 8)) for number in range(len(floors))]
    # Each stand-in carries one floor's plan, but as a Floors it still says which floor of the mansion has the
    # front door, so the scenery draws the door there (and not on the cellar, the mansion's floor 0).
    stand_ins = [R.Floors([image], {}, ground_floor) for image in images]
    return [looks.LOOKS["nes"](pack, stand_in) for stand_in in stand_ins], [floor.name for floor in floors]


def floor_art(floor_set: list["looks.FloorLook"], names: list[str]) -> list[FloorArt]:
    made = []
    for floor, (look, name) in enumerate(zip(floor_set, names)):
        scene = look.scene(floor)
        colours = FC.choose(scene.full, scene.walls)
        indices, kinds = FC.cut(scene.full, colours)
        tiles, tile_map = floor_tiles(indices)
        made.append(FloorArt(tile_map, tiles, FC.palette_bytes(colours), FC.kind_bytes(kinds), name.upper()))
    return made


def shared_block(floors: list[FloorArt], labelled: bool) -> list[str]:
    """What every maps bank starts with, at the same places in each, so it reads the same whichever floor's
    bank is in: the floors' colours and names, and the light's shape. Labelled in the first bank only."""
    lines = []
    for number, floor in enumerate(floors):
        label = f"floor{number + 1}_colours:" if labelled else ";"
        lines += [f"{label}   ; the walls' palette, the floor's, the dark, lightning"]
        lines += byte_lines(floor.colours, 12)
    for number, floor in enumerate(floors):
        label = f"floor{number + 1}_kinds:" if labelled else ";"
        lines += [f"{label}   ; per block row, 16 bits: the blocks in the floor's palette"]
        lines += byte_lines(floor.kinds, 16)
    for number, floor in enumerate(floors):
        label = f"floor{number + 1}_name:" if labelled else ""
        lines += [f'{label} .byte "{floor.name}", $FF']   # (0 is a space)
    label = "light_levels:" if labelled else ";"
    lines += [f"{label}   ; by (down, across) from the eyes, 4 px steps: 2 lit, 0 unlit"]
    return lines + byte_lines(light_table(), LIGHT_STEPS)


def maps_banks(floors: list[FloorArt]) -> list[str]:
    """The maps' banks (MAPS_SEGMENTS): each starts with the shared block, then the maps of its floors."""
    lines = []
    for bank, segment in enumerate(MAPS_SEGMENTS):
        first = bank * FLOORS_PER_BANK
        if first >= len(floors):
            break
        lines += [f'.segment "{segment}"'] + shared_block(floors, bank == 0)
        for number in range(first, min(first + FLOORS_PER_BANK, len(floors))):
            floor = floors[number]
            lines += [f"floor{number + 1}_map:   ; {len(floor.tiles)} tiles"] + byte_lines(floor.tile_map)
    return lines


def floors_include(floors: list[FloorArt], songs: list[str]) -> list[str]:
    """The fixed bank's per-floor tables: where each floor's map, colours and name are, its maps bank, its
    song."""
    numbers = range(1, len(floors) + 1)
    return ["; Made by tools/make_art.py: each floor's art and song, by floor.",
            "floor_maps:   .word " + ", ".join(f"floor{number}_map" for number in numbers),
            "floor_colours: .word " + ", ".join(f"floor{number}_colours" for number in numbers),
            "floor_names:  .word " + ", ".join(f"floor{number}_name" for number in numbers),
            "floor_kinds:  .word " + ", ".join(f"floor{number}_kinds" for number in numbers),
            "floor_banks:  .byte " + ", ".join(str(MAPS_BANKS[(number - 1) // FLOORS_PER_BANK])
                                                for number in numbers),
            "floor_songs:  .byte " + ", ".join(songs)]


def floor_song_names(shareable: bool) -> list[str | None]:
    if not shareable:
        return FAITHFUL_SONGS
    with open(MANSION_MUSIC) as music_file:
        return json.load(music_file)["floor_songs"]


def main() -> None:
    shareable = "--shareable" in sys.argv
    output = os.path.join(ROOT, "build", "shareable" if shareable else "faithful", "art")
    floor_set, names = floor_looks(shareable)
    look = floor_set[0]
    font, status_names = status_tiles(look)
    floors = floor_art(floor_set, names)
    chr_data = b"".join(b"".join(font + floor.tiles).ljust(SET_BYTES, b"\0") for floor in floors)
    lines = ["; Made by tools/make_art.py from the remaster's NES look. Never commit this file.", "",
             f"FONT_TILES = {FONT_TILES}"] + status_names + [""] + maps_banks(floors)
    sprites = SpriteTiles()
    sprite_lines = sprite_include(look, sprites)
    chr_data += b"".join(sprites.pairs).ljust(SET_BYTES, b"\0")
    screen_chr, screen_lines = screen_sets(look)
    chr_data += screen_chr
    songs = [f"SONG_{name.upper()}" if name else "NO_SONG" for name in floor_song_names(shareable)]
    os.makedirs(output, exist_ok=True)
    with open(os.path.join(output, "tiles.chr"), "wb") as chr_file:
        chr_file.write(bytes(chr_data).ljust(CHR_BYTES, b"\0"))
    for file_name, text in (("art.inc", lines), ("font.inc", [font_map()]), ("screens.inc", screen_lines),
                            ("sprites.inc", sprite_lines), ("floors.inc", floors_include(floors, songs))):
        with open(os.path.join(output, file_name), "w") as include:
            include.write("\n".join(text) + "\n")
    print(f"{len(sprites.pairs)} sprite tile pairs of {SPRITE_PAIRS}")
    print(output)


if __name__ == "__main__":
    main()
