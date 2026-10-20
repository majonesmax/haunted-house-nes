"""The faithful build's mansion: read the original's tables from your own 2600 ROM into
build/faithful/mansion.inc, an include file for the assembler. Never commit what this makes.

What it takes, and why (the remaster's docs/spec.md has what each one means):
- the mansion: walls, doors, locks, stairs, the doorway lines, the room limits, the monsters' waypoints;
- the rules' numbers: the new game's bytes, the monsters' speeds and chase offsets, where dropped items go,
  how long each sound lasts;
- the shapes touching is worked out from: the ROM page $FE00-$FEFF (items, monsters, stairs) and the eyes.
  The pictures shown are our own; these only decide what touches what, so the game plays the same;
- the 256 code bytes whose lowest bits the monster-noise sound uses as random numbers.

It must be the NTSC cartridge (Atari CX2654), MD5 f0a6e99f5875891246c3dbecbf2d2cea - the one the remaster
worked everything out on; the tables are read from fixed places in it, so another ROM would make a broken
build. docs/faithful-build.md has the whole recipe.

Usage: python tools/extract.py [path to your Haunted House ROM]
       (default: ../haunted-house/roms/haunted_house.a26, the remaster's)
"""

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REMASTER = os.path.join(os.path.dirname(ROOT), "haunted-house")
sys.path.insert(0, REMASTER)
from game import player as P  # noqa: E402
from game import rom as R  # noqa: E402

DEFAULT_ROM = os.path.join(REMASTER, "roms", "haunted_house.a26")
KNOWN_MD5 = "f0a6e99f5875891246c3dbecbf2d2cea"   # Haunted House, NTSC (Atari CX2654)
OUTPUT = os.path.join(ROOT, "build", "faithful", "mansion.inc")
BYTES_PER_LINE = 16
HEADER = "; The original mansion, read from your 2600 ROM by tools/extract.py. Never commit this file."

# (label, address, length, what it is). Addresses are the 2600's; the remaster's game/rom.py names them.
TABLES = [
    ("mansion_walls", 0xFFD4, 16, "the wall plan: a byte per 16-unit row, a bit per column"),
    ("door_ids", 0xFD82, 24, "per room: left, right, up, down - a door, $80 + room for the edge, $FF wall"),
    ("locked_doors", 0xFDD5, 8, "per floor, a bit per locked door; [4-7] game 9"),
    ("stairs_here", 0xFDDD, 8, "per floor, a bit per room with stairs; [4-7] game 9"),
    ("stairs_go_up", 0xFDE5, 8, "per floor, a bit per room whose stairs go up; [4-7] game 9"),
    ("stairs_edge", 0xFD46, 6, "per room, the edge its stairs are on: 0 left, 1 right, 2 top, 3 bottom"),
    ("stairs_x", 0xFF8C, 6, "per room, the x the stairs are drawn at"),
    ("stairs_y", 0xFF88, 4, "per edge, the y the stairs are drawn at"),
    ("room_bounds", 0xFD7F, 4, "the y limit through the doors above and below, by door number / 2; "
     "the 4th, read for a side door, only needs not to be 0"),
    ("room_step", 0xFFD0, 4, "the room number's change through a door: left, right, up, down"),
    ("doorway_lines", 0xFC68, 12, "where each crossing's doorway starts and ends"),
    ("waypoint_start", 0xFFA6, 4, "the first waypoint of each kind of plan"),
    ("waypoint_x", 0xFFAA, 19, "the monsters' waypoints: room centres, doors, stairs"),
    ("waypoint_y", 0xFFBD, 19, ""),
    ("new_game", 0xFDF6, 10, "what a new game puts in $96-$9F"),
    ("monster_speed", 0xFA86, 5, "per monster, the frames of 8 it steps on when chasing"),
    ("monster_speed_fast", 0xFA8B, 5, "the same in games 8-9"),
    ("chase_offset_x", 0xFDEC, 5, "per monster, taken from the player's x for the point it chases"),
    ("chase_offset_y", 0xFDF1, 5, ""),
    ("drop_offsets", 0xFD02, 5, "x offsets [0-3] and y offsets [1-4] of the spots a dropped item tries"),
    ("sound_lengths", 0xF8A0, 12, "how many frames each sound effect lasts"),
    ("monster_frames", 0xF5E2, 5, "per monster, its pictures' place in the shapes page"),
    ("shapes", 0xFE00, 256, "the page touching reads its shapes from ($FE00-$FEFF)"),
]
EYES = [("eyes_row", 0xF319), ("pupils_ahead", 0xF321), ("pupils_right", 0xF328), ("pupils_left", 0xF32D)]
# the mansion's sizes and places, as the spec gives them (from the remaster's game/rom.py and game/player.py)
CONSTANTS = [
    ("FLOOR_LEFT", R.FLOOR_LEFT), ("FLOOR_RIGHT", R.FLOOR_RIGHT), ("FLOOR_BOTTOM", R.FLOOR_BOTTOM),
    ("FLOOR_TOP", R.FLOOR_TOP), ("ROOM_COUNT", R.ROOM_COUNT), ("FRONT_DOOR_ROOM", R.FRONT_DOOR_ROOM),
    ("FRONT_DOOR_FLOOR", P.FRONT_DOOR_FLOOR), ("START_X", P.START_X), ("START_Y", P.START_Y),
    ("GAME_3_KEY_FLOOR", P.GAME_3_KEY[0]), ("GAME_3_KEY_X", P.GAME_3_KEY[1]),
    ("GAME_3_KEY_Y", P.GAME_3_KEY[2]),
    ("MIDDLE_ROW", P.MIDDLE_ROW), ("DROP_TOO_HIGH", P.DROP_TOO_HIGH),
    ("DROP_TOO_FAR_RIGHT", P.DROP_TOO_FAR_RIGHT),
    ("MASK_WITH_LEFT_DOOR", P.MASK_WITH_LEFT_DOOR[0]), ("MASK_2_WITH_LEFT_DOOR", P.MASK_WITH_LEFT_DOOR[1]),
    ("MASK_WITHOUT", P.MASK_WITHOUT[0]), ("MASK_2_WITHOUT", P.MASK_WITHOUT[1]),
]
# the tables that can differ from floor to floor: the faithful build gives each floor the original's one plan
PER_FLOOR = {"mansion_walls", "door_ids", "stairs_edge", "stairs_x", "stairs_y", "room_bounds",
             "doorway_lines", "waypoint_x", "waypoint_y"}
