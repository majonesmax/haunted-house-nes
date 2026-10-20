"""A stand-in for the 2600 ROM, for the shareable build: 4K with our own tables where the original keeps its
own, so code written for the original's ROM - the remaster's look, which draws a floor from the wall plan
at $FFD4 - reads our mansion instead. One image per floor: the tables that differ from floor to floor hold
that floor's part. Nothing in it is the original's.

    floor_image(tables, floor, eyes, bits)   the image for one floor

The model (the remaster's game/player.py) also reads two small tables from the original's code: the order
the doorway crossings are tested in, and each direction's stick bit. They're the rules', as the spec gives
them (and as the NES engine has them, src/main.s), so the images have them too.
"""

import extract as E

from game import player as P
from game import rom as R

IMAGE_SIZE = 0x1000
# the crossings, last first (the model reads them from the end): right, left, down into the middle, down
# into the bottom, up from the middle, up from the bottom - as directions 0 left, 1 right, 2 up, 3 down
DOORWAY_DIRECTIONS = bytes([1, 0, 3, 3, 2, 2])
DIRECTION_STICK = bytes([0x40, 0x80, 0x10, 0x20])   # the stick's bit for left, right, up, down
COLUMN_BITS = 0xFE00         # the bits 1, 2, 4 ... 128, which the game uses as masks (the wall test's too)
RANDOM_BYTES = 256           # the mood sound reads bit 0 of these, from RANDOM_BITS_FROM


def floor_image(tables: dict[str, bytes], floor: int, eyes: list[tuple[str, int]], bits: bytes) -> bytes:
    """tables: by tools/extract.py's labels, the per-floor ones a part per floor."""
    image = bytearray(IMAGE_SIZE)
    start = COLUMN_BITS - R.ROM_START
    image[start:start + 8] = bytes(1 << bit for bit in range(8))   # (the shapes' page, if given, starts so)
    for address, data in ((P.DOORWAY_DIRECTIONS, DOORWAY_DIRECTIONS), (P.DIRECTION_STICK, DIRECTION_STICK)):
        image[address - R.ROM_START:address - R.ROM_START + len(data)] = data
    for label, address, length, _what in E.TABLES:
        if label not in tables:   # (only what's given: the look needs just the plan)
            continue
        data = tables[label]
        if label in E.PER_FLOOR:
            data = data[floor * length:(floor + 1) * length]
        start = address - R.ROM_START
        image[start:start + len(data)] = data
    addresses = dict(E.EYES)
    for label, value in eyes:
        image[addresses[label] - R.ROM_START] = value
    start = E.RANDOM_BITS_FROM - R.ROM_START
    for index in range(RANDOM_BYTES):
        image[start + index] = bits[index >> 3] >> (index & 7) & 1
    return bytes(image)
