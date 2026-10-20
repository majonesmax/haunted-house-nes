# Haunted House for the NES

A native NES version of the Atari 2600 *Haunted House* (1982): the same game, rule for rule, drawn the way the
[Haunted House remaster](https://github.com/majonesmax/haunted-house-remastered)'s NES look draws it.

Work in progress - see [the plan](docs/plan.md).

There will be two builds of one engine: a **shareable** one with a new, bigger mansion of its own, and a
**faithful** one with the original's mansion, which you build from your own copy of the 2600 game (nothing
from it is in this repository).

## Building

```sh
brew install cc65                       # or https://cc65.github.io
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/python tools/build.py         # build/haunted_house.nes
.venv/bin/python tests/test_boot.py     # it boots (needs the FCEUmm libretro core in cores/)
```