FLOOR_COUNT = 4
RANDOM_BITS_FROM = 0xF000   # the mood sound takes bit 0 of the byte at $F000 + a random number


def byte_lines(data: bytes) -> list[str]:
    lines = []
    for start in range(0, len(data), BYTES_PER_LINE):
        chunk = data[start:start + BYTES_PER_LINE]
        lines.append("    .byte " + ", ".join(f"${value:02X}" for value in chunk))
    return lines


def random_bits(rom: bytes) -> bytes:
    """Bit 0 of each of 256 bytes, packed eight to a byte (bit n of byte k is the byte at k * 8 + n)."""
    start = RANDOM_BITS_FROM - R.ROM_START
    packed = bytearray(32)
    for index in range(256):
        if rom[start + index] & 1:
            packed[index >> 3] |= 1 << (index & 7)
    return bytes(packed)


def include_text(header: str, constants: list[tuple[str, int]], tables: dict[str, tuple[bytes, str]],
                 eyes: list[tuple[str, int]], bits: bytes) -> str:
    """The include file: the constants, each table (by TABLES' labels: its bytes and what it is, the
    per-floor ones a part per floor), the eyes' bytes and the random bits. tools/shareable.py writes its
    mansion through this too."""
    lines = [header, "", "; the mansion's sizes and places"]
    lines += [f"{name} = ${value:02X}" for name, value in constants]
    lines += [f"{label.upper()}_SIZE = {length}" for label, _address, length, _what in TABLES
              if label in PER_FLOOR] + [""]
    for label, _address, _length, _what in TABLES:
        data, what = tables[label]
        lines += [f"{label}:" + (f"   ; {what}" if what else "")] + byte_lines(data)
    lines += ["", "; the eyes' rows, as the 2600 builds them"]
    lines += [f"{label} = ${value:02X}" for label, value in eyes]
    lines += ["", "random_bits:   ; the mood sound's random bits, eight to a byte"] + byte_lines(bits)
    return "\n".join(lines) + "\n"


def include_file(rom: bytes) -> str:
    tables = {}
    for label, address, length, what in TABLES:
        start = address - R.ROM_START
        data = rom[start:start + length]
        if label in PER_FLOOR:
            data, what = data * FLOOR_COUNT, f"{what} (the same plan on each floor)".lstrip(" ")
        tables[label] = (data, what)
    eyes = [(label, R.byte_at(rom, address)) for label, address in EYES]
    constants = CONSTANTS + [("GHOST_START_FLOOR", FLOOR_COUNT - 1), ("FLOOR_COUNT", FLOOR_COUNT)]
    return include_text(HEADER, constants, tables, eyes, random_bits(rom))


def checked_rom(rom_path: str) -> bytes:
    """The ROM, if it's there and it's the one the tables are known for; otherwise, say what to do."""
    if not os.path.exists(rom_path):
        sys.exit(f"No 2600 ROM at {rom_path}.\nThe faithful build reads the original's mansion from your own "
                 "copy of Haunted House: put it there (see docs/faithful-build.md).")
    with open(rom_path, "rb") as rom_file:
        fingerprint = hashlib.md5(rom_file.read()).hexdigest()
    if fingerprint != KNOWN_MD5:
        sys.exit(f"{rom_path} isn't the Haunted House cartridge this build knows (its MD5 is {fingerprint};\n"
                 f"the NTSC cartridge, Atari CX2654, is {KNOWN_MD5}). Its tables would be read from the "
                 "wrong places.")
    return R.load(rom_path)


def main() -> None:
    rom_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ROM
    rom = checked_rom(rom_path)
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w") as include:
        include.write(include_file(rom))
    print(OUTPUT)


if __name__ == "__main__":
    main()
