"""A picture of a mansion's plans (tools/mansion.py), to look at: each floor side by side, the first on the
left; rooms in their own colours, walls dark, doorways light, each room's middle a dot, stairs as arrows
(games 1-8; game 9's are listed under the floor), locked doors (games 3-8) marked with a bar.

Usage: python tools/draw_mansion.py [mansion/floors.txt]      (saves shots/mansion.png)
"""

import os
import sys

from PIL import Image, ImageDraw

import mansion as M

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "shots", "mansion.png")
CELL_PIXELS = 18
GAP = 24                     # between floors
LABEL_ROWS = 52              # under each floor: its name, game 9's stairs
WALL_COLOUR = (40, 36, 48)
DOORWAY_COLOUR = (230, 220, 190)
LOCK_COLOUR = (200, 40, 40)
INK = (20, 20, 20)
BACKGROUND = (250, 248, 240)
ROOM_COLOURS = [(150, 190, 230), (170, 220, 170), (240, 200, 140), (220, 170, 210), (180, 210, 210),
                (230, 230, 150)]
Point = tuple[int, int]


def cell_box(left: int, column: int, row: int) -> tuple[int, int, int, int]:
    """A cell's pixels: rows are drawn top first, as in the text."""
    top = (M.ROWS - 1 - row) * CELL_PIXELS
    x = left + column * CELL_PIXELS
    return x, top, x + CELL_PIXELS - 1, top + CELL_PIXELS - 1


def cell_colour(plan: M.Plan, column: int, row: int) -> tuple[int, int, int]:
    for room, cells in plan.rooms.items():
        if (column, row) in cells:
            return ROOM_COLOURS[room]
    return DOORWAY_COLOUR if plan.cells[row][column] == M.DOORWAY else WALL_COLOUR


def stairs_cell(plan: M.Plan, room: int) -> Point:
    if room == 2:
        return M.COLUMNS - 1, M.MIDDLE_ROW
    if room == 3:
        return 0, M.MIDDLE_ROW
    return plan.edge_column(room), 0 if room < 2 else M.ROWS - 1


def draw_floor(picture: ImageDraw.ImageDraw, left: int, floor: M.Floor) -> None:
    plan = M.Plan(floor)
    for row in range(M.ROWS):
        for column in range(M.COLUMNS):
            picture.rectangle(cell_box(left, column, row), fill=cell_colour(plan, column, row))
    for column, row in plan.middles.values():
        x0, y0, x1, y1 = cell_box(left, column, row)
        picture.ellipse((x0 + 5, y0 + 5, x1 - 5, y1 - 5), fill=INK)
    for door in floor.locked:
        if door in plan.doorways:
            x0, y0, x1, y1 = cell_box(left, *plan.doorways[door])
            picture.rectangle((x0 + 2, y0 + 7, x1 - 2, y1 - 7), fill=LOCK_COLOUR)
    for room, upward in floor.stairs.items():
        x0, y0, x1, y1 = cell_box(left, *stairs_cell(plan, room))
        middle = (x0 + x1) // 2
        tip, base = (y0 + 3, y1 - 3) if upward else (y1 - 3, y0 + 3)
        picture.polygon([(middle, tip), (x0 + 3, base), (x1 - 3, base)], fill=INK)
    bottom = M.ROWS * CELL_PIXELS
    picture.text((left, bottom + 6), floor.name, fill=INK)
    game9 = ", ".join(f"{room} {'up' if upward else 'down'}" for room, upward in floor.game9_stairs.items())
    picture.text((left, bottom + 22), f"game 9: {game9}", fill=INK)


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "mansion", "floors.txt")
    with open(path) as mansion_file:
        floors = M.parse(mansion_file.read())
    floor_width = M.COLUMNS * CELL_PIXELS
    width = len(floors) * floor_width + (len(floors) + 1) * GAP
    image = Image.new("RGB", (width, M.ROWS * CELL_PIXELS + LABEL_ROWS + GAP), BACKGROUND)
    picture = ImageDraw.Draw(image)
    for number, floor in enumerate(floors):
        left = GAP + number * (floor_width + GAP)
        draw_floor(picture, left, floor)
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    image.resize((image.width * 2, image.height * 2), Image.Resampling.NEAREST).save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
