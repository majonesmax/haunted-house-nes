"""The full screens' pictures, for tools/make_art.py: the title (and game over, the help and the story,
which share its tiles) and the ending - laid out as the remaster's NES look lays them out (its
looks/nes/look.py), cut into NES tiles.

Each screen has its own tile set - the font, the logo's big letters, the mansion, the sky - and a
nametable of its picture; the code writes the words on it. Its background palettes:
  title:   0 white words (and stars), 1-2 the mansion, 3 grey words (the rules, the hints)
  ending:  0 white words on the night that's left, 1-2 the mansion, 3 the dawn; the backdrop is the
           dawn's lowest colour, which shows behind the mansion
The mansion's two palettes are chosen so the fewest pixels are lost, and each 16 x 16 block of it takes
whichever fits it better.
"""

import itertools
from collections.abc import Callable

import numpy as np

from looks.nes import look as NL
from shared import hud
from shared import palettes as PAL

SCREEN_W, SCREEN_H = 256, 240
TILE = 8
COLUMNS, ROWS = SCREEN_W // TILE, SCREEN_H // TILE
BLOCK = 16
BIG = 2                                # the logo's letters are twice the font's size
LOGO_LETTERS = "HAUNTEDOSGMVRYCP!"     # every letter of HAUNTED HOUSE, GAME OVER, YOU ESCAPED!
WHITE_INK, BACKING_INK, SHADOW_INK = 1, 2, 3
BLACK = 0x0F
TITLE_SKY, TITLE_FLASH = 0x01, 0x31    # the night sky, and in a lightning flash
TITLE_WORDS = [0x30, 0x10, 0x16]       # palette 0: white, (grey), the logo's red shadow
TITLE_GREY = [0x10, 0x00, 0x16]        # palette 3: grey words
ENDING_WORDS = [0x30, 0x01, 0x16]      # palette 0: white on the night that's left, the red shadow
ENDING_BACKDROP = 0x27                 # the dawn's lowest colour, behind the mansion
DAWN = [0x01, 0x13, 0x24]              # palette 3: the dawn's upper colours
# (from this row, this colour): the orange reaches up to just above the mansion, so its blocks - whose sky
# is the backdrop - meet sky of the same colour
DAWN_BANDS = [(0, 0x01), (64, 0x13), (88, 0x24), (112, ENDING_BACKDROP)]
DAWN_MIX_ROWS = 4                      # where two bands meet they mix, on alternate rows
WORDS_ROWS = 8                         # the ending's words: the top eight tile rows
TileBytes = Callable[[np.ndarray], bytes]


def nes_rgb(code: int) -> np.ndarray:
    return np.array(PAL.NES[code], int)


def nearest_code(rgb: np.ndarray) -> int:
    colours = np.array(PAL.NES, int)
    distances = ((colours - rgb) ** 2).sum(axis=1).astype(float)
    distances[[0x0D, 0x0E, 0x1D, 0x1E, 0x1F, 0x2D, 0x2E, 0x2F, 0x3D, 0x3E, 0x3F]] = np.inf
    distances[BLACK] = distances[BLACK] if rgb.sum() == 0 else np.inf
    return int(distances.argmin())


# --- the words ------------------------------------------------------------------------------------------
def glyph_tile(letter: str, backing: bool) -> np.ndarray:
    """One letter of the font in white - on the backing colour if `backing`."""
    tile = np.full((TILE, TILE), BACKING_INK if backing else 0, np.uint8)
    glyph = hud.GLYPHS[letter]
    for row in range(7):
        for column in range(5):
            if glyph[row * 5 + column] == "#":
                tile[row, column + 1] = WHITE_INK
    return tile


