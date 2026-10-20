"""The shareable build's mansion: build/shareable/mansion.inc, in the same form as tools/extract.py's, but
with nothing from the 2600 ROM in it:

- the floors from mansion/floors.txt (tools/mansion.py works out their tables);
- the shapes touching is worked out from, made from our own pictures (the remaster's NES look of its classic
  pack, as tools/make_art.py draws them): each picture's outline fitted into the 2600's 8-unit-wide box, so
  what touches is what's seen;
- the rules' numbers that the spec leaves to the ROM, chosen here: the monsters' speeds and where they aim,
  how long each sound effect lasts (as long as our own effects play), and the mood sound's random bits.
  What the spec says in words (a new game's bytes, the rooms' steps) is written as it says.

Usage: python tools/shareable.py
"""

import os
import random
import sys

import numpy as np

import extract as E
import make_art as A
import make_music as S
import mansion as M
import rom_image as I

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, E.REMASTER)
import looks  # noqa: E402


MANSION_TEXT = os.path.join(ROOT, "mansion", "floors.txt")
OUTPUT = os.path.join(ROOT, "build", "shareable", "mansion.inc")
HEADER = "; The new mansion and its rules: tools/shareable.py, from mansion/floors.txt and our own art."
SHAPE_WIDTH = 8
ITEM_LINES, MONSTER_LINES, STAIRS_LINES = 8, 10, 17
ITEM_SHAPES, MONSTER_SHAPES, STAIRS_SHAPES = 0x08, 0x50, 0x8C   # where each kind starts in the page
PAGE = 256
SOLID = 0.5                  # a unit is solid if at least this much of the picture under it is
DARK = 80                    # the eyes' pupils: darker than this
RANDOM_SEED = "haunted house nes"

# the spec's words: 9 lives, no room beyond, the mood sound silent, mode $02, carrying nothing, no stairs,
# room 2, urn shapes 2, 3, 4 (three single pieces) - into $96-$9F
NEW_GAME = [9, 0xFF, 0x7F, 0x02, 0xFF, 0x0F, 2, 2, 3, 4]
ROOM_STEP = [1, 0xFF, 2, 0xFE]          # through a door: left +1, right -1, up +2, down -2 (the spec's)
WAYPOINT_START = [0, M.ROOM_COUNT, M.ROOM_COUNT + M.DOOR_COUNT, M.ROOM_COUNT + M.DOOR_COUNT]
# per monster (ghost, bat, three tarantulas): the frames of every 8 it steps on while chasing, a bit each;
# wandering is always frames 3 and 7, so each chases faster than it wanders, and all slower than you
MONSTER_SPEED = [0b01010101, 0b01011011, 0b01001001, 0b10010010, 0b00100101]
MONSTER_SPEED_FAST = [0b01110111, 0b01111111, 0b01010101, 0b10101010, 0b01011011]   # games 8-9
# per monster, taken from the player's place for the point it heads for: the ghost and the bat come
# straight at you, the tarantulas from below, from the left, and from both
CHASE_OFFSET_X = [0, 0, 0, 8, 8]
CHASE_OFFSET_Y = [0, 0, 8, 0, 8]
DROP_STEP = 0x0A             # a dropped item tries left, below, right and above, this far away...
DROP_OFFSETS = [0, DROP_STEP, 0, (-DROP_STEP) & 0xFF, 0]   # ...read as x [0-3] and y [1-4] (the spec's order)
MONSTER_FRAMES = [0, 20, 40, 40, 40]    # each monster's two pictures in the page (the tarantulas share one)
# how long each effect lasts (the game's numbers 2-11), as our own effects for those moments play
EFFECT_FOR_SOUND = {2: "locked", 3: "bump", 4: "door_open", 5: "drop", 6: "pickup_scepter", 7: "urn_join",
                    8: "door_close", 9: "stairs_up", 10: "stairs_down", 11: "urn_whole"}
SOUNDS = 12


# --- shapes from our pictures ---------------------------------------------------------------------------
def fitted(mask: np.ndarray, lines: int, width: int = SHAPE_WIDTH) -> np.ndarray:
    """A picture's outline (True where solid) fitted into `lines` x `width` units by how much of each
    unit's share of it is solid."""
    rows, columns = mask.shape
    fit = np.zeros((lines, width), bool)
    for line in range(lines):
        for unit in range(width):
            top, bottom = line * rows / lines, (line + 1) * rows / lines
            left, right = unit * columns / width, (unit + 1) * columns / width
            share = mask[int(top):max(int(np.ceil(bottom)), int(top) + 1),
                         int(left):max(int(np.ceil(right)), int(left) + 1)]
            fit[line, unit] = share.mean() >= SOLID
    return fit


