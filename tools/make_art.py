"""The picture's tiles, made from the remaster's NES look: each floor drawn by the remaster's own scenery code
with its classic pack, cut down to three NES colours plus black (docs/plan.md, "The picture"), split into
8x8 tiles; and the remaster's NES font. The faithful build's floors carry the original's wall plan, so all
of this goes in build/ and is never committed.

Makes:
  build/art/tiles.chr   the cartridge's tile memory (CHR): per floor a 4K set (font, then the floor's
                        tiles), then the sprites' 4K
  build/art/art.inc     each floor's map (the tile on every 8x8 of its 240 x 512 picture), its colours, and
                        the light's shape
  build/art/font.inc    the font's character map, so text in the code is written as text
  build/art/sprites.inc the cast: each picture as 8x16 pieces, and each kind's three colours

Usage: python tools/make_art.py
"""

import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REMASTER = os.path.join(os.path.dirname(ROOT), "haunted-house")
sys.path.insert(0, REMASTER)
import looks  # noqa: E402
from game import rom as R  # noqa: E402
from shared import hud  # noqa: E402
from shared import palettes as PAL  # noqa: E402

OUTPUT = os.path.join(ROOT, "build", "art")
FLOORS = 4
TILE = 8
TILES_PER_SET = 256
FONT_TILES = 64            # tiles 0-63 of each set: the font and the status band's pieces
FONT_ORDER = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!.,-:'?<>/"
SET_BYTES = TILES_PER_SET * 16
CHR_BYTES = 32 * 1024      # four floor sets and the sprites' set, rounded up to a size the cartridge can be
BLACK = 0x0F
COLOURS = 3
KMEANS_ROUNDS = 25
NES = np.array(PAL.NES, int)
DIM_ROW, FLASH_ROWS = 0x10, 0x20   # a palette row darker; two rows lighter
LIGHT_HALF_WIDTH, LIGHT_HALF_HEIGHT = 24, 28   # px: the match's reach (the remaster's 16 units by 14 lines)
LIGHT_CORE, LIGHT_EDGE = 0.9, 1.3   # fully lit within this much of the reach; dim out to this
LIGHT_STEP = 4                      # the light table's steps, in px
LIGHT_STEPS = 16

Indices = np.ndarray       # a picture as colour numbers 0-3
SPRITE_W, SPRITE_H = 8, 16  # the NES's sprites, in 8x16 mode
SPRITE_PAIRS = 128         # tile pairs in the sprites' 4K
# Each kind of thing and its pictures (the remaster's cast names; frames after the colon). A kind shares
# three colours. Right-facing pictures the cast doesn't draw are the left ones mirrored, by the code.
CAST_KINDS = {
    "eyes": ["eyes_centre", "eyes_left", "eyes_right", "eyes_up", "eyes_down", "eyes_blink"],
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
}


def nes_code(rgb: np.ndarray) -> int:
    """The NES colour nearest an RGB colour (not one of the duplicate blacks)."""
    distances = ((NES - rgb) ** 2).sum(axis=1).astype(float)
    distances[[0x0D, 0x0E, 0x1D, 0x1E, 0x1F, 0x2E, 0x2F, 0x3E, 0x3F]] = np.inf
    return int(distances.argmin())


def three_colours(picture: np.ndarray) -> list[int]:
    """The three NES colours that best stand for a picture's non-black colours (a weighted k-means), dark
    first."""
    colours, counts = np.unique(picture.reshape(-1, 3), axis=0, return_counts=True)
    keep = colours.sum(axis=1) > 0
    distinct, weights = colours[keep].astype(float), counts[keep].astype(float)
    centres = distinct[np.argsort(-weights)[:COLOURS]]
    for _ in range(KMEANS_ROUNDS):
        nearest = ((distinct[:, None] - centres[None]) ** 2).sum(axis=2).argmin(axis=1)
        for index in range(COLOURS):
            mine = nearest == index
            if mine.any():
                centres[index] = (distinct[mine] * weights[mine, None]).sum(axis=0) / weights[mine].sum()
    codes = [nes_code(centre) for centre in centres]
    return sorted(codes, key=lambda code: NES[code].sum())


def to_indices(picture: np.ndarray, codes: list[int]) -> Indices:
    """Each pixel as 0 (black) or 1-3 (the codes' colours), whichever is nearest."""
    choices = np.vstack([[0, 0, 0]] + [NES[code] for code in codes])
    pixels = picture.reshape(-1, 3).astype(int)
    nearest = ((pixels[:, None] - choices[None]) ** 2).sum(axis=2).argmin(axis=1)
    return nearest.reshape(picture.shape[:2]).astype(np.uint8)


def tile_bytes(tile: Indices) -> bytes:
    """An 8x8 tile of colour numbers as the NES stores it: 8 bytes of low bits, then 8 of high bits."""
    def plane(bit: int) -> list[int]:
        return [int(sum(((tile[row, column] >> bit & 1) << (7 - column)) for column in range(TILE)))
                for row in range(TILE)]
    return bytes(plane(0) + plane(1))


def font_tiles() -> list[bytes]:
    """The remaster's 5x7 font, one glyph a tile in colour 1, in FONT_ORDER; the rest blank."""
    tiles = []
    for letter in FONT_ORDER:
        glyph = hud.GLYPHS[letter]
        tile = np.zeros((TILE, TILE), np.uint8)
        for row in range(7):
            for column in range(5):
                if glyph[row * 5 + column] == "#":
                    tile[row, column + 1] = 1
        tiles.append(tile_bytes(tile))
    return tiles + [bytes(16)] * (FONT_TILES - len(tiles))


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


