"""A floor's picture in the NES's colours (docs/decisions.md, "a palette for walls and one for floors"): four
colours and black, in two lit palettes that share two of them.

  the walls' palette    the floor's main colour, the walls' main colour, the walls' second colour
  the floor's palette   the floor's main colour, the walls' main colour, the floor's second colour

Each 16 x 16 block of the screen takes whichever palette draws it better; sharing the two main colours means
a block across a wall's edge draws both sides. In the dark (game 1) a third palette keeps only the walls'
main colour, dimmed - the floor black, as the original shows it; a lightning flash shows the walls bright.

The blocks are the screen's: the picture starts at the nametable's column 1, so a block covers the
picture's columns 16b - 8 to 16b + 7.
"""

from typing import NamedTuple

import numpy as np

from shared import palettes as PAL

BLOCK = 16
PICTURE_LEFT = 8           # the picture's first column on the screen
BLOCK_COLUMNS = 16
BLACK = 0x0F
DIM_ROW, FLASH_ROWS = 0x10, 0x20   # a palette row darker; two rows lighter
KMEANS_ROUNDS = 25
NES = np.array(PAL.NES, int)
Indices = np.ndarray       # a picture as colour numbers 0-3


class FloorColours(NamedTuple):
    floor_main: int
    floor_second: int
    wall_main: int
    wall_second: int

    def walls_palette(self) -> list[int]:
        return [self.floor_main, self.wall_main, self.wall_second]

    def floors_palette(self) -> list[int]:
        return [self.floor_main, self.wall_main, self.floor_second]


def nes_code(rgb: np.ndarray) -> int:
    """The NES colour nearest an RGB colour (not one of the duplicate blacks)."""
    distances = ((NES - rgb) ** 2).sum(axis=1).astype(float)
    distances[[0x0D, 0x0E, 0x1D, 0x1E, 0x1F, 0x2E, 0x2F, 0x3E, 0x3F]] = np.inf
    return int(distances.argmin())


def two_colours(pixels: np.ndarray) -> tuple[int, int]:
    """The two NES colours that best stand for some pixels' non-black colours (a weighted k-means), the one
    covering more first."""
    colours, counts = np.unique(pixels.reshape(-1, 3), axis=0, return_counts=True)
    keep = colours.sum(axis=1) > 0
    distinct, weights = colours[keep].astype(float), counts[keep].astype(float)
    if len(distinct) == 0:
        return BLACK, BLACK
    centres = distinct[np.argsort(-weights)[:2]].copy()
    if len(centres) == 1:
        return nes_code(centres[0]), nes_code(centres[0])
    for _ in range(KMEANS_ROUNDS):
        nearest = ((distinct[:, None] - centres[None]) ** 2).sum(axis=2).argmin(axis=1)
        for index in range(2):
            mine = nearest == index
            if mine.any():
                centres[index] = (distinct[mine] * weights[mine, None]).sum(axis=0) / weights[mine].sum()
    nearest = ((distinct[:, None] - centres[None]) ** 2).sum(axis=2).argmin(axis=1)
    first, second = sorted(range(2), key=lambda index: -weights[nearest == index].sum())
    return nes_code(centres[first]), nes_code(centres[second])


def choose(picture: np.ndarray, walls: np.ndarray) -> FloorColours:
    """The floor's two colours from its floor's pixels, and the walls' two from theirs."""
    floor_main, floor_second = two_colours(picture[~walls])
    wall_main, wall_second = two_colours(picture[walls])
    return FloorColours(floor_main, floor_second, wall_main, wall_second)


def to_indices(picture: np.ndarray, codes: list[int]) -> Indices:
    """Each pixel as 0 (black) or 1-3 (the codes' colours), whichever is nearest."""
    choices = np.vstack([[0, 0, 0]] + [NES[code] for code in codes])
    pixels = picture.reshape(-1, 3).astype(int)
    nearest = ((pixels[:, None] - choices[None]) ** 2).sum(axis=2).argmin(axis=1)
    return nearest.reshape(picture.shape[:2]).astype(np.uint8)


def cut(picture: np.ndarray, colours: FloorColours) -> tuple[Indices, np.ndarray]:
    """The picture as colour numbers, each block in the palette that draws it better; and which blocks those
    are: (rows, BLOCK_COLUMNS), True for the floor's palette."""
    rows = picture.shape[0] // BLOCK
    indices = np.zeros(picture.shape[:2], np.uint8)
    kinds = np.zeros((rows, BLOCK_COLUMNS), bool)
    palettes = [colours.walls_palette(), colours.floors_palette()]
    for row in range(rows):
        for column in range(BLOCK_COLUMNS):
            left = max(0, column * BLOCK - PICTURE_LEFT)
            right = min(picture.shape[1], column * BLOCK + BLOCK - PICTURE_LEFT)
            block = picture[row * BLOCK:(row + 1) * BLOCK, left:right]
            errors = []
            for codes in palettes:
                drawn = np.vstack([[0, 0, 0]] + [NES[code] for code in codes])[to_indices(block, codes)]
                errors.append(((drawn - block.astype(int)) ** 2).sum())
            kinds[row, column] = errors[1] < errors[0]
            chosen = palettes[int(kinds[row, column])]
            indices[row * BLOCK:(row + 1) * BLOCK, left:right] = to_indices(block, chosen)
    return indices, kinds


def dimmer(code: int) -> int:
    return code - DIM_ROW if code >= DIM_ROW else code


def brighter(code: int) -> int:
    return min(code + FLASH_ROWS, 0x30 + (code & 0x0F))


def palette_bytes(colours: FloorColours) -> list[int]:
    """The floor's palettes as the code keeps them: the walls', the floor's, the dark (game 1), lightning."""
    dark = [BLACK, dimmer(colours.wall_main), BLACK]
    flash = [BLACK, brighter(colours.wall_main), BLACK]
    return colours.walls_palette() + colours.floors_palette() + dark + flash


def kind_bytes(kinds: np.ndarray) -> list[int]:
    """Two bytes a block row: bit c of byte c / 8 set where block column c takes the floor's palette."""
    out = []
    for row in kinds:
        for half in (row[:8], row[8:]):
            out.append(sum(1 << bit for bit, floor_palette in enumerate(half) if floor_palette))
    return out