def big_letter(letter: str, backing: bool) -> np.ndarray:
    """A 16 x 16 cell: the glyph at twice size in white, its shadow two pixels down and right in red."""
    cell = np.full((BLOCK, BLOCK), BACKING_INK if backing else 0, np.uint8)
    glyph = hud.GLYPHS[letter]
    for ink, offset in ((SHADOW_INK, BIG), (WHITE_INK, 0)):
        for row in range(7):
            for column in range(5):
                if glyph[row * 5 + column] == "#":
                    top, left = row * BIG + offset, column * BIG + offset
                    cell[top:top + BIG, left:left + BIG] = ink
    return cell


def word_tiles(font_order: str, backing: bool, tile_bytes: TileBytes) -> tuple[list[bytes], list[str]]:
    """The font (in font_order, so text means the same tiles as elsewhere) and the big letters (each 4
    tiles: top left, top right, bottom left, bottom right, in LOGO_LETTERS order)."""
    tiles = [tile_bytes(glyph_tile(letter, backing)) for letter in font_order]
    names = [f"BIG_LETTERS = {len(tiles)}   ; 4 tiles each, in the order: {LOGO_LETTERS}"]
    for letter in LOGO_LETTERS:
        cell = big_letter(letter, backing)
        quarters = [cell[top:top + TILE, left:left + TILE] for top in (0, TILE) for left in (0, TILE)]
        tiles += [tile_bytes(quarter) for quarter in quarters]
    return tiles, names


# --- the pictures ---------------------------------------------------------------------------------------
def mansion_palettes(mansion: np.ndarray) -> list[list[int]]:
    """Two palettes of three colours for the mansion (black in both, as its outline), chosen so the fewest
    pixels come out wrong, block by block at its size on screen."""
    scale = NL.MANSION_SCALE
    big = mansion.repeat(scale, axis=0).repeat(scale, axis=1)
    solid = mansion[..., 3] > 0
    others = sorted({nearest_code(colour) for colour in mansion[solid][:, :3]} - {BLACK})
    best: tuple[int, list[list[int]]] | None = None
    for first in itertools.combinations(others, min(2, len(others))):
        rest = [code for code in others if code not in first]
        palettes = [([BLACK, *first] + [BLACK] * 3)[:3], ([BLACK, *rest] + [BLACK] * 3)[:3]]
        lost = sum(Screen.best_fit(big[top:top + BLOCK, left:left + BLOCK], palettes)[2]
                   for top in range(0, big.shape[0], BLOCK) for left in range(0, big.shape[1], BLOCK))
        if best is None or lost < best[0]:
            best = (lost, palettes)
    assert best is not None
    return best[1]


