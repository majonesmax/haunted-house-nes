"""How long each routine takes, in CPU cycles: one frame of the game's work, run in py65 (a 6502 in
Python) from the RAM the emulator has at some moment - to find what to make faster when a frame runs late.

The NES's chips aren't there: reads of the PPU's status say "vertical blank", every other chip read gives
0, and writes to the chips (and to the cartridge's registers) are ignored.

Usage: python tools/profile.py [steps...]     (steps as tools/screenshot.py takes them)
  e.g.  python tools/profile.py 30 6:start 30 5:a 30 10:left
Prints each routine's cycles, including what it calls, for the game's frame and the picture's.
"""

import os
import sys
from collections import defaultdict

from py65.devices.mpu6502 import MPU

from build import build
import nes as N
from screenshot import play

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LABELS = os.path.join(ROOT, "build", "haunted_house.labels")
HEADER = 16
PRG_START, PRG_SIZE = 0x8000, 0x10000
BANK = 0x2000                # the MMC3's 8K program banks
FIXED_BANKS = 6              # $C000 and $E000 hold the last two
BANK_SELECT, BANK_DATA = 0x8000, 0x8001
PROGRAM_8000, PROGRAM_A000 = 6, 7
PPU_STATUS, VBLANK = 0x2002, 0x80
CHIPS_END = 0x6000           # $2000-$5FFF: the PPU, the sound chip, the controllers
SENTINEL = 0xFFF0            # a return address that ends a run
JSR, RTS = 0x20, 0x60
FRAME_CYCLES = 29780


class Memory:
    """The NES's memory as the 6502 sees it, without the chips: RAM (mirrored), and the cartridge's program
    through the MMC3's banks (bank 0 at $8000 and 1 at $A000 at first; writes to its registers switch
    them, as on the board)."""

    def __init__(self, ram: bytes, program: bytes):
        self.ram = bytearray(ram)
        self.program = program
        self.banks = [0, 1, FIXED_BANKS, FIXED_BANKS + 1]   # the bank in each 8K window from $8000
        self.selected = 0

    def __getitem__(self, address: int | slice) -> int | list[int]:
        if isinstance(address, slice):
            return [self.byte(index) for index in range(*address.indices(0x10000))]
        return self.byte(address)

    def byte(self, address: int) -> int:
        if address < 0x2000:
            return self.ram[address & 0x7FF]
        if address >= PRG_START:
            window = (address - PRG_START) // BANK
            return self.program[self.banks[window] * BANK + (address - PRG_START) % BANK]
        return VBLANK if address == PPU_STATUS else 0

    def __setitem__(self, address: int | slice, value: int | list[int]) -> None:
        if isinstance(address, slice):
            for index, byte in zip(range(*address.indices(0x10000)), value):  # type: ignore[arg-type]
                self[index] = byte
            return
        if address < 0x2000:
            self.ram[address & 0x7FF] = value & 0xFF  # type: ignore[operator]
        elif address == BANK_SELECT:
            self.selected = int(value) & 7  # type: ignore[arg-type]
        elif address == BANK_DATA and self.selected in (PROGRAM_8000, PROGRAM_A000):
            self.banks[self.selected - PROGRAM_8000] = int(value)  # type: ignore[arg-type]

    def __len__(self) -> int:
        return 0x10000


def labels() -> dict[int, str]:
    found: dict[int, str] = {}
    with open(LABELS) as label_file:
        for line in label_file:
            _kind, address, name = line.split()
            found.setdefault(int(address, 16), name.lstrip("."))
    return found


def run_routine(mpu: MPU, address: int, names: dict[int, str]) -> dict[str, int]:
    """Call a routine and run it to its return; each routine's cycles, including what it calls."""
    mpu.memory[0x100 + mpu.sp] = (SENTINEL - 1) >> 8
    mpu.memory[0x100 + mpu.sp - 1] = (SENTINEL - 1) & 0xFF
    mpu.sp -= 2
    mpu.pc = address
    calls: list[tuple[str, int]] = [(names.get(address, f"${address:04X}"), mpu.processorCycles)]
    totals: dict[str, int] = defaultdict(int)
    while mpu.pc != SENTINEL:
        opcode = mpu.memory[mpu.pc]
        if opcode == JSR:
            target = mpu.memory[mpu.pc + 1] | mpu.memory[mpu.pc + 2] << 8
            calls.append((names.get(target, f"${target:04X}"), mpu.processorCycles))
        elif opcode == RTS and calls:
            name, started = calls.pop()
            totals[name] += mpu.processorCycles - started
        mpu.step()
    return dict(totals)


def main() -> None:
    rom_path = build()
    machine = N.Nes(rom_path)
    play(machine, sys.argv[1:])
    with open(rom_path, "rb") as rom_file:
        program = rom_file.read()[HEADER:HEADER + PRG_SIZE]
    names = labels()
    addresses = {name: address for address, name in names.items()}
    mpu = MPU(memory=Memory(bytes(machine.ram), program))  # type: ignore[arg-type]
    mpu.sp = 0xF0
    for routine in ("game_frame", "prepare_picture", "audio_frame"):
        totals = run_routine(mpu, addresses[routine], names)
        print(f"\n{routine}: {totals.get(routine, 0)} cycles of {FRAME_CYCLES}")
        for name, cycles in sorted(totals.items(), key=lambda item: -item[1])[:16]:
            print(f"  {cycles:6d}  {name}")


if __name__ == "__main__":
    main()
