"""The shareable build's pack, for the remaster's look to draw our floors with: build/shareable/pack. Its
world is our own text art (mansion/art.py), written out as PNGs; its cast is the remaster's classic pack's
(the NES look's own, all original art).

Usage: python tools/mansion_pack.py      (tools/make_art.py --shareable runs it)
"""

import json
import os
import shutil
import sys

from PIL import Image

import extract as E
import mansion as M

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "mansion"))
import art  # noqa: E402

CLASSIC = os.path.join(E.REMASTER, "packs", "classic")
OUTPUT = os.path.join(ROOT, "build", "shareable", "pack")
MANSION_TEXT = os.path.join(ROOT, "mansion", "floors.txt")


def floor_names() -> list[str]:
    with open(MANSION_TEXT) as mansion_file:
        return [floor.name.title() for floor in M.parse(mansion_file.read())]


def main() -> None:
    shutil.rmtree(OUTPUT, ignore_errors=True)
    world = os.path.join(OUTPUT, "world")
    os.makedirs(world)
    shutil.copytree(os.path.join(CLASSIC, "cast"), os.path.join(OUTPUT, "cast"))
    for name, picture in art.world_pictures().items():
        Image.fromarray(picture, "RGBA").save(os.path.join(world, f"{name}.png"))
    with open(os.path.join(CLASSIC, "pack.json")) as about:
        info = json.load(about)
    info["title"], info["floors"] = "Haunted House: By Matchlight", floor_names()
    info["description"] = "Our own mansion, a cellar and four floors (mansion/art.py), with the classic cast."
    with open(os.path.join(OUTPUT, "pack.json"), "w") as about:
        json.dump(info, about, indent=2)
    print(OUTPUT)


if __name__ == "__main__":
    main()
