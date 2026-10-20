"""The hints say what the remaster's say (its game/hints.py), in random scenes: the player, the urn's pieces
and what's held put in place, then B pressed; the hint's parts are read from the NES's RAM and its words
from the ROM, and compared with the remaster's lines for the same state. The two notes too: what's held
changed between two frames, and the note (or none) compared with the remaster's. (A hint comes when B is let
go, so the state compared is the frame after.)

The scenes are set up by writing the game's RAM, as the remaster's research lab does - only to test.

Needs the remaster beside this repository (../haunted-house) with your ROM in it.

With --shareable, the shareable build, against the remaster's hints on our own mansion.

Usage: python tests/test_hints.py [--shareable] [scenes] [seed]      (exit code 1 on any difference)
"""

import os
import random
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REMASTER = os.path.join(os.path.dirname(ROOT), "haunted-house")
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, REMASTER)
from build import build, labels_for, shareable_wanted  # noqa: E402
import shareable  # noqa: E402
from nes import BUTTON_A, BUTTON_B, BUTTON_START, Nes  # noqa: E402

from game import hints  # noqa: E402
from game import rom as R  # noqa: E402
from game.state import Game, GameState  # noqa: E402

FONT = os.path.join(ROOT, "build", "faithful", "art", "font.inc")
HEADER, BANK = 16, 0x2000
EXTRAS_BANK = 2
STATE_START = 0x80
FLOOR, CARRIED, URN_SHAPES, LIVES = 0x8D, 0x9A, 0x9D, 0x96
ITEM_FLOOR, ITEM_X, ITEM_Y = 0xA0, 0xAB, 0xB6
PLAYER_X, PLAYER_Y, ROOM, FLAGS = 0xAA, 0xB5, 0x9C, 0x8A
MATCH_LIT = 0x40
NOTHING, JOINED, WHOLE = 0xFF, 0xFF, 8
HINT_TIME = 180
LINES, PARTS, STRING_END = 3, 4, 0xFF
SETTLE_FRAMES = 20          # a new floor is drawn before the hint can show
PAIRS = {5: (2, 3), 6: (2, 4), 7: (3, 4)}   # a two-piece shape: the pieces in it


def labels(rom_path: str) -> dict[str, int]:
    found = {}
    with open(labels_for(rom_path)) as label_file:
        for line in label_file:
            _kind, address, name = line.split()
            found[name.lstrip(".")] = int(address, 16)
    return found


def font_letters() -> dict[int, str]:
    """Tile number -> letter, from the font's charmap."""
    letters = {}
    with open(FONT) as font_file:
        for match in re.finditer(r"\.charmap \$([0-9A-F]+), (\d+)", font_file.read()):
            letters[int(match.group(2))] = chr(int(match.group(1), 16))
    return letters


class HintReader:
    """The NES's hint, as words: its parts' addresses from RAM, their letters from the ROM's extras bank."""

    def __init__(self, nes: Nes, rom_path: str):
        self.nes = nes
        self.at = labels(rom_path)
        with open(rom_path, "rb") as rom_file:
            start = HEADER + EXTRAS_BANK * BANK
            self.extras = rom_file.read()[start:start + BANK]
        self.letters = font_letters()

    def byte(self, name: str, offset: int = 0) -> int:
        return int(self.nes.ram[self.at[name] + offset])

    def text(self, address: int) -> str:
        words = []
        place = address - 0x8000
        while self.extras[place] != STRING_END:
            words.append(self.letters[self.extras[place]])
            place += 1
        return "".join(words)

    def lines(self) -> list[str]:
        found = []
        for line in range(LINES):
            parts = []
            for part in range(PARTS):
                place = (line * PARTS + part) * 2
                high = self.byte("hint_parts", place + 1)
                if high:
                    parts.append(self.text(high << 8 | self.byte("hint_parts", place)))
            if parts:
                found.append("".join(parts))
        return found

    def just_shown(self) -> bool:
        return self.byte("hint_timer") == HINT_TIME and self.byte("hint_in_extras") == 1


def expected_hint(state: GameState, rom: bytes) -> list[str]:
    """The remaster's hint, with the NES's button for a match."""
    return [line.replace("SPACE", "A") for line in hints.hint(state, rom)]


