"""The ROM builds, boots in the emulator, and its frame counter runs.

Usage: python tests/test_boot.py      (exit code 1 on failure)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
from build import ambient_wanted, build, shareable_wanted  # noqa: E402
from nes import Nes  # noqa: E402

READY = 0x42
FRAME_COUNT, READY_FLAG = 0x00, 0x01   # zero page addresses (build/haunted_house.labels)
FRAMES = 60


def main() -> None:
    nes = Nes(build(shareable=shareable_wanted(sys.argv), ambient=ambient_wanted(sys.argv)))
    nes.run(10)
    counted_before = int(nes.ram[FRAME_COUNT])
    nes.run(FRAMES)
    counted = (int(nes.ram[FRAME_COUNT]) - counted_before) % 256
    ok = nes.ram[READY_FLAG] == READY and counted == FRAMES
    print(f"ready ${nes.ram[READY_FLAG]:02X}, {counted} frames counted in {FRAMES}: {'OK' if ok else 'FAIL'}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