def palettes(codes: list[int]) -> list[int]:
    """The floor's colours lit, dim (a row darker) and in a lightning flash (two rows lighter)."""
    dim = [code - DIM_ROW if code >= DIM_ROW else code for code in codes]   # the darkest row stays: game 1
                                                                            # must still see dark walls
    flash = [min(code + FLASH_ROWS, 0x30 + (code & 0x0F)) for code in codes]
    return codes + dim + flash


def light_table() -> list[int]:
    """The light at a block whose centre is (across, down) px from the eyes, in LIGHT_STEP steps of each:
    2 lit, 1 dim, 0 unlit. Row by row of `down`."""
    levels = []
    for down in range(LIGHT_STEPS):
        for across in range(LIGHT_STEPS):
            centre_x, centre_y = (across + 0.5) * LIGHT_STEP, (down + 0.5) * LIGHT_STEP
            reach = np.hypot(centre_x / LIGHT_HALF_WIDTH, centre_y / LIGHT_HALF_HEIGHT)
            levels.append(2 if reach <= LIGHT_CORE else 1 if reach <= LIGHT_EDGE else 0)
    return levels


def cast_picture(look: "looks.FloorLook", entry: str) -> np.ndarray:
    """A cast picture (RGBA) through the NES look's colours: "name" or "name:frame"."""
    name, _, frame = entry.partition(":")
    frames = look.pack.cast.must(name)
    return look.adapt(frames[int(frame) if frame else 0])


def sprite_indices(picture: np.ndarray, codes: list[int]) -> Indices:
    """Transparent 0; every other pixel the nearest of the kind's three colours, 1-3."""
    choices = np.array([NES[code] for code in codes])
    pixels = picture[..., :3].reshape(-1, 3).astype(int)
    nearest = ((pixels[:, None] - choices[None]) ** 2).sum(axis=2).argmin(axis=1) + 1
    solid = picture[..., 3].reshape(-1) > 0
    return np.where(solid, nearest, 0).reshape(picture.shape[:2]).astype(np.uint8)


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
        codes = kind_colours(pictures)
        lines.append(f"KIND_{kind.upper()} = {number}")
        colour_lines += byte_lines(codes)
        for entry, picture in zip(entries, pictures):
            pieces = sprite_pieces(sprite_indices(picture, codes), tiles)
            label = entry.replace(":", "_")
            lines.append(f"picture_{label}:   ; {picture.shape[1]} x {picture.shape[0]}")
            lines += byte_lines([picture.shape[1], picture.shape[0], len(pieces)])
            lines += byte_lines([value for piece in pieces for value in piece], 16)
    if len(tiles.pairs) > SPRITE_PAIRS:
        raise ValueError(f"the cast needs {len(tiles.pairs)} sprite tile pairs; there's room for 128")
    return lines + [""] + colour_lines + [""] + monster_tables()


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


def main() -> None:
    look = looks.make("nes", R.load())
    font = font_tiles()
    chr_data = bytearray()
    lines = ["; Made by tools/make_art.py from the remaster's NES look. Never commit this file.", "",
             f"FONT_TILES = {FONT_TILES}", ""]
    for floor in range(FLOORS):
        picture = look.scene(floor).full
        codes = three_colours(picture)
        tiles, tile_map = floor_tiles(to_indices(picture, codes))
        chr_data += b"".join(font + tiles).ljust(SET_BYTES, b"\0")
        lines += [f"floor{floor + 1}_map:   ; {len(tiles)} tiles"] + byte_lines(tile_map)
        lines += [f"floor{floor + 1}_colours:   ; lit, dim, lightning"] + byte_lines(palettes(codes), 9)
    sprites = SpriteTiles()
    sprite_lines = sprite_include(look, sprites)
    chr_data += b"".join(sprites.pairs).ljust(SET_BYTES, b"\0")
    names = look.pack.info.get("floors", [f"FLOOR {number + 1}" for number in range(FLOORS)])
    for floor, name in enumerate(names):
        lines += [f'floor{floor + 1}_name: .byte "{name.upper()}", $FF']   # (0 is a space)
    lines += ["light_levels:   ; by (down, across) from the eyes, 4 px steps: 2 lit, 1 dim, 0 unlit"]
    lines += byte_lines(light_table(), LIGHT_STEPS)
    os.makedirs(OUTPUT, exist_ok=True)
    with open(os.path.join(OUTPUT, "tiles.chr"), "wb") as chr_file:
        chr_file.write(bytes(chr_data).ljust(CHR_BYTES, b"\0"))
    with open(os.path.join(OUTPUT, "art.inc"), "w") as include:
        include.write("\n".join(lines) + "\n")
    with open(os.path.join(OUTPUT, "font.inc"), "w") as include:
        include.write(font_map())
    with open(os.path.join(OUTPUT, "sprites.inc"), "w") as include:
        include.write("\n".join(sprite_lines) + "\n")
    print(f"{len(sprites.pairs)} sprite tile pairs of {SPRITE_PAIRS}")
    print(OUTPUT)


if __name__ == "__main__":
    main()
