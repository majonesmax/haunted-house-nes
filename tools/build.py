"""Build the NES ROM: assemble src/ with ca65 and link it with ld65. For now there's one build, the
faithful one, with the mansion read from your 2600 ROM: build/haunted_house_faithful.nes (never share it).

Usage: python tools/build.py

Needs cc65 (brew install cc65, or https://cc65.github.io).
"""

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "src")
BUILD = os.path.join(ROOT, "build")
ROM = os.path.join(BUILD, "haunted_house_faithful.nes")
MANSION = os.path.join(BUILD, "faithful")   # tools/extract.py makes it from your 2600 ROM
LINK_CONFIG = os.path.join(SOURCE, "nrom.cfg")


def build() -> str:
    """main.s includes the rest; the mansion comes from build/faithful/mansion.inc."""
    os.makedirs(BUILD, exist_ok=True)
    if not os.path.exists(os.path.join(MANSION, "mansion.inc")):
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "extract.py")], check=True)
    program = os.path.join(BUILD, "main.o")
    subprocess.run(["ca65", os.path.join(SOURCE, "main.s"), "-I", SOURCE, "-I", MANSION, "-g", "-o", program],
                   check=True)
    labels = os.path.join(BUILD, "haunted_house.labels")
    subprocess.run(["ld65", "-C", LINK_CONFIG, program, "-o", ROM, "-Ln", labels], check=True)
    return ROM


if __name__ == "__main__":
    try:
        print(build())
    except subprocess.CalledProcessError:
        sys.exit(1)
