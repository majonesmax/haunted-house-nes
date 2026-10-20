"""A mansion drawn as text, made into the tables the engine reads (the same ones tools/extract.py takes from
the original): the shareable build's mansion is a file of these, mansion/floors.txt.

A floor is 16 rows of 10 cells, the top row first; each cell is 16 x 16 units of the floor. The middle eight
columns are the wall plan; the outer two are outside it, wall except in row 8 (the middle row), where the
front door and the side stairs are. In a cell:
  #        wall
  0-5      the room it belongs to (2 x 3 rooms, as the original's: even on the right, 0 and 1 at the bottom)
  @        the room's middle, where monsters go between doors (a room's cell too)
  +        a doorway: in a wall row between two rows of rooms, or both cells of the middle wall's gap

The rooms' rows are split by two wall rows, and the two columns by a wall two cells thick: their places can
change from floor to floor; the numbers the game uses (doorway lines, room limits, waypoints, the stairs'
places) are worked out from them, as the original's are from its plan. Each floor also says its name, the
rooms with stairs (up or down), and the doors locked in games 3-8, then the same two for game 9:

  floor THE FOYER
  stairs 0 up, 3 down
  locked 0-2, 4-5
  game 9 stairs 0 up
  game 9 locked
  ##5####4##
  ...

A door is named by the two rooms it joins. Lines starting with ; are comments. Before the floors, a line
"front door on floor N" says which floor has the front door, where a new game starts (counting the first in
the file as 1; without the line, the first, as in the original).
"""

import re
from typing import NamedTuple

PLAN_ROWS, PLAN_COLUMNS = 16, 8
ROWS, COLUMNS = PLAN_ROWS, PLAN_COLUMNS + 2   # with the two columns outside the plan
CELL = 16
MIDDLE_ROW = 8
ROOM_COUNT, DOOR_COUNT = 6, 7
WALL, DOORWAY, MIDDLE = "#", "+", "@"
# the doors, by the rooms they join: up the right column, up the left, then across the bottom, middle, top
DOORS = [(0, 2), (1, 3), (2, 4), (3, 5), (0, 1), (2, 3), (4, 5)]
EDGE = 0x80                  # door_ids: $80 + room for the floor's outer edge...
NO_WAY = 0xFF                # ...and $FF for wall
WAY_LEFT, WAY_RIGHT, WAY_UP, WAY_DOWN = range(4)   # door_ids' order, per room
GAME_TABLES = ("locked_doors", "stairs_here", "stairs_go_up")
STAIRS_EDGE = [3, 3, 1, 0, 2, 2]          # by room: 0 left, 1 right, 2 top, 3 bottom (on every floor)
OUTER_EDGE = {0: WAY_DOWN, 1: WAY_DOWN, 2: WAY_RIGHT, 3: WAY_LEFT, 4: WAY_UP, 5: WAY_UP}   # out at the edge
STAIRS_Y = [0x80, 0x80, 0xEE, 0x03]       # by edge: the line the stairs are drawn at
FLOOR_LEFT, FLOOR_RIGHT = 0x04, 0x94
STAIRS_BOTTOM_Y, STAIRS_TOP_Y = 0x00, 0xF4   # the stairs' waypoints, beyond the floor's ends
STAIRS_PICTURE_LEFT = 5      # the stairs' picture starts this far left of the stairs' waypoint...
STAIRS_RIGHT_X = 0x8B        # ...but at the right edge, here
WAYPOINT_COUNT = ROOM_COUNT + DOOR_COUNT + ROOM_COUNT
INSIDE = 4                   # a waypoint is this far into its cell (the original's)
BOUND_INSIDE = 7             # a room's limit: this far into the wall row above or below it


class Floor(NamedTuple):
    name: str
    cells: list[str]                    # ROWS strings of COLUMNS cells, the bottom row first
    stairs: dict[int, bool]             # room -> True if its stairs go up
    locked: set[int]                    # door numbers, games 3-8
    game9_stairs: dict[int, bool]
    game9_locked: set[int]


class MansionError(ValueError):
    """The text doesn't make a mansion the engine can use: what's wrong, and where."""


# --- reading the text ----------------------------------------------------------------------------------
FRONT_DOOR_LINE = "front door on floor "


def text_lines(text: str) -> list[str]:
    lines = [line.rstrip() for line in text.splitlines()]
    return [line for line in lines if line.strip() and not line.lstrip().startswith(";")]


def front_door_floor(text: str) -> int:
    """The floor (0 the first) with the front door, where a new game starts."""
    for line in text_lines(text):
        if line.startswith(FRONT_DOOR_LINE):
            return int(line[len(FRONT_DOOR_LINE):]) - 1
    return 0


def parse(text: str) -> list[Floor]:
    floors: list[Floor] = []
    lines = [line for line in text_lines(text) if not line.startswith(FRONT_DOOR_LINE)]
    index = 0
    while index < len(lines):
        if not lines[index].startswith("floor "):
            raise MansionError(f"expected 'floor NAME', found {lines[index]!r}")
        header, cells = lines[index:index + 5], lines[index + 5:index + 5 + ROWS]
        floors.append(parse_floor(header, cells))
        index += 5 + ROWS
    return floors


