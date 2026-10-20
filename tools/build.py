"""Build the NES ROM: assemble src/ with ca65 and link it with ld65 into build/haunted_house.nes.

Usage: python tools/build.py

Needs cc65 (brew install cc65, or https://cc65.github.io).
"""

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "src")
BUILD = os.path.join(ROOT, "build")
ROM = os.path.join(BUILD, "haunted_house.nes")
LINK_CONFIG = os.path.join(SOURCE, "nrom.cfg")


def assemble(source: str) -> str:
    """One .s file into an object file in build/; returns its path."""
    name = os.path.splitext(os.path.basename(source))[0]
    output = os.path.join(BUILD, f"{name}.o")
    subprocess.run(["ca65", source, "-I", SOURCE, "-g", "-o", output], check=True)
    return output


def build() -> str:
    os.makedirs(BUILD, exist_ok=True)
    sources = sorted(name for name in os.listdir(SOURCE) if name.endswith(".s"))
    objects = [assemble(os.path.join(SOURCE, name)) for name in sources]
    labels = os.path.join(BUILD, "haunted_house.labels")
    subprocess.run(["ld65", "-C", LINK_CONFIG, *objects, "-o", ROM, "-Ln", labels], check=True)
    return ROM


if __name__ == "__main__":
    try:
        print(build())
    except subprocess.CalledProcessError:
        sys.exit(1)
