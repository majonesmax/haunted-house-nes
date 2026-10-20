"""tools/mansion.py works the tables out as the original's are: the original's mansion, drawn as text from
your ROM's tables (here, never saved), comes back as exactly the ROM's bytes; and tools/check_mansion.py
finds nothing wrong with it.

Needs the remaster beside this repository (../haunted-house) with your ROM in it.

Usage: python tests/test_mansion.py      (exit code 1 on any difference)
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REMASTER = os.path.join(os.path.dirname(ROOT), "haunted-house")
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, REMASTER)
import check_mansion as C  # noqa: E402
import mansion as M  # noqa: E402
from extract import FLOOR_COUNT, TABLES  # noqa: E402

from game import rom as R  # noqa: E402

FLOORS_AND_GAME_9 = 2 * FLOOR_COUNT


def rom_table(rom: bytes, label: str) -> bytes:
    for name, address, length, _what in TABLES:
        if name == label:
            start = address - R.ROM_START
            return rom[start:start + length]
    raise KeyError(label)


def original_cells(rom: bytes) -> list[str]:
    """The original's plan as text cells, the bottom row first: walls, doorways, then each room flooded
    from its middle."""
    walls, lines = rom_table(rom, "mansion_walls"), rom_table(rom, "doorway_lines")
    across, upward = rom_table(rom, "waypoint_x"), rom_table(rom, "waypoint_y")
    wall_rows = {(lines[0] - 4) // M.CELL, (lines[2] - 4) // M.CELL}
    middle_wall = lines[11] // M.CELL - 1
    grid = [[M.WALL] * M.COLUMNS for _row in range(M.ROWS)]
    for row in range(M.ROWS):
        for column in range(M.COLUMNS):
            inside = 1 <= column <= M.PLAN_COLUMNS
            open_cell = not walls[row] >> (column - 1) & 1 if inside else row == M.MIDDLE_ROW
            doorway = row in wall_rows or (inside and column in (middle_wall, middle_wall + 1))
            if open_cell:
                grid[row][column] = M.DOORWAY if doorway else "?"
    for room in range(M.ROOM_COUNT):
        column, row = (across[room] - M.INSIDE) // M.CELL, (upward[room] - M.INSIDE) // M.CELL
        flood(grid, column, row, str(room))
        grid[row][column] = M.MIDDLE
    return ["".join(row) for row in grid]


def flood(grid: list[list[str]], column: int, row: int, room: str) -> None:
    waiting = [(column, row)]
    while waiting:
        column, row = waiting.pop()
        if 0 <= row < M.ROWS and 0 <= column < M.COLUMNS and grid[row][column] == "?":
            grid[row][column] = room
            waiting += [(column + 1, row), (column - 1, row), (column, row + 1), (column, row - 1)]


def by_floor(rom: bytes, label: str, floor: int) -> tuple[dict[int, bool], set[int]]:
    here, going_up = rom_table(rom, "stairs_here")[floor], rom_table(rom, "stairs_go_up")[floor]
    stairs = {room: bool(going_up >> room & 1) for room in range(M.ROOM_COUNT) if here >> room & 1}
    locked = rom_table(rom, label)[floor]
    return stairs, {door for door in range(M.DOOR_COUNT) if locked >> door & 1}


def original_floors(rom: bytes) -> list[M.Floor]:
    cells = original_cells(rom)
    floors = []
    for floor in range(FLOOR_COUNT):
        stairs, locked = by_floor(rom, "locked_doors", floor)
        game9_stairs, game9_locked = by_floor(rom, "locked_doors", floor + FLOOR_COUNT)
        floors.append(M.Floor(f"FLOOR {floor + 1}", cells, stairs, locked, game9_stairs, game9_locked))
    return floors


def main() -> None:
    rom = R.load()
    floors = original_floors(rom)
    for row in reversed(floors[0].cells):
        print("   " + row)
    differences = 0
    made = M.floor_tables(floors[0]) | M.game_tables(floors)
    for label, data in made.items():
        wanted = rom_table(rom, label)
        if label in M.GAME_TABLES:
            wanted = wanted[:FLOORS_AND_GAME_9]
        if data != wanted:
            differences += 1
            print(f"{label}: made {data.hex(' ')}\n{' ' * len(label)}  rom  {wanted.hex(' ')}")
    print(f"{len(made)} tables, {differences} different")
    problems = C.Checker(floors).run()
    for problem in problems:
        print(problem)
    print(f"the checker: {len(problems)} problems with the original")
    differences += len(problems)
    sys.exit(1 if differences else 0)


if __name__ == "__main__":
    main()
