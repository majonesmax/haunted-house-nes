"""The shareable build's pack, for the remaster's look to draw our six floors with: build/shareable/pack, made
from the remaster's classic pack (the NES look's own, all original art). The cast is the classic one; each
floor borrows the world pictures of the classic floor nearest its feel (STYLES) - the Library the dining
hall's bookshelves, the Attic the attic's cobwebs - until floors of our own are drawn for it.

Usage: python tools/mansion_pack.py      (tools/make_art.py --shareable runs it)
"""

import json
import os
import shutil

import extract as E
import mansion as M

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLASSIC = os.path.join(E.REMASTER, "packs", "classic")
OUTPUT = os.path.join(ROOT, "build", "shareable", "pack")
MANSION_TEXT = os.path.join(ROOT, "mansion", "floors.txt")
# each of our floors (by number) -> the classic floor whose pictures it borrows: 1 the foyer (portraits and
# sconces), 2 the dining hall (portraits, bookshelves), 3 the conservatory (ferns, windows), 4 the attic
STYLES = {1: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 4}
SHARED_WORLD = ("front_door", "title_mansion", "title_moon")
FLOOR_PICTURES = ("floor{n}", "wall{n}_top", "wall{n}_face", "wall{n}_trim")


def floor_names() -> list[str]:
    with open(MANSION_TEXT) as mansion_file:
        return [floor.name.title() for floor in M.parse(mansion_file.read())]


def copy_floor(world: str, ours: int, theirs: int) -> None:
    classic_world = os.path.join(CLASSIC, "world")
    for pattern in FLOOR_PICTURES:
        shutil.copy(os.path.join(classic_world, pattern.format(n=theirs) + ".png"),
                    os.path.join(world, pattern.format(n=ours) + ".png"))
    shutil.copy(os.path.join(classic_world, f"wall{theirs}_top.png"), os.path.join(world, f"wall{ours}.png"))
    for file_name in os.listdir(classic_world):
        if file_name.startswith(f"decor{theirs}_"):
            renamed = f"decor{ours}_" + file_name[len(f"decor{theirs}_"):]
            shutil.copy(os.path.join(classic_world, file_name), os.path.join(world, renamed))


def main() -> None:
    shutil.rmtree(OUTPUT, ignore_errors=True)
    world = os.path.join(OUTPUT, "world")
    os.makedirs(world)
    shutil.copytree(os.path.join(CLASSIC, "cast"), os.path.join(OUTPUT, "cast"))
    for name in SHARED_WORLD:
        shutil.copy(os.path.join(CLASSIC, "world", name + ".png"), world)
    for ours, theirs in STYLES.items():
        copy_floor(world, ours, theirs)
    with open(os.path.join(CLASSIC, "pack.json")) as about:
        info = json.load(about)
    info["title"], info["floors"] = "Haunted House", floor_names()
    info["description"] = "Our own six-floor mansion, in the classic pack's pictures."
    with open(os.path.join(OUTPUT, "pack.json"), "w") as about:
        json.dump(info, about, indent=2)
    print(OUTPUT)


if __name__ == "__main__":
    main()
