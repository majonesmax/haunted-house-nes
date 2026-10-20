"""The shareable build's floors, as pictures: text art, drawn the way the remaster's classic pack draws its
manor (its packs/classic/source/manor.py - whose motifs and helpers this uses), a floor of the house per
floor of the game. tools/mansion_pack.py turns it into PNGs in build/, for the remaster's look to draw.

    B  The Cellar      rough stone walls; flagstones; wine racks and barrels
    1  The Foyer       the classic foyer: blue damask over a wood wainscot; black and white marble
    2  The Gallery     plum lozenge paper; polished boards; portraits whose eyes follow you, landscapes
    3  The Bedrooms    pale pink paper with small blue flowers; a patterned red carpet; mirrors, candles
    4  The Attic       the classic attic: bare planks, rough boards, cobwebs and crates

Each floor ends up in four NES colours and black (tools/floor_colours.py: the walls' two and the floor's two),
so each keeps to about that, and draws its fine detail - mortar, seams, grout - in black, which is free
(docs/decisions.md). Colours are NES palette numbers.
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

# --- B: the cellar -------------------------------------------------------------------------------------
ROUGH_STONE = """
SSSSSKSSSSSK
SsSSSKSSSsSK
KKKKKKKKKKKK
SSKSSSSSKSSS
SSKSsSSSKSSS
KKKKKKKKKKKK
"""
FLAGSTONES = """
fffffffffffK
fffefffffffK
fffffffffffK
KKKKKKKKKKKK
fffffKffffff
fffffKfffeff
fffffKffffff
KKKKKKKKKKKK
"""
WINE_RACK = """
DDDDDDDDDD
DgGDgGDgGD
DDDDDDDDDD
DgGDgGDgGD
DDDDDDDDDD
DgGDgGDgGD
DDDDDDDDDD
"""
BARREL = """
..DDDDDD..
.DwwwwwwD.
DDDDDDDDDD
DwwwwwwwwD
DwwwwwwwwD
DDDDDDDDDD
.DwwwwwwD.
..DDDDDD..
"""

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

CELLAR = {
    "paper": (ROUGH_STONE, {"S": 0x00, "s": 0x10, "K": 0x0F}),
    "wainscot": (ROUGH_STONE, {"S": 0x00, "s": 0x10, "K": 0x0F}),
    "floor": ("motif", FLAGSTONES, {"f": 0x17, "e": 0x07, "K": 0x0F}),
    "top": (manor.MASONRY, {"n": 0x00, "m": 0x0F}),
    "trim": 0x10,
    "decor": [{"kind": "wine_rack", "art": WINE_RACK, "colours": {"D": 0x07, "g": 0x0A, "G": 0x1A}},
              {"kind": "barrel", "art": BARREL, "colours": {"D": 0x07, "w": 0x17}}],
}
GALLERY = {
    "paper": (LOZENGE, {"P": 0x04, "p": 0x14}),
    "floor": ("motif", BOARDS, {"w": 0x17, "D": 0x0F, "h": 0x27}),
    "top": (manor.MASONRY, {"n": 0x04, "m": 0x0F}),
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
def with_black_mortar(floor: dict) -> dict:
    """A classic floor with its walls' tops in one colour and black mortar (the classic pack's own two
    shades would be one colour here)."""
    _motif, numbers = floor["top"]
    return floor | {"top": (manor.MASONRY, {"n": numbers["n"], "m": 0x0F})}


FOYER, ATTIC = (with_black_mortar(manor.FLOORS[number]) for number in (0, 3))
FLOORS = [CELLAR, FOYER, GALLERY, BEDROOMS, ATTIC]   # from the bottom: the cellar, then the front door's
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
