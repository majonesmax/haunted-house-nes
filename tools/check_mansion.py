"""Checks a mansion drawn as text (tools/mansion.py) can be played on the engine as the original is:

- each floor's plan is the shape the engine assumes: the outside wall except at the middle row's ends, the
  rooms' rows split by two wall rows, the columns by a wall two cells thick, each room in its place with
  one middle, its cells joined, and the bottom and top rooms with one cell at the floor's end;
- every doorway joins its two rooms, and is wide enough;
- monsters, who never test walls, stay out of them: every walk between waypoints (a room's middle and its
  doors, a door and the next room's middle, the middle and the stairs, and from the stairs on the floor
  they lead to) keeps a monster's whole picture clear of the walls;
- stairs lead somewhere: up on one floor is down on the next, from the same room and the same cell at the
  edge, and none go off the top or bottom of the house, in games 1-8 and in game 9;
- the player starts on open floor in room 2 of the first floor, beside the front door, and every room of
  every floor can be reached from there without the master key, in games 3-8 and in game 9 (the locks
  only make you go round by the stairs: the original's rule);
- the master key, where game 3 puts it, is on open floor in room 2.

Usage: python tools/check_mansion.py [mansion/floors.txt]      (exit code 1 if anything's wrong)
"""

import os
import sys

import mansion as M

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_MANSION = os.path.join(ROOT, "mansion", "floors.txt")
MONSTER_WIDTH, MONSTER_HEIGHT = 8, 10       # a monster's picture, from its x and y
START = (0x80, 0x86)                        # where a new game puts the player (the spec's)
GAME_3_KEY = (0x74, 0x84)                   # ...and game 3 the master key, on the first floor
START_ROOM = 2
PLAYER_WIDTH, PLAYER_HEIGHT = 8, 3
Point = tuple[int, int]


def wall_at(walls: bytes, x: int, y: int) -> bool:
    """The game's wall test (the spec's, "The mansion")."""
    column = ((x >> 4) - 1) & 0xFF
    row = (y >> 4) & 0x0F
    if column & 8:
        return row != M.MIDDLE_ROW
    return bool(walls[row] >> column & 1)


def box_hits_wall(walls: bytes, x: int, y: int, width: int, height: int) -> bool:
    return any(wall_at(walls, min(x + dx, 255), min(y + dy, 255))
               for dx in range(width) for dy in range(height))


def walk(start: Point, end: Point) -> list[Point]:
    """A monster's steps: a unit in x and in y at once, towards the end."""
    x, y = start
    steps = [(x, y)]
    while (x, y) != end:
        x += (end[0] > x) - (end[0] < x)
        y += (end[1] > y) - (end[1] < y)
        steps.append((x, y))
    return steps


