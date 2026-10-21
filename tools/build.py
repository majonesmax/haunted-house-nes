"""Build the NES ROM: assemble src/ with ca65 and link it with ld65. Two builds, one engine:

  faithful    the original's mansion, read from your 2600 ROM: build/faithful/haunted_house_faithful.nes
              (never share it)
  shareable   our own mansion, a cellar and four floors (mansion/floors.txt), and rules, nothing from the ROM:
              build/shareable/haunted_house.nes

Each build's mansion, art, ROM and labels are in its own folder; the sound is shared.

--ambient makes the same game with no songs on the floors, only the house's sounds (as the Attic has always
been); the title, the story, danger, dying and the win keep theirs. It's haunted_house_ambient.nes, beside
the other.

Usage: python tools/build.py [--shareable] [--ambient]
The other tools and tests take --shareable and --ambient too (shareable_wanted, ambient_wanted below), and
build the faithful one otherwise.

Needs cc65 (brew install cc65, or https://cc65.github.io).
"""

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "src")
BUILD = os.path.join(ROOT, "build")
LINK_CONFIG = os.path.join(SOURCE, "mmc3.cfg")
SOUND = os.path.join(BUILD, "sound")         # tools/make_music.py makes it from the remaster's soundtrack
SHAREABLE_FLAG = "--shareable"
AMBIENT_FLAG = "--ambient"
BUILDS = {   # name -> (its ROM's file name, the tool that makes its mansion.inc)
    "faithful": ("haunted_house_faithful.nes", "extract.py"),
    "shareable": ("haunted_house.nes", "shareable.py"),
}


def folder(shareable: bool) -> str:
    return os.path.join(BUILD, "shareable" if shareable else "faithful")


def rom_path(shareable: bool) -> str:
    return os.path.join(folder(shareable), BUILDS["shareable" if shareable else "faithful"][0])


def labels_for(rom: str) -> str:
    """Where the linker put each label, for the ROM at this path."""
    return os.path.splitext(rom)[0] + ".labels"


def flag_wanted(arguments: list[str], flag: str) -> bool:
    """True if the flag is among the arguments; it's taken out of them."""
    if flag in arguments:
        arguments.remove(flag)
        return True
    return False


def shareable_wanted(arguments: list[str]) -> bool:
    return flag_wanted(arguments, SHAREABLE_FLAG)


def ambient_wanted(arguments: list[str]) -> bool:
    return flag_wanted(arguments, AMBIENT_FLAG)


def make_if_missing(made: str, tool: str, *tool_arguments: str) -> None:
    if not os.path.exists(made):
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", tool), *tool_arguments], check=True)


def build(profile: bool = False, shareable: bool = False, ambient: bool = False) -> str:
    """main.s includes the rest. A profile build tints the screen while the game works, so a screenshot
    shows how long each part takes; an ambient build plays no songs on the floors. Returns the ROM's path."""
    name = "shareable" if shareable else "faithful"
    here = folder(shareable)
    art = os.path.join(here, "art")
    os.makedirs(here, exist_ok=True)
    make_if_missing(os.path.join(here, "mansion.inc"), BUILDS[name][1])
    make_if_missing(os.path.join(art, "art.inc"), "make_art.py", *([SHAREABLE_FLAG] if shareable else []))
    make_if_missing(os.path.join(SOUND, "sound.inc"), "make_music.py")
    suffix = "_ambient" if ambient else ""
    program = os.path.join(here, f"main{suffix}.o")
    includes = ["-I", SOURCE, "-I", here, "-I", art, "-I", SOUND, "--bin-include-dir", art]
    defines = ["-D", "PROFILE"] if profile else []
    if ambient:
        defines += ["-D", "AMBIENT"]
    subprocess.run(["ca65", os.path.join(SOURCE, "main.s"), *includes, *defines, "-g", "-o", program],
                   check=True)
    rom = rom_path(shareable).replace(".nes", f"{suffix}.nes")
    memory_map = os.path.splitext(rom)[0] + ".map"
    subprocess.run(["ld65", "-C", LINK_CONFIG, program, "-o", rom, "-Ln", labels_for(rom), "-m", memory_map],
                   check=True)
    return rom


if __name__ == "__main__":
    try:
        print(build(shareable=shareable_wanted(sys.argv), ambient=ambient_wanted(sys.argv)))
    except subprocess.CalledProcessError:
        sys.exit(1)
