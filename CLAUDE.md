# Working on Haunted House for the NES with an AI assistant

Notes for Claude Code (or any coding assistant); for people, a quick tour. The plan and its steps:
[docs/plan.md](docs/plan.md).

This is a native NES game written in 6502 assembly (ca65), from the rules in the remaster's
`../haunted-house/docs/spec.md` and its models (`game/player.py`, `game/monsters.py`, `game/sounds.py`), which
predict the original game exactly. Python here is for tools and checks only.

## Commands

```sh
.venv/bin/python tools/build.py          # build/haunted_house.nes (ca65 + ld65, src/nrom.cfg)
.venv/bin/python tests/test_boot.py      # it boots in the emulator (tools/nes.py, FCEUmm in cores/)
.venv/bin/python tools/readability.py    # the Python readability rules (a hook runs it after each edit)
```

## Rules

- **Write the engine from the spec and the models, never from the disassembly.** The original's code is
  Atari's; the rules aren't.
- **Never commit anything from the 2600 ROM**: its tables, its pictures, or a faithful build. They're made in
  `build/` from the user's own ROM and stay there.
- **Keep the game's state where the 2600 kept it**: zero page `$80`-`$FF`, same bytes, same meanings. The
  check compares it with the model frame by frame. Put everything the NES needs besides in `$00`-`$7F` and
  the rest of RAM.
- **Prove each routine before the next.** A routine is done when the check agrees with the model on it.
- **Art is our own**, drawn as text and generated into tiles, like the remaster's packs.

## Readable code

The person who owns this reads it rather than writes it. Assembly especially: a comment on each routine
saying what it does and which part of the spec it follows, names for every address and constant
(`player_x`, not `$AA`), short routines. Python follows the remaster's rules: names of 3 letters or more,
lines of 110 or less, types on every signature; `tools/readability.py` keeps it at zero.