def parse_floor(header: list[str], rows: list[str]) -> Floor:
    name = header[0][len("floor "):].strip()
    if len(rows) != ROWS or any(len(row) != COLUMNS for row in rows):
        raise MansionError(f"{name}: needs {ROWS} rows of {COLUMNS} cells")
    return Floor(name, list(reversed(rows)), stairs_list(field(header[1], "stairs")),
                 doors_list(field(header[2], "locked")), stairs_list(field(header[3], "game 9 stairs")),
                 doors_list(field(header[4], "game 9 locked")))


def field(line: str, label: str) -> str:
    if not line.startswith(label):
        raise MansionError(f"expected {label!r}, found {line!r}")
    return line[len(label):].strip()


def stairs_list(text: str) -> dict[int, bool]:
    stairs = {}
    for room, way in re.findall(r"(\d)\s+(up|down)", text):
        stairs[int(room)] = way == "up"
    return stairs


def doors_list(text: str) -> set[int]:
    doors = set()
    for first, second in re.findall(r"(\d)-(\d)", text):
        pair = (min(int(first), int(second)), max(int(first), int(second)))
        if pair not in DOORS:
            raise MansionError(f"no door joins rooms {first} and {second}")
        doors.add(DOORS.index(pair))
    return doors


# --- what a floor's plan says ---------------------------------------------------------------------------
class Plan:
    """One floor's cells, read: the rooms' cells, the wall rows and middle wall, the doors and middles."""

    def __init__(self, floor: Floor):
        self.floor = floor
        self.cells = floor.cells
        self.rooms: dict[int, set[tuple[int, int]]] = {room: set() for room in range(ROOM_COUNT)}
        self.middles: dict[int, tuple[int, int]] = {}
        self.read_rooms()
        self.lower_wall_row = max(row for room in (0, 1) for _column, row in self.rooms[room]) + 1
        self.upper_wall_row = max(row for room in (2, 3) for _column, row in self.rooms[room]) + 1
        left_columns = [column for room in (1, 3, 5) for column, _row in self.rooms[room] if column > 0]
        self.middle_wall = max(left_columns) + 1          # its first column, in the 10 (with the outside)
        self.doorways = self.read_doorways()

    def read_rooms(self) -> None:
        for row in range(ROWS):
            for column in range(COLUMNS):
                cell = self.cells[row][column]
                if cell.isdigit():
                    self.rooms[int(cell)].add((column, row))
        for row in range(ROWS):
            for column in range(COLUMNS):
                if self.cells[row][column] == MIDDLE:
                    room = self.neighbouring_room(column, row)
                    self.rooms[room].add((column, row))
                    self.middles[room] = (column, row)

    def neighbouring_room(self, column: int, row: int) -> int:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            cell = self.cell(column + dx, row + dy)
            if cell.isdigit():
                return int(cell)
        raise MansionError(f"{self.floor.name}: the middle at column {column}, row {row} is in no room")

    def cell(self, column: int, row: int) -> str:
        if 0 <= column < COLUMNS and 0 <= row < ROWS:
            return self.cells[row][column]
        return WALL

    def read_doorways(self) -> dict[int, tuple[int, int]]:
        """Door number -> its first doorway cell."""
        doorways: dict[int, tuple[int, int]] = {}
        for row in range(ROWS):
            for column in range(COLUMNS):
                if self.cells[row][column] == DOORWAY:
                    door = self.door_at(column, row)
                    doorways.setdefault(door, (column, row))
        return doorways

    def door_at(self, column: int, row: int) -> int:
        right = column >= self.middle_wall + 2
        if row == self.lower_wall_row:
            return 0 if right else 1
        if row == self.upper_wall_row:
            return 2 if right else 3
        if column in (self.middle_wall, self.middle_wall + 1):
            return 4 if row < self.lower_wall_row else 5 if row < self.upper_wall_row else 6
        raise MansionError(f"{self.floor.name}: the doorway at column {column}, row {row} joins no rooms")

    # the numbers, as the original's are worked out from its plan
    def middle_x(self) -> int:
        """The x where the two columns of rooms meet: the middle of the middle wall."""
        return CELL * (self.middle_wall + 1)

    def cell_x(self, column: int) -> int:
        return CELL * column + INSIDE        # (the plan's column c is the 10's c + 1, at x = 16 (c + 1))

    def cell_y(self, row: int) -> int:
        return CELL * row + INSIDE

    def edge_column(self, room: int) -> int:
        """A bottom or top room's one cell at the floor's end, where its stairs are."""
        end_row = 0 if room < 2 else ROWS - 1
        columns = [column for column, row in self.rooms[room] if row == end_row]
        if len(columns) != 1:
            raise MansionError(f"{self.floor.name}: room {room} needs one cell at the floor's end")
        return columns[0]


# --- the tables -----------------------------------------------------------------------------------------
def wall_rows(plan: Plan) -> bytes:
    rows = bytearray(PLAN_ROWS)
    for row in range(PLAN_ROWS):
        for column in range(PLAN_COLUMNS):
            if plan.cells[row][column + 1] == WALL:
                rows[row] |= 1 << column
    return bytes(rows)


