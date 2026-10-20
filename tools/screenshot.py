"""Play the ROM in the emulator for a while and save what's on screen - to look at the picture.

Usage: python tools/screenshot.py NAME [steps...]
  a step is FRAMES or FRAMES:BUTTONS, buttons from: up down left right a b start select
  e.g.   python tools/screenshot.py start 60 10:start 30 40:a 120:left
Saves shots/NAME.png (at 3x), and prints a few of the game's bytes.
"""

import os
import sys

import numpy as np
from PIL import Image

from build import build, shareable_wanted
import nes as N

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "shots")
SCALE = 3
BUTTONS = {"up": N.BUTTON_UP, "down": N.BUTTON_DOWN, "left": N.BUTTON_LEFT, "right": N.BUTTON_RIGHT,
           "a": N.BUTTON_A, "b": N.BUTTON_B, "start": N.BUTTON_START, "select": N.BUTTON_SELECT}


def play(machine: N.Nes, steps: list[str]) -> None:
    for step in steps:
        frames, _, buttons = step.partition(":")
        held = {BUTTONS[name] for name in buttons.split("+") if name}
        machine.run(int(frames), held)


def main() -> None:
    shareable = shareable_wanted(sys.argv)
    name, steps = sys.argv[1], sys.argv[2:]
    machine = N.Nes(build(shareable=shareable))
    play(machine, steps)
    if machine.picture is None:
        sys.exit("no picture yet")
    os.makedirs(SHOTS, exist_ok=True)
    picture = Image.fromarray(np.ascontiguousarray(machine.picture))
    picture.resize((picture.width * SCALE, picture.height * SCALE), Image.Resampling.NEAREST).save(
        os.path.join(SHOTS, f"{name}.png"))
    ram = machine.ram
    print(f"state ${ram[0x99]:02X} game {ram[0xCC] + 1} floor {ram[0x8D] + 1} room {ram[0x9C]} "
          f"x ${ram[0xAA]:02X} y ${ram[0xB5]:02X} flags ${ram[0x8A]:02X}")


if __name__ == "__main__":
    main()
