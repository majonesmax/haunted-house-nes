"""Download the FCEUmm NES libretro core into cores/ - the emulator the checks play the ROM in (GPL-2.0,
https://github.com/libretro/libretro-fceumm).

It comes from libretro's nightly builds, which keep only the latest. Unlike the remaster's pinned Stella,
nothing here depends on the core's exact version: the checks compare the game's RAM, which any accurate
NES gives the same, never its pictures. (The Mesen core crashes in this harness, so it isn't used.)

Usage: python tools/get_core.py           the core for this system, if it isn't there yet
       python tools/get_core.py --force   download it again
"""

import io
import os
import platform
import sys
import urllib.request
import zipfile

from nes import CORE

NIGHTLY = "https://buildbot.libretro.com/nightly"
PLATFORMS = {("darwin", "arm64"): "apple/osx/arm64", ("darwin", "x86_64"): "apple/osx/x86_64",
             ("linux", "x86_64"): "linux/x86_64", ("win32", "x86_64"): "windows/x86_64"}


def processor() -> str:
    machine = platform.machine().lower()
    return {"amd64": "x86_64", "x64": "x86_64", "aarch64": "arm64"}.get(machine, machine)


def main() -> None:
    if os.path.exists(CORE) and "--force" not in sys.argv:
        print(f"{CORE} is already there (--force to download it again)")
        return
    where = PLATFORMS.get((sys.platform, processor()))
    if where is None:
        sys.exit(f"no FCEUmm build known for {sys.platform} {processor()}")
    name = os.path.basename(CORE)
    url = f"{NIGHTLY}/{where}/latest/{name}.zip"
    print(f"downloading {url}")
    with urllib.request.urlopen(url) as response:
        archive = zipfile.ZipFile(io.BytesIO(response.read()))
    os.makedirs(os.path.dirname(CORE), exist_ok=True)
    with open(CORE, "wb") as core_file:
        core_file.write(archive.read(name))
    print(CORE)


if __name__ == "__main__":
    main()