class Screen:
    """A full screen being made: its picture as colour numbers 0-3, and each 16 x 16 block's palette."""

    def __init__(self) -> None:
        self.inks = np.zeros((SCREEN_H, SCREEN_W), np.uint8)
        self.blocks = np.zeros((SCREEN_H // BLOCK + 1, SCREEN_W // BLOCK), np.uint8)

    def place_mansion(self, mansion: np.ndarray, palettes: list[list[int]]) -> None:
        """The mansion at its place and size; each block in whichever of palettes 1 and 2 fits it best."""
        scale = NL.MANSION_SCALE
        big = mansion.repeat(scale, axis=0).repeat(scale, axis=1)
        left, top = NL.MANSION_AT
        big = big[:SCREEN_H - top]
        canvas = np.zeros((SCREEN_H, SCREEN_W, 4), np.uint8)
        canvas[top:top + big.shape[0], left:left + big.shape[1]] = big
        for block_top in range(0, SCREEN_H, BLOCK):
            for block_left in range(0, SCREEN_W, BLOCK):
                block = canvas[block_top:block_top + BLOCK, block_left:block_left + BLOCK]
                if not (block[..., 3] > 0).any():
                    continue
                number, inks, _lost = self.best_fit(block, palettes)
                area = self.inks[block_top:block_top + BLOCK, block_left:block_left + BLOCK]
                np.copyto(area, inks, where=block[..., 3] > 0)
                self.blocks[block_top // BLOCK, block_left // BLOCK] = number + 1

    @staticmethod
    def best_fit(block: np.ndarray, palettes: list[list[int]]) -> tuple[int, np.ndarray, int]:
        """(the palette that fits a block best, its pixels as colour numbers 1-3, how many come out wrong)."""
        solid = block[..., 3].reshape(-1) > 0
        pixels = block[..., :3].reshape(-1, 3).astype(int)
        results = []
        for palette in palettes:
            choices = np.array([nes_rgb(code) for code in palette])
            distances = ((pixels[:, None] - choices[None]) ** 2).sum(axis=2)
            inks = (distances.argmin(axis=1) + 1).reshape(block.shape[:2]).astype(np.uint8)
            wrong = int((distances.min(axis=1)[solid] > 0).sum())
            results.append((wrong, inks))
        number = int(np.argmin([wrong for wrong, _inks in results]))
        return number, results[number][1], results[number][0]

    def place_stars(self, stars: list[tuple[int, int]]) -> None:
        for x, y in stars:
            if not self.inks[y, x] and not self.blocks[y // BLOCK, x // BLOCK]:
                self.inks[y, x] = WHITE_INK

    def grey_rows(self, first_row: int, last_row: int) -> None:
        """Blocks between these tile rows (not the mansion's) in palette 3: the grey words go there."""
        for block_row in range(first_row // 2, last_row // 2 + 1):
            row = self.blocks[block_row]
            row[row == 0] = 3

    def place_dawn(self) -> None:
        """Below the words' rows, the sky (not the mansion's blocks) in the dawn's bands, palette 3: each
        band its colour number, mixing with the next on alternate rows where they meet; the lowest band is
        the backdrop."""
        words = self.inks[:WORDS_ROWS * TILE]
        words[words == 0] = BACKING_INK    # the night that's left, behind the words
        codes = [ENDING_BACKDROP] + DAWN
        band_inks = [codes.index(code) if code in codes else 0 for _top, code in DAWN_BANDS]
        for row in range(SCREEN_H):
            ink = band_inks[0]
            for (top, _code), band_ink in zip(DAWN_BANDS, band_inks):
                if row >= top:
                    ink = band_ink
            mixing = [top for top, _code in DAWN_BANDS[1:] if top <= row < top + DAWN_MIX_ROWS]
            if mixing and (row - mixing[0]) % 2 == 0:
                ink = band_inks[[top for top, _code in DAWN_BANDS].index(mixing[0]) - 1]
            for column in range(SCREEN_W):
                block = self.blocks[row // BLOCK, column // BLOCK]
                if block in (0, 3) and row >= WORDS_ROWS * TILE and not self.inks[row, column]:
                    self.inks[row, column] = ink
                    self.blocks[row // BLOCK, column // BLOCK] = 3

    def tiles(self, first: int, distinct: dict[bytes, int], tiles: list[bytes],
              tile_bytes: TileBytes) -> list[int]:
        """The screen's nametable: each 8 x 8's tile number; new tiles go in `tiles`, numbered from first."""
        table = []
        for row in range(ROWS):
            for column in range(COLUMNS):
                piece = self.inks[row * TILE:(row + 1) * TILE, column * TILE:(column + 1) * TILE]
                data = tile_bytes(piece)
                if data not in distinct:
                    distinct[data] = first + len(tiles)
                    tiles.append(data)
                table.append(distinct[data])
        return table

    def attributes(self) -> list[int]:
        """The nametable's 64 attribute bytes, from the blocks' palettes."""
        out = []
        for byte_row in range(8):
            for byte_column in range(8):
                value = 0
                for quadrant, (down, across) in enumerate(((0, 0), (0, 1), (1, 0), (1, 1))):
                    row, column = byte_row * 2 + down, byte_column * 2 + across
                    if row < len(self.blocks):
                        value |= int(self.blocks[row, column]) << (quadrant * 2)
                out.append(value)
        return out
