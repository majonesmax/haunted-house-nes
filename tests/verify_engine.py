"""Run the faithful NES build beside the remaster's model of the original game, and check the NES keeps the
game's whole state exactly as the model says, every frame.

This is the remaster's own check, tools/verify_player.py, with the NES in place of the 2600: the same bot,
the same scenes, the same comparison of $80-$CC and the other state bytes. It works because the engine
keeps the state at the 2600's addresses. Where the model says the original crashes, the frame isn't
compared (the NES doesn't crash) and the bot presses RESET, as it does for the original. It also fails if
the NES ever took longer than a frame to work a frame out.

Needs the remaster beside this repository (../haunted-house) with your ROM in it, and the FCEUmm core in
cores/.

With --shareable it checks the shareable build the same way: the model runs our own mansion (an R.Floors,
from tools/shareable.py), floor by floor, so the new mansion has the same proof as the original.

Usage: python tests/verify_engine.py [--shareable] [frames per game] [seed]   (exit code 1 on any mismatch)
"""

import os
import sys
from typing import Iterable

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REMASTER = os.path.join(os.path.dirname(ROOT), "haunted-house")
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(REMASTER, "tools"))
sys.path.insert(0, REMASTER)
from build import build, labels_for, shareable_wanted  # noqa: E402
import shareable  # noqa: E402
from nes import BUTTON_A, BUTTON_B, Nes  # noqa: E402
import verify_player as V  # noqa: E402
from lab import BUTTON, RESET  # noqa: E402

from game import rom as R  # noqa: E402

STATE_START, STATE_END = 0x80, 0x100
RESET_HELD, AFTER_RESET = 5, 5


def label_address(rom_path: str, name: str) -> int:
    """Where the linker put a label in this ROM (its .labels file, from tools/build.py)."""
    with open(labels_for(rom_path)) as labels:
        for line in labels:
            _kind, address, label = line.split()
            if label == f".{name}":
                return int(address, 16)
    raise KeyError(name)


class NesLab:
    """The NES, looking to the remaster's check like its 2600 lab: the same joypad ids, the same addresses."""

    def __init__(self, rom: str):
        self.nes = Nes(rom)
        self.nes.run(5)
        self.nes.run(2, {BUTTON_B})   # past the story (any button; B is no 2600 control)
        self.nes.run(5)

    def run(self, frames: int = 1, held: Iterable[int] = ()) -> None:
        on_the_nes = {BUTTON_A if button == BUTTON else button for button in held}
        self.nes.run(frames, on_the_nes)

    def hold(self, *held: int, frames: int = 1) -> None:
        self.run(frames, held)

    def reset(self) -> None:
        self.hold(RESET, frames=RESET_HELD)
        self.run(AFTER_RESET)

    def peek(self, address: int) -> int:
        return int(self.nes.ram[address])

    def poke(self, address: int, value: int) -> None:
        self.nes.ram[address] = value & 0xFF

    def snapshot(self) -> bytes:
        return bytes(self.nes.ram[STATE_START:STATE_END])


def main() -> None:
    our_mansion = shareable_wanted(sys.argv)
    frames = int(sys.argv[1]) if len(sys.argv) > 1 else V.FRAMES_PER_GAME
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    rom_path = build(shareable=our_mansion)
    lab = NesLab(rom_path)
    rom = shareable.floors_rom() if our_mansion else R.load()
    tally = V.Tally()
    for game in V.GAMES:
        V.check_game(lab, rom, game, frames, seed, tally)  # type: ignore[arg-type]
    V.report(tally)
    late = lab.peek(label_address(rom_path, "late_frames"))
    print(f"frames the NES finished late: {late}")
    sys.exit(1 if tally.mismatches or late else 0)


if __name__ == "__main__":
    main()
