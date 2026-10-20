"""tools/check_mansion.py catches what it's meant to: the new mansion passes, and each of a few broken
copies of it - a wall in a monster's way, stairs that meet nothing, a room shut away by locks, a doorway
into a wall, the start in a wall - is reported.

Usage: python tests/test_check_mansion.py      (exit code 1 if the checker misses anything)
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import check_mansion as C  # noqa: E402
import mansion as M  # noqa: E402

# (what's broken, the text as it is, the text broken, what the report must say)
BREAKAGES = [
    ("a wall on a monster's way", "#1@11++@0#\n#1111##00#\n##1####0##",
     "#1@11++@0#\n#1111###0#\n##1####0##", "goes into a wall"),
    ("stairs that meet nothing", "stairs 1 up, 4 up", "stairs 4 up", "don't meet stairs"),
    ("a room shut away", "locked 2-3\ngame 9 stairs 3 down", "locked 2-3, 0-2, 2-4\ngame 9 stairs 3 down",
     "can't be reached"),
    ("a doorway into a wall", "##+####+##\n#1111##00#\n#1@11", "##+####+##\n#1111###0#\n#1@11",
     "doesn't open into room 0"),
    ("the start in a wall", "33@33++@22", "33@33++@#2", "player's start"),
]


def problems_in(text: str) -> list[str]:
    try:
        return C.Checker(M.parse(text), M.front_door_floor(text)).run()
    except M.MansionError as error:
        return [str(error)]


def main() -> None:
    with open(C.DEFAULT_MANSION) as mansion_file:
        text = mansion_file.read()
    missed = 0
    found = problems_in(text)
    print(f"the mansion as it is: {len(found)} problems")
    missed += len(found)
    for what, before, after, wanted in BREAKAGES:
        assert before in text, what
        found = problems_in(text.replace(before, after, 1))
        caught = any(wanted in problem for problem in found)
        print(f"{what}: {'caught' if caught else 'MISSED'}" + (f" - {found[0]}" if found else ""))
        missed += not caught
    sys.exit(1 if missed else 0)


if __name__ == "__main__":
    main()