def door_ids(plan: Plan) -> bytes:
    """Per room, the way out left, right, up and down: a door, the outer edge, or wall."""
    ways = bytearray([NO_WAY] * ROOM_COUNT * 4)
    for room, edge in OUTER_EDGE.items():
        ways[room * 4 + edge] = EDGE + room
    for door in plan.doorways:
        lower, higher = DOORS[door]
        if door >= 4:             # across: the higher room is on the left
            ways[lower * 4 + WAY_LEFT], ways[higher * 4 + WAY_RIGHT] = door, door
        else:
            ways[lower * 4 + WAY_UP], ways[higher * 4 + WAY_DOWN] = door, door
    return bytes(ways)


def doorway_lines(plan: Plan) -> bytes:
    """Where each crossing's doorway starts and ends: up from the bottom row, up from the middle, down into
    the bottom, down into the middle (y); left, right (x)."""
    lower, upper, middle = CELL * plan.lower_wall_row, CELL * plan.upper_wall_row, plan.middle_x()
    return bytes([lower + 4, lower + 12, upper + 4, upper + 12, lower + 8, lower - 1, upper + 8, upper - 1,
                  middle - 1, middle - 9, middle - 8, middle])


def room_bounds(plan: Plan, door_bytes: bytes) -> bytes:
    """The y limit through the doors below and above the middle rooms; then two bytes only read for a side
    door, which only need not to be 0 (the original's are the middle's x - 1 and the next table's first)."""
    return bytes([CELL * plan.lower_wall_row + BOUND_INSIDE, CELL * plan.upper_wall_row + BOUND_INSIDE,
                  plan.middle_x() - 1, door_bytes[0]])


def waypoints(plan: Plan) -> tuple[bytes, bytes]:
    """The six rooms' middles, the seven doors (a missing one's is still there, never used), the six
    stairs."""
    points = [(plan.cell_x(column), plan.cell_y(row)) for column, row in
              (plan.middles[room] for room in range(ROOM_COUNT))]
    for door in range(DOOR_COUNT):
        points.append(door_point(plan, door, points))
    for room in range(ROOM_COUNT):
        points.append(stairs_point(plan, room, points))
    return bytes(point[0] for point in points), bytes(point[1] for point in points)


def door_point(plan: Plan, door: int, middles: list[tuple[int, int]]) -> tuple[int, int]:
    lower, higher = DOORS[door]
    if door >= 4:                 # across: the middle wall's middle, at the rooms' middle's height
        return plan.middle_x() - INSIDE, middles[lower][1]
    wall_row = plan.lower_wall_row if door < 2 else plan.upper_wall_row
    column = plan.doorways[door][0] if door in plan.doorways else plan.middles[lower][0]
    return plan.cell_x(column), plan.cell_y(wall_row)


def stairs_point(plan: Plan, room: int, middles: list[tuple[int, int]]) -> tuple[int, int]:
    if room == 2:
        return FLOOR_RIGHT, middles[room][1]
    if room == 3:
        return FLOOR_LEFT, middles[room][1]
    x = plan.cell_x(plan.edge_column(room))
    return x, STAIRS_BOTTOM_Y if room < 2 else STAIRS_TOP_Y


def stairs_x(waypoint_x: bytes) -> bytes:
    """Per room, where the stairs' picture starts across."""
    places = []
    for room in range(ROOM_COUNT):
        point = waypoint_x[ROOM_COUNT + DOOR_COUNT + room]
        if room == 2:
            places.append(STAIRS_RIGHT_X)
        else:
            places.append(FLOOR_LEFT if room == 3 else point - STAIRS_PICTURE_LEFT)
    return bytes(places)


def floor_tables(floor: Floor) -> dict[str, bytes]:
    """The per-floor tables, as tools/extract.py names them."""
    plan = Plan(floor)
    doors = door_ids(plan)
    across, upward = waypoints(plan)
    return {"mansion_walls": wall_rows(plan), "door_ids": doors, "stairs_edge": bytes(STAIRS_EDGE),
            "stairs_x": stairs_x(across), "stairs_y": bytes(STAIRS_Y),
            "room_bounds": room_bounds(plan, doors), "doorway_lines": doorway_lines(plan),
            "waypoint_x": across, "waypoint_y": upward}


def bits(numbers: set[int] | dict[int, bool]) -> int:
    return sum(1 << number for number in numbers)


def game_tables(floors: list[Floor]) -> dict[str, bytes]:
    """The tables by floor and game: the locks and stairs, games 1-8 then game 9."""
    locked = [bits(floor.locked) for floor in floors] + [bits(floor.game9_locked) for floor in floors]
    here = [bits(floor.stairs) for floor in floors] + [bits(floor.game9_stairs) for floor in floors]
    going_up = [bits({room for room, upward in floor.stairs.items() if upward}) for floor in floors]
    going_up += [bits({room for room, upward in floor.game9_stairs.items() if upward}) for floor in floors]
    return {"locked_doors": bytes(locked), "stairs_here": bytes(here), "stairs_go_up": bytes(going_up)}