def row_byte(row: np.ndarray) -> int:
    return sum(0x80 >> unit for unit in range(SHAPE_WIDTH) if row[unit])


def shape_bytes(fit: np.ndarray) -> bytes:
    """Bottom row first, as the 2600 keeps its pictures; bit 7 is the leftmost unit."""
    return bytes(row_byte(row) for row in fit[::-1])


def outline(look: "looks.FloorLook", entry: str) -> np.ndarray:
    return A.cast_picture(look, entry)[..., 3] > 0


def shapes_page(look: "looks.FloorLook") -> bytes:
    page = bytearray(PAGE)
    page[0:8] = bytes(1 << bit for bit in range(8))   # the bits, which the game uses as masks everywhere
    items = ["key", "scepter"] + [f"urn{shape}:0" for shape in range(2, 9)]
    for number, entry in enumerate(items):
        start = ITEM_SHAPES + number * ITEM_LINES
        page[start:start + ITEM_LINES] = shape_bytes(fitted(outline(look, entry), ITEM_LINES))
    for name, place in (("ghost", 0), ("bat", 20), ("tarantula2", 40)):
        for frame in (0, 1):
            start = MONSTER_SHAPES + place + frame * MONSTER_LINES
            picture = outline(look, f"{name}_down:{frame}")
            page[start:start + MONSTER_LINES] = shape_bytes(fitted(picture, MONSTER_LINES))
    stairs = outline(look, "stairs_up") | outline(look, "stairs_down")
    for number in range(4):   # each picture serves an edge going down and another going up: one shape
        start = STAIRS_SHAPES + number * STAIRS_LINES
        page[start:start + STAIRS_LINES] = shape_bytes(fitted(stairs, STAIRS_LINES))
    return bytes(page)


def eyes_bytes(look: "looks.FloorLook") -> list[tuple[str, int]]:
    """The eyes' row (both eyes), and the row with the pupils looking ahead, right and left: the whites."""
    whole = fitted(outline(look, "eyes_centre"), 3)
    eyes = [("eyes_row", row_byte(whole[1]))]
    for label, entry in (("pupils_ahead", "eyes_centre"), ("pupils_right", "eyes_right"),
                         ("pupils_left", "eyes_left")):
        picture = A.cast_picture(look, entry)
        whites = (picture[..., 3] > 0) & (picture[..., :3].mean(axis=2) >= DARK)
        eyes.append((label, row_byte(fitted(whites, 3)[1])))
    return eyes


# --- the rules' numbers and the floors ------------------------------------------------------------------
def sound_lengths() -> bytes:
    lengths = bytearray(SOUNDS)
    for sound, effect in EFFECT_FOR_SOUND.items():
        lengths[sound] = max(len(frames) for frames in S.EFFECTS[effect].values())
    return bytes(lengths)


def random_bits() -> bytes:
    return random.Random(RANDOM_SEED).randbytes(32)


def floor_tables(floors: list[M.Floor]) -> dict[str, bytes]:
    per_floor = [M.floor_tables(floor) for floor in floors]
    tables = {label: b"".join(tables[label] for tables in per_floor) for label in E.PER_FLOOR}
    return tables | M.game_tables(floors)


def all_tables(floors: list[M.Floor], look: "looks.FloorLook") -> dict[str, tuple[bytes, str]]:
    made = floor_tables(floors) | {
        "room_step": bytes(ROOM_STEP), "waypoint_start": bytes(WAYPOINT_START), "new_game": bytes(NEW_GAME),
        "monster_speed": bytes(MONSTER_SPEED), "monster_speed_fast": bytes(MONSTER_SPEED_FAST),
        "chase_offset_x": bytes(CHASE_OFFSET_X), "chase_offset_y": bytes(CHASE_OFFSET_Y),
        "drop_offsets": bytes(DROP_OFFSETS), "sound_lengths": sound_lengths(),
        "monster_frames": bytes(MONSTER_FRAMES), "shapes": shapes_page(look)}
    return {label: (made[label], what) for label, _address, _length, what in E.TABLES}


def main() -> None:
    with open(MANSION_TEXT) as mansion_file:
        floors = M.parse(mansion_file.read())
    look = looks.make("nes", bytes(I.IMAGE_SIZE))   # (the cast's pictures need nothing from a ROM)
    constants = E.CONSTANTS + [("GHOST_START_FLOOR", len(floors) - 1), ("FLOOR_COUNT", len(floors))]
    text = E.include_text(HEADER, constants, all_tables(floors, look), eyes_bytes(look), random_bits())
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w") as include:
        include.write(text)
    print(OUTPUT)


if __name__ == "__main__":
    main()