def random_urn(chance: random.Random) -> list[int]:
    """Shapes for items 2-4: three pieces, a pair and a piece, or the whole urn."""
    kind = chance.choice(["pieces", "pair", "whole"])
    if kind == "pieces":
        return [2, 3, 4]
    if kind == "whole":
        holder = chance.randrange(3)
        return [WHOLE if index == holder else JOINED for index in range(3)]
    shape, (first, second) = chance.choice(list(PAIRS.items()))
    keeper = chance.choice((first, second))
    shapes = {first: JOINED, second: JOINED, keeper: shape}
    alone = ({2, 3, 4} - {first, second}).pop()
    shapes[alone] = alone
    return [shapes[2], shapes[3], shapes[4]]


def held_choice(chance: random.Random, shapes: list[int]) -> int:
    choices = [NOTHING, 0, 1] + [2 + index for index, shape in enumerate(shapes) if shape != JOINED]
    return chance.choice(choices)


def place_scene(nes: Nes, chance: random.Random, floors: int) -> None:
    ram = nes.ram
    shapes = random_urn(chance)
    for index, shape in enumerate(shapes):
        ram[URN_SHAPES + index] = shape
    for item in range(5):
        ram[ITEM_FLOOR + item] = chance.randrange(floors)
        ram[ITEM_X + item] = chance.randrange(4, 149)
        ram[ITEM_Y + item] = chance.randrange(1, 252)
    ram[CARRIED] = held_choice(chance, shapes)
    ram[PLAYER_X] = chance.randrange(4, 149)
    ram[PLAYER_Y] = chance.randrange(1, 252)
    ram[ROOM] = chance.randrange(6)
    lit = MATCH_LIT if chance.random() < 0.5 else 0
    ram[FLAGS] = (int(ram[FLAGS]) & (0xFF ^ MATCH_LIT)) | lit
    ram[LIVES] = 9


def check_hints(nes: Nes, reader: HintReader, game: Game, scenes: int, chance: random.Random) -> int:
    differences = 0
    compared = 0
    for _scene in range(scenes):
        floors = R.floor_count(game.rom)
        nes.ram[FLOOR] = chance.randrange(floors)
        nes.run(SETTLE_FRAMES)
        place_scene(nes, chance, floors)
        nes.run(1, {BUTTON_B})
        nes.run(1)                # the hint comes when B is let go
        state = game.state(nes.ram[STATE_START:STATE_START + 128])
        if state.mode != "playing" or not reader.just_shown():
            continue
        compared += 1
        wanted, shown = expected_hint(state, game.rom), reader.lines()
        if wanted != shown:
            differences += 1
            print(f"hint differs: wanted {wanted}, shown {shown}")
    print(f"hints: {compared} compared, {differences} different")
    return differences


def check_notes(nes: Nes, reader: HintReader, game: Game, scenes: int, chance: random.Random) -> int:
    differences = 0
    for _scene in range(scenes):
        place_scene(nes, chance, R.floor_count(game.rom))
        nes.run(1)
        before = game.state(nes.ram[STATE_START:STATE_START + 128])
        nes.ram[reader.at["hint_timer"]] = 0
        shapes = [int(nes.ram[URN_SHAPES + index]) for index in range(3)]
        if chance.random() < 0.5:
            shapes = random_urn(chance)
        for index, shape in enumerate(shapes):
            nes.ram[URN_SHAPES + index] = shape
        nes.ram[CARRIED] = held_choice(chance, shapes)
        nes.run(1)
        after = game.state(nes.ram[STATE_START:STATE_START + 128])
        if before.mode != "playing" or after.mode != "playing":
            continue
        wanted = hints.swap_note(before, after)
        if wanted is None and hints.urn_just_whole(before, after):
            wanted = hints.WHOLE_URN_NOTE
        shown = reader.lines() if reader.just_shown() else None
        if wanted != shown:
            differences += 1
            print(f"note differs: wanted {wanted}, shown {shown}")
    print(f"notes: {scenes} scenes, {differences} different")
    return differences


def main() -> None:
    our_mansion = shareable_wanted(sys.argv)
    scenes = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    chance = random.Random(seed)
    rom_path = build(shareable=our_mansion)
    nes = Nes(rom_path)
    nes.run(5)
    nes.run(2, {BUTTON_B})        # past the story
    nes.run(30)
    nes.run(5, {BUTTON_START})    # a game
    nes.run(30)
    nes.run(1, {BUTTON_A})
    reader = HintReader(nes, rom_path)
    game = Game()
    if our_mansion:
        game.rom = shareable.floors_rom()
    differences = check_hints(nes, reader, game, scenes, chance)
    differences += check_notes(nes, reader, game, scenes, chance)
    sys.exit(1 if differences else 0)


if __name__ == "__main__":
    main()
