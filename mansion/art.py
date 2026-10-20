"""The shareable build's floors, as pictures: text art, drawn the way the remaster's classic pack draws its
manor (its packs/classic/source/manor.py - whose motifs and helpers this uses), a floor of the house per
floor of the game. tools/mansion_pack.py turns it into PNGs in build/, for the remaster's look to draw.

    1  The Foyer       the classic foyer: blue damask over a wood wainscot; black and white marble
    2  The Gallery     plum lozenge paper; polished boards; portraits whose eyes follow you, landscapes
    3  The Library     the classic dining hall's red stripes and parquet, its bookshelves and portraits
    4  The Bedrooms    pale pink paper with small blue flowers; a patterned red carpet; mirrors, candles
    5  The Nursery     pink and cream stripes with stars; big yellow and blue checks; a clock, toy blocks
    6  The Attic       the classic attic: bare planks, rough boards, cobwebs and crates

Each floor ends up in three NES colours and black (tools/make_art.py chooses them), so each keeps to about
three families of colour. Colours are NES palette numbers.
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REMASTER = os.path.join(os.path.dirname(ROOT), "haunted-house")
sys.path.insert(0, REMASTER)
sys.path.insert(0, os.path.join(REMASTER, "packs", "classic", "source"))
import manor  # noqa: E402

from shared.pixelart import from_ascii  # noqa: E402

Pictures = manor.Pictures

# --- 2: the gallery ------------------------------------------------------------------------------------
LOZENGE = """
PPPPpPPP
PPPpPpPP
PPpPPPpP
PpPPPPPp
PPpPPPpP
PPPpPpPP
"""
BOARDS = """
wwwwwwwwwwwD
hwwwwwwwwwwD
wwwwwwwwwwwD
DDDDDDDDDDDD
wwwwwDwwwwww
wwwwwDhwwwww
wwwwwDwwwwww
DDDDDDDDDDDD
"""
LANDSCAPE = """
GGGGGGGGGGGGGG
GssssssssssssG
GsssssssMMsssG
GssssssMMMMssG
GssMMsMMMMMMsG
GMMMMMMMMMMMMG
GggggggggggggG
GggggggggggggG
GGGGGGGGGGGGGG
"""

# --- 4: the bedrooms -----------------------------------------------------------------------------------
FLORAL = """
bbbbbbbb
bbFbbbbb
bFyFbbbb
bbFbbbbb
bbbbbbbb
bbbbbFbb
bbbbFyFb
bbbbbFbb
"""
CARPET = """
rrrrrRrrrrrr
rrrrRrRrrrrr
rrrRrrrRrrrr
rrRrrorrRrrr
rrrRrrrRrrrr
rrrrRrRrrrrr
rrrrrRrrrrrr
rrrrrrrrrrrr
"""
MIRROR = """
..GGGGGG..
.GmmmmmmG.
GmWmmmmmmG
GmWmmmmmmG
GmmWmmmmmG
GmmmmmmmmG
.GmmmmmmG.
..GGGGGG..
"""
CANDLE = """
...W....
...W....
...W....
..GGG...
.GGGGG..
"""

# --- 5: the nursery ------------------------------------------------------------------------------------
NURSERY_STRIPES = """
ppppcccc
ppppcccc
ppppcycc
ppppcccc
ppppcccc
ppppcccc
"""
CHECKS = """
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
yyyyyyyyyyyyBBBBBBBBBBBB
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
BBBBBBBBBBBByyyyyyyyyyyy
"""
CLOCK = """
...DDDD...
..DwwwwD..
.DwWWWWwD.
.DwWKWWwD.
.DwWWKWwD.
.DwWWWWwD.
..DwwwwD..
...DDDD...
....D.....
....G.....
"""
BLOCKS = """
DDDDDDDDDD
DrrDbbDyyD
DrRDbBDyYD
DrrDbbDyyD
DDDDDDDDDD
DyyDrrDbbD
DyYDrRDbBD
DyyDrrDbbD
DDDDDDDDDD
"""

GALLERY = {
    "paper": (LOZENGE, {"P": 0x04, "p": 0x14}),
    "floor": ("motif", BOARDS, {"w": 0x17, "D": 0x07, "h": 0x27}),
    "top": (manor.MASONRY, {"n": 0x04, "m": 0x03}),
    "trim": 0x14,
    "decor": [{"kind": "portrait", "art": manor.PORTRAIT, "eyes": True,
               "colours": {"G": 0x27, "d": 0x04, "q": 0x14, "f": 0x37, "K": 0x0F, "W": 0x30, "c": 0x16}},
              {"kind": "landscape", "art": LANDSCAPE,
               "colours": {"G": 0x27, "s": 0x21, "M": 0x00, "g": 0x1A}}],
}
BEDROOMS = {
    "paper": (FLORAL, {"b": 0x35, "F": 0x11, "y": 0x30}),     # its pink is the carpet's pattern too: three
    "floor": ("motif", CARPET, {"r": 0x16, "R": 0x35, "o": 0x35}),   # colours in all, so none is lost
    "top": (manor.MASONRY, {"n": 0x01, "m": 0x0F}),   # (black mortar: black is always there, a free colour)
    "trim": 0x11,
    "decor": [{"kind": "mirror", "art": MIRROR, "colours": {"G": 0x27, "m": 0x10, "W": 0x30}},
              {"kind": "candle", "frames": [flame.strip("\n") + "\n" + CANDLE.strip("\n")
                                            for flame in manor.SCONCE_FLAMES],
               "colours": {"F": 0x28, "y": 0x30, "W": 0x30, "G": 0x27}}],
}
NURSERY = {
    "paper": (NURSERY_STRIPES, {"p": 0x25, "c": 0x37, "y": 0x28}),
    "floor": ("motif", CHECKS, {"y": 0x28, "B": 0x21}),
    "top": (manor.MASONRY, {"n": 0x15, "m": 0x05}),
    "trim": 0x25,
    "decor": [{"kind": "clock", "art": CLOCK, "colours": {"D": 0x07, "w": 0x17, "W": 0x30, "K": 0x0F,
                                                           "G": 0x27}},
              {"kind": "blocks", "art": BLOCKS,
               "colours": {"D": 0x07, "r": 0x16, "R": 0x26, "b": 0x11, "B": 0x21, "y": 0x28, "Y": 0x38}}],
}
FOYER, DINING_HALL, ATTIC = manor.FLOORS[0], manor.FLOORS[1], manor.FLOORS[3]
FLOORS = [FOYER, GALLERY, DINING_HALL, BEDROOMS, NURSERY, ATTIC]   # the first floor first
SHARED = ("front_door", "title_mansion", "title_moon")   # the classic pack's, as they are


def world_pictures() -> Pictures:
    """Every world picture, named as the remaster's scenery code asks for them (floor<n>, wall<n>_top...)."""
    classic = manor.world_pictures()
    pictures: Pictures = {name: classic[name] for name in SHARED}
    for number, floor in enumerate(FLOORS, start=1):
        pictures[f"floor{number}"] = manor.floor_tile(floor)
        pictures[f"wall{number}"] = manor.top(floor)
        pictures[f"wall{number}_top"] = manor.top(floor)
        pictures[f"wall{number}_face"] = manor.face(floor)
        pictures[f"wall{number}_trim"] = from_ascii("T", manor.colours({"T": floor["trim"]}), strict=True)
        for decoration in floor["decor"]:
            pictures.update(manor.decoration_pictures(number, decoration))
    return pictures
