"""The README's pictures: the shareable ROM played in the emulator, and a few moments of it saved into
docs/media/ at twice size - the title, the Foyer by matchlight, three floors with the lights on, and the
ending. All of it is our own art, so the pictures may be committed.

To set the moments up quickly it writes the game's RAM between frames (where the eyes stand, what they hold),
as the tests do; the game itself is never changed.

Usage: python tools/readme_media.py
"""

import os
import sys

import numpy as np
from PIL import Image

import mansion as M
import nes as N
from build import build

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "docs", "media")
SCALE = 2
FLOOR, ROOM, PLAYER_X, PLAYER_Y, CARRIED, URN_SHAPES = 0x8D, 0x9C, 0xAA, 0xB5, 0x9A, 0x9D
MONSTER_FLOORS = 0xA5
OFF_EVERY_FLOOR = 7          # a monster's floor no floor has: out of the picture
WHOLE_URN, JOINED, URN = 8, 0xFF, 2
NOTE_GONE = 400              # frames for the cheat's note to have gone from the band
FLOORS_SHOWN = {"gallery": 2, "bedrooms": 3, "cellar": 0}   # name -> floor (0 the cellar)
SETTLE = 25                  # frames for a floor to be drawn after the eyes are put there


def save(machine: N.Nes, name: str) -> None:
    picture = Image.fromarray(np.asarray(machine.picture)[..., :3])
    picture = picture.resize((picture.width * SCALE, picture.height * SCALE), Image.Resampling.NEAREST)
    picture.save(os.path.join(OUTPUT, f"{name}.png"))
    print(name)


def new_machine(rom: str) -> N.Nes:
    machine = N.Nes(rom)
    machine.run(30, {N.BUTTON_A})            # past the story
    machine.run(90)                          # the title, settled
    return machine


def start_game(machine: N.Nes) -> None:
    machine.run(6, {N.BUTTON_START})
    machine.run(60)


def put_eyes(machine: N.Nes, floor: int, x: int, y: int) -> None:
    """The eyes in room 2 of a floor, the monsters elsewhere; held there while the floor is drawn."""
    for _ in range(SETTLE):
        machine.ram[FLOOR], machine.ram[ROOM] = floor, 2
        machine.ram[PLAYER_X], machine.ram[PLAYER_Y] = x, y
        machine.ram[MONSTER_FLOORS:MONSTER_FLOORS + 5] = OFF_EVERY_FLOOR
        machine.run(1)


def room_2_middle(floor: int) -> tuple[int, int]:
    with open(os.path.join(ROOT, "mansion", "floors.txt")) as mansion_file:
        tables = M.floor_tables(M.parse(mansion_file.read())[floor])
    return tables["waypoint_x"][2], tables["waypoint_y"][2]


def by_matchlight(rom: str) -> None:
    machine = new_machine(rom)
    start_game(machine)
    machine.run(5, {N.BUTTON_A})             # a match
    machine.run(20)
    machine.run(24, {N.BUTTON_LEFT})
    save(machine, "foyer_by_matchlight")


def lights_on(rom: str) -> None:
    machine = new_machine(rom)
    start_game(machine)
    machine.run(4, {N.BUTTON_B})
    machine.run(3, {N.BUTTON_B, N.BUTTON_SELECT})   # the lights-on cheat
    machine.run(4, {N.BUTTON_B})
    machine.run(NOTE_GONE)
    for name, floor in FLOORS_SHOWN.items():
        put_eyes(machine, floor, *room_2_middle(floor))
        machine.run(SETTLE)
        save(machine, name)


def ending(rom: str) -> None:
    machine = new_machine(rom)
    start_game(machine)
    machine.ram[URN_SHAPES:URN_SHAPES + 3] = [WHOLE_URN, JOINED, JOINED]   # the whole urn in hand
    machine.ram[CARRIED] = URN
    machine.run(60, {N.BUTTON_RIGHT})        # out of the front door
    machine.run(560)                         # the light, then the dawn and the verdict
    save(machine, "ending")


def main() -> None:
    rom = build(shareable=True)
    os.makedirs(OUTPUT, exist_ok=True)
    save(new_machine(rom), "title")
    by_matchlight(rom)
    lights_on(rom)
    ending(rom)


if __name__ == "__main__":
    sys.exit(main())