class Checker:
    def __init__(self, floors: list[M.Floor]):
        self.floors = floors
        self.problems: list[str] = []
        self.plans: dict[int, M.Plan] = {}
        self.tables: dict[int, dict[str, bytes]] = {}

    def problem(self, floor: int, text: str) -> None:
        self.problems.append(f"floor {floor + 1} ({self.floors[floor].name}): {text}")

    def run(self) -> list[str]:
        for number, floor in enumerate(self.floors):
            try:
                plan = M.Plan(floor)
                tables = M.floor_tables(floor)
            except (M.MansionError, ValueError, KeyError) as error:
                self.problem(number, str(error))
                continue
            self.plans[number] = plan
            self.tables[number] = tables
            self.check_shape(number, plan)
            self.check_doorways(number, plan)
            self.check_walks(number, tables)
        if len(self.plans) == len(self.floors):   # (every floor could be read)
            self.check_stairs()
            self.check_start()
            self.check_reach()
        return self.problems

    # --- the plan's shape ------------------------------------------------------------------------------
    def check_shape(self, number: int, plan: M.Plan) -> None:
        self.check_outside(number, plan)
        self.check_walls_between(number, plan)
        for room in range(M.ROOM_COUNT):
            self.check_room(number, plan, room)

    def check_outside(self, number: int, plan: M.Plan) -> None:
        for row in range(M.ROWS):
            for column in (0, M.COLUMNS - 1):
                cell = plan.cells[row][column]
                wanted = (str(3) if column == 0 else str(2)) if row == M.MIDDLE_ROW else M.WALL
                if cell != wanted:
                    self.problem(number, f"row {row}, outside column {column}: {cell!r}, not {wanted!r}")

    def check_walls_between(self, number: int, plan: M.Plan) -> None:
        """The two wall rows between the rows of rooms, and the middle wall between the columns."""
        lower, upper = plan.lower_wall_row, plan.upper_wall_row
        if not lower < M.MIDDLE_ROW < upper:
            self.problem(number, f"the wall rows ({lower}, {upper}) must be either side of row 8")
        for row in (lower, upper):
            if any(cell not in (M.WALL, M.DOORWAY) for cell in plan.cells[row]):
                self.problem(number, f"row {row} splits the rooms, so it holds only walls and doorways")
        for row in range(M.ROWS):
            for column in (plan.middle_wall, plan.middle_wall + 1):
                if plan.cells[row][column] not in (M.WALL, M.DOORWAY):
                    self.problem(number, f"the middle wall (columns {plan.middle_wall}-"
                                 f"{plan.middle_wall + 1}) has a room's cell in row {row}")

    def check_room(self, number: int, plan: M.Plan, room: int) -> None:
        cells = plan.rooms[room]
        if room not in plan.middles:
            self.problem(number, f"room {room} has no middle (@)")
            return
        rows = {0: range(0, plan.lower_wall_row), 1: range(0, plan.lower_wall_row),
                2: range(plan.lower_wall_row + 1, plan.upper_wall_row),
                3: range(plan.lower_wall_row + 1, plan.upper_wall_row),
                4: range(plan.upper_wall_row + 1, M.ROWS), 5: range(plan.upper_wall_row + 1, M.ROWS)}[room]
        right = room % 2 == 0
        for column, row in cells:
            if row not in rows or (column > plan.middle_wall) != right:
                self.problem(number, f"room {room} has a cell out of its place: column {column}, row {row}")
                return
        joined = flood(cells, plan.middles[room])
        if joined != cells:
            self.problem(number, f"room {room}'s cells aren't all joined")
        if room in (0, 1, 4, 5):
            end_row = 0 if room < 2 else M.ROWS - 1
            ends = [column for column, row in cells if row == end_row]
            if len(ends) != 1:
                self.problem(number, f"room {room} needs one cell at the floor's end, has {len(ends)}")

    def check_doorways(self, number: int, plan: M.Plan) -> None:
        for door, cells in self.doorway_cells(number, plan).items():
            self.check_doorway(number, plan, door, cells)

    def doorway_cells(self, number: int, plan: M.Plan) -> dict[int, list[tuple[int, int]]]:
        """Door number -> its doorway's cells."""
        cells_by_door: dict[int, list[tuple[int, int]]] = {}
        for row in range(M.ROWS):
            for column in range(M.COLUMNS):
                if plan.cells[row][column] != M.DOORWAY:
                    continue
                try:
                    door = plan.door_at(column, row)
                except M.MansionError as error:
                    self.problem(number, str(error))
                    continue
                cells_by_door.setdefault(door, []).append((column, row))
        return cells_by_door

    def check_doorway(self, number: int, plan: M.Plan, door: int, cells: list[tuple[int, int]]) -> None:
        lower, higher = M.DOORS[door]
        if door >= 4:
            row = cells[0][1]
            both = [(plan.middle_wall, row), (plan.middle_wall + 1, row)]
            sides = [(plan.middle_wall - 1, row, higher), (plan.middle_wall + 2, row, lower)]
            if sorted(cells) != both:
                self.problem(number, f"door {lower}-{higher} must be both cells of the middle wall, once")
        else:
            if len(cells) != 1:
                self.problem(number, f"door {lower}-{higher} must be one cell")
            column, row = cells[0]
            sides = [(column, row - 1, lower), (column, row + 1, higher)]
        for column, row, room in sides:
            if (column, row) not in plan.rooms[room]:
                self.problem(number, f"door {lower}-{higher} doesn't open into room {room}")

    # --- monsters --------------------------------------------------------------------------------------
    def walks(self, number: int, tables: dict[str, bytes]) -> list[tuple[str, Point, Point, bytes]]:
        """Every walk a monster can take from this floor: (what, from, to, the walls it's among)."""
        points = list(zip(tables["waypoint_x"], tables["waypoint_y"]))
        walls = tables["mansion_walls"]
        found = []
        for door in self.plans[number].doorways:
            lower, higher = M.DOORS[door]
            at_door = points[M.ROOM_COUNT + door]
            for room, other in ((lower, higher), (higher, lower)):
                found.append((f"room {room} to door {lower}-{higher}", points[room], at_door, walls))
                found.append((f"door {lower}-{higher} into room {other}", at_door, points[other], walls))
        for room in range(M.ROOM_COUNT):
            if self.has_stairs(number, room):
                at_stairs = points[M.ROOM_COUNT + M.DOOR_COUNT + room]
                found.append((f"room {room} to its stairs", points[room], at_stairs, walls))
        return found

    def has_stairs(self, number: int, room: int) -> bool:
        floor = self.floors[number]
        return room in floor.stairs or room in floor.game9_stairs

    def check_walks(self, number: int, tables: dict[str, bytes]) -> None:
        for what, start, end, walls in self.walks(number, tables):
            for x, y in walk(start, end):
                if box_hits_wall(walls, x, y, MONSTER_WIDTH, MONSTER_HEIGHT):
                    self.problem(number, f"a monster walking {what} goes into a wall at x {x}, y {y}")
                    break

    def check_arrivals(self, number: int, room: int, other: int) -> None:
        """A monster up or down the stairs walks from the same spot to the room's middle on the other
        floor."""
        here, there = self.tables[number], self.tables[other]
        at_stairs = (here["waypoint_x"][M.ROOM_COUNT + M.DOOR_COUNT + room],
                     here["waypoint_y"][M.ROOM_COUNT + M.DOOR_COUNT + room])
        middle = (there["waypoint_x"][room], there["waypoint_y"][room])
        for x, y in walk(at_stairs, middle):
            if box_hits_wall(there["mansion_walls"], x, y, MONSTER_WIDTH, MONSTER_HEIGHT):
                self.problem(other, f"a monster coming off the stairs into room {room} goes into a wall "
                             f"at x {x}, y {y}")
                return

    # --- stairs, the start, reaching everywhere --------------------------------------------------------
    def check_stairs(self) -> None:
        for game9 in (False, True):
            for number, floor in enumerate(self.floors):
                stairs = floor.game9_stairs if game9 else floor.stairs
                for room, upward in stairs.items():
                    self.check_one_stairs(number, room, upward, game9)

    def check_one_stairs(self, number: int, room: int, upward: bool, game9: bool) -> None:
        games = "game 9" if game9 else "games 1-8"
        other = number + 1 if upward else number - 1
        if not 0 <= other < len(self.floors):
            way = "up" if upward else "down"
            self.problem(number, f"room {room}'s stairs go {way} out of the house ({games})")
            return
        theirs = self.floors[other].game9_stairs if game9 else self.floors[other].stairs
        if theirs.get(room) != (not upward):
            self.problem(number, f"room {room}'s stairs ({games}) don't meet stairs the other way on "
                         f"floor {other + 1}")
            return
        at_an_end = room in (0, 1, 4, 5)
        if at_an_end and self.plans[number].edge_column(room) != self.plans[other].edge_column(room):
            self.problem(number, f"room {room}'s stairs aren't at the same cell as floor {other + 1}'s")
        self.check_arrivals(number, room, other)

    def check_start(self) -> None:
        walls = self.tables[0]["mansion_walls"]
        plan = self.plans[0]
        for what, (x, y) in (("the player's start", START), ("game 3's master key", GAME_3_KEY)):
            if box_hits_wall(walls, x, y, PLAYER_WIDTH, PLAYER_HEIGHT):
                self.problem(0, f"{what} (x {x}, y {y}) is in a wall")
            if (x // M.CELL, y // M.CELL) not in plan.rooms[START_ROOM]:
                self.problem(0, f"{what} (x {x}, y {y}) isn't in room {START_ROOM}")

    def check_reach(self) -> None:
        for game9 in (False, True):
            reached = self.reachable(game9)
            games = "game 9" if game9 else "games 3-8"
            for number in range(len(self.floors)):
                for room in range(M.ROOM_COUNT):
                    if (number, room) not in reached:
                        self.problem(number, f"room {room} can't be reached without the key ({games})")

    def reachable(self, game9: bool) -> set[tuple[int, int]]:
        reached = {(0, START_ROOM)}
        waiting = [(0, START_ROOM)]
        while waiting:
            number, room = waiting.pop()
            floor = self.floors[number]
            locked = floor.game9_locked if game9 else floor.locked
            ways = [(number, M.DOORS[door][1] if M.DOORS[door][0] == room else M.DOORS[door][0])
                    for door in self.plans[number].doorways if room in M.DOORS[door] and door not in locked]
            stairs = floor.game9_stairs if game9 else floor.stairs
            if room in stairs:
                ways.append((number + 1 if stairs[room] else number - 1, room))
            for place in ways:
                if place not in reached:
                    reached.add(place)
                    waiting.append(place)
        return reached


def flood(cells: set[tuple[int, int]], start: tuple[int, int]) -> set[tuple[int, int]]:
    joined, waiting = set(), [start]
    while waiting:
        cell = waiting.pop()
        if cell in cells and cell not in joined:
            joined.add(cell)
            column, row = cell
            waiting += [(column + 1, row), (column - 1, row), (column, row + 1), (column, row - 1)]
    return joined


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MANSION
    with open(path) as mansion_file:
        floors = M.parse(mansion_file.read())
    problems = Checker(floors).run()
    for problem in problems:
        print(problem)
    print(f"{len(floors)} floors: {'all good' if not problems else f'{len(problems)} problems'}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
