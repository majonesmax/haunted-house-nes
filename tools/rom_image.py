"""A stand-in for the 2600 ROM, for the shareable build: 4K with our own tables where the original keeps its
own, so code written for the original's ROM - the remaster's look, which draws a floor from the wall plan
at $FFD4 - reads our mansion instead. One image per floor: the tables that differ from floor to floor hold
that floor's part. Nothing in it is the original's.

    floor_image(tables, floor, eyes, bits)   the image for one floor
"""

import extract as E

from game import rom as R

IMAGE_SIZE = 0x1000
RANDOM_BYTES = 256           # the mood sound reads bit 0 of these, from RANDOM_BITS_FROM


def floor_image(tables: dict[str, bytes], floor: int, eyes: list[tuple[str, int]], bits: bytes) -> bytes:
    """tables: by tools/extract.py's labels, the per-floor ones a part per floor."""
    image = bytearray(IMAGE_SIZE)
    for label, address, length, _what in E.TABLES:
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
