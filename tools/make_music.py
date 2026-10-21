"""The sound, for the NES's sound chip: the remaster's NES-look soundtrack (its classic pack's music.json,
arranged by the same rules as its synth, music/chiptune.py) as note streams for the four voices, and its
remastered sound effects (music/effects.py) as frame-by-frame lists for the voices they use.

Makes build/sound/sound.inc, played by src/audio.s.

A voice's stream is pairs of (note, frames): note 0 is a rest, 1-95 a note (MIDI note - 24; for the noise,
its period 0-15), TIE carries on the note before. Commands between them: INSTRUMENT + n, ARPEGGIO and two
semitone offsets (0, 0 for none: the voice cycles through the note and those, a frame each - the NES way
to play a chord on one voice), END.

Usage: python tools/make_music.py
"""

import json
import os
import sys
from collections.abc import Callable
from typing import NamedTuple

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REMASTER = os.path.join(os.path.dirname(ROOT), "haunted-house")
sys.path.insert(0, REMASTER)
from music import chiptune  # noqa: E402

OUTPUT = os.path.join(ROOT, "build", "sound", "sound.inc")
PACK_MUSIC = os.path.join(REMASTER, "packs", "classic", "music.json")
MANSION_MUSIC = os.path.join(ROOT, "mansion", "music.json")   # the shareable build's own songs
MUSIC_BANKS = (1, 4)        # program banks at $A000: the classic songs and the effects; the mansion's songs
FPS = 60.0988               # the NES's frames a second (NTSC)
CPU_HZ = 1789773
LOWEST_NOTE = 24            # note 1 is MIDI 25: notes are MIDI - 24
NOTES = 96
MAX_FRAMES = 255
REST, TIE = 0, 0x70
INSTRUMENT, ARPEGGIO, END = 0xF0, 0xE0, 0xFF
LEAD, HARMONY, BASS, DRUMS = range(4)   # the voices: pulse 1, pulse 2, triangle, noise
GAP = 1                     # frames of silence between bass notes (the remaster's 10 ms)

Event = tuple[int, int, int]   # (frame it starts, note or -1 for a command, ...) - see Stream


class Instrument(NamedTuple):
    duty: int                # pulse: 0 12.5%, 1 25%, 2 50% (noise: 0)
    volumes: list[int]       # a volume a frame from the note's start; the last is held


def swell(loudest: int, rising: int, falling: int) -> list[int]:
    """A volume a frame that rises to loudest over some frames and falls back to 0 over more."""
    rise = [round(loudest * frame / rising) for frame in range(rising)]
    fall = [round(loudest * (1 - frame / falling)) for frame in range(falling)]
    return rise + fall + [0]


def fade(start: int, frames: int) -> list[int]:
    return [max(0, round(start * (1 - frame / frames))) for frame in range(frames)] + [0]


# The instruments, numbered by their place here (src/audio.s reads them by number).
INSTRUMENTS = {
    "lead": Instrument(1, [15, 14, 13, 12, 11, 10, 10, 9]),
    "arpeggio": Instrument(0, [9, 7, 5, 4, 3]),
    "stab": Instrument(0, [8, 6, 4, 2, 1]),
    "organ": Instrument(2, [2, 3, 4, 5, 6, 6, 6, 5]),
    "shiver": Instrument(0, [8, 6, 5, 4]),
    "broken": Instrument(0, [8, 7, 6, 5, 4, 3]),
    "bass": Instrument(0, [15]),
    "kick": Instrument(0, [12, 9, 6, 3, 1, 0]),
    "snare": Instrument(0, [10, 7, 4, 2, 1, 0]),
    "hat": Instrument(0, [6, 2, 0]),
    # The haunting's (the ambient ROM's floors, below): each the length of the notes that use it, ending at 0.
    "wind": Instrument(0, swell(7, 100, 140)),
    "sigh": Instrument(0, swell(6, 30, 60)),
    "chime": Instrument(1, [8, 6, 5, 4, 3, 3, 2, 2, 1, 1, 1, 0]),
    "knock": Instrument(0, [11, 6, 3, 1, 0]),
    "shriek": Instrument(1, [15] * 20 + fade(15, 70)),
}
INSTRUMENT_NUMBER = {name: number for number, name in enumerate(INSTRUMENTS)}
DRUM_SOUNDS = {"k": ("kick", 13), "s": ("snare", 6), "h": ("hat", 1)}   # drum -> instrument, noise period
HARMONY_STYLES = {"anthem": "arpeggio", "drive": "arpeggio", "fanfare": "arpeggio", "march": "stab",
                  "organ": "organ", "tremolo": "shiver"}


def frame_at(seconds: float) -> int:
    return int(round(seconds * FPS))


class Stream:
    """One voice's notes, written as they come: (start frame, end frame, note, instrument, arpeggio)."""

    def __init__(self) -> None:
        self.notes: list[tuple[int, int, int, str, tuple[int, int]]] = []

    def add(self, start: float, end: float, midi: int, instrument: str,
            arpeggio: tuple[int, int] = (0, 0)) -> None:
        """A note from start to end seconds (midi < LOWEST_NOTE: a noise period)."""
        first, last = frame_at(start), frame_at(end)
        if last > first:
            self.notes.append((first, last, midi, instrument, arpeggio))

    def encode(self, total: float) -> list[int]:
        """The stream's bytes: rests fill the gaps; long notes are tied; END at the song's end."""
        out: list[int] = []
        now, instrument, arpeggio = 0, "", (0, 0)
        for first, last, midi, name, chord in sorted(self.notes):
            if first < now:          # overlapping notes on one voice: the later one cuts in
                first = now
            if first > now:
                out += timed(REST, first - now)
            if name != instrument:
                out += [INSTRUMENT + INSTRUMENT_NUMBER[name]]
                instrument = name
            if chord != arpeggio:
                out += [ARPEGGIO, chord[0], chord[1]]
                arpeggio = chord
            note = midi if midi < LOWEST_NOTE else midi - LOWEST_NOTE
            out += timed(note, last - first)
            now = last
        end = frame_at(total)
        if end > now:
            out += timed(REST, end - now)
        return out + [END]


def timed(note: int, frames: int) -> list[int]:
    """A note (or rest) for some frames: tied on in pieces of up to 255."""
    out = [note, min(frames, MAX_FRAMES)]
    frames -= MAX_FRAMES
    while frames > 0:
        out += [TIE if note else REST, min(frames, MAX_FRAMES)]
        frames -= MAX_FRAMES
    return out


def song_streams(song: chiptune.Song) -> tuple[list[list[int]], bool]:
    """A song (as music.json writes it) arranged as the remaster's synth arranges it, as four streams."""
    if song.get("haunting"):
        return haunting_streams(), True
    song = {"drums": "", "style": "march", "loop": True, **song}
    timing = chiptune.Timing(song)
    step = timing.step                       # a sixteenth, in seconds
    chords = song["chords"].split()
    total = len(chords) * 16 * step
    voices = [Stream() for _ in range(4)]
    melody = [token for bar in song["melody"].split("|") for token in bar.split()]
    add_melody(voices[LEAD], melody, step)
    for bar, symbol in enumerate(chords):
        root, intervals = chiptune.chord_notes(symbol)
        start = bar * 16 * step
        add_bass(voices[BASS], song["style"], root, start, step)
        add_harmony(voices[HARMONY], song["style"], root, intervals, start, step)
        if song["loop"] or bar < len(chords) - 1:
            add_drums(voices[DRUMS], song["drums"], start, step)
    return [voice.encode(total) for voice in voices], song["loop"]


def add_melody(voice: Stream, tokens: list[str], step: float) -> None:
    index = 0
    while index < len(tokens):
        token = tokens[index]
        after = index + 1
        while after < len(tokens) and tokens[after] == "-":
            after += 1
        if token not in ("-", "."):
            voice.add(2 * index * step, 2 * after * step, midi_of(token), "lead")
        index = after


def midi_of(name: str) -> int:
    letter, rest = name[0], name[1:]
    semitone = chiptune.NOTE[letter]
    while rest and rest[0] in "#b":
        semitone += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + semitone


def add_bass(voice: Stream, style: str, root: int, start: float, step: float) -> None:
    pattern = chiptune.BASS_PATTERNS.get(style, chiptune.BASS_PATTERNS["creep"])
    for index, (sixteenth, offset) in enumerate(pattern):
        until = pattern[index + 1][0] if index + 1 < len(pattern) else 16
        end = start + until * step - GAP / FPS
        voice.add(start + sixteenth * step, end, root + offset, "bass")


def add_harmony(voice: Stream, style: str, root: int, intervals: tuple[int, ...], start: float,
                step: float) -> None:
    """Pulse 2, by style. A chord on one voice is an arpeggio (the note and two more, a frame each)."""
    tones = [root + interval for interval in intervals]
    chord = (intervals[1], intervals[2])
    kind = HARMONY_STYLES.get(style, "broken")
    if kind == "arpeggio":
        sequence = tones + [tones[0] + 12, tones[1] + 12]
        for sixteenth in range(16):
            midi = sequence[sixteenth % len(sequence)] + 12
            voice.add(start + sixteenth * step, start + (sixteenth + 1) * step, midi, "arpeggio")
    elif kind == "stab":
        for sixteenth in (2, 6, 10, 14):
            voice.add(start + sixteenth * step, start + (sixteenth + 1) * step, root + 12, "stab", chord)
    elif kind == "organ":
        voice.add(start, start + 16 * step - 0.02, root + 12, "organ", chord)
    elif kind == "shiver":
        for sixteenth in range(16):
            midi = root + 12 + sixteenth % 2
            voice.add(start + sixteenth * step, start + (sixteenth + 1) * step, midi, "shiver")
    else:
        for sixteenth in range(0, 16, 2):
            midi = tones[(sixteenth // 2) % len(tones)] + 12
            voice.add(start + sixteenth * step, start + (sixteenth + 2) * step, midi, "broken")


def add_drums(voice: Stream, pattern: str, start: float, step: float) -> None:
    for sixteenth, kind in enumerate(pattern):
        if kind in DRUM_SOUNDS:
            name, period = DRUM_SOUNDS[kind]
            frames = len(INSTRUMENTS[name].volumes)
            begin = start + sixteenth * step
            voice.add(begin, begin + frames / FPS, period, name)


# --- the haunting -----------------------------------------------------------------------------------------
# The ambient ROM's one floor song (tools/build.py --ambient): no tune, only the house - a low hum that comes
# and goes, wind, a music box somewhere far off, a sigh, knocking, footsteps on the floor above - and once a
# loop, after a long hush, a shriek. Written in seconds; each line is (when, then what).
HAUNTING_SECONDS = 120.0
# The hum: (start, seconds, note). Short breaths - the triangle has no volume, so it's always at full.
HUM = [(0, 4, "E2"), (9, 3, "F2"), (26, 5, "E2"), (39, 4, "F2"), (51, 4, "E2"),
       (84, 4, "E2"), (95, 3, "F2"), (110, 5, "E2")]
GUSTS = [(4, 6), (17, 7), (23, 9), (44, 5), (55, 6), (80, 8), (88, 7), (108, 5), (114, 9)]   # (start, hiss)
GUST_SECONDS = len(INSTRUMENTS["wind"].volumes) / FPS
MUSIC_BOX = [(36.0, 0.45, "E6 G6 B6 A6 G6 F#6 E6 . E6 G6 B6 C7 B6 . Bb6"),   # (start, seconds a note, notes)
             (100.0, 0.6, "E6 G6 B6 A6 G6 F#6 . . . F6")]
SIGHS = [(20.5, "B4 Bb4"), (47.5, "G4 F#4"), (112.0, "E5 Eb5")]   # (start, two notes falling a semitone)
SIGH_SECONDS = len(INSTRUMENTS["sigh"].volumes) / FPS
KNOCKS = (30.0, [0, 0.4, 0.8, 2.2, 2.6])        # three knocks, a wait, two more: (start, each one's offset)
FOOTSTEPS = (98.0, [0, 0.7, 1.4, 2.1, 2.8, 3.5])   # someone crossing the floor above
KNOCK_HISS, FOOTSTEP_HISS = 12, 15
SHRIEK_AT = 74.0                                 # after a hush: nothing since the gust at 55
SHRIEK = [("E6", (1, 6)), ("Bb5", (1, 0))]       # the two pulses: a note, and its arpeggio's offsets
HAUNTING_SONG = {"haunting": {"haunting": True, "loop": True}}   # song_streams knows it by its "haunting"


def haunting_streams() -> list[list[int]]:
    voices = [Stream() for _ in range(4)]
    for start, seconds, note in HUM:
        voices[BASS].add(start, start + seconds, midi_of(note), "bass")
    for start, hiss in GUSTS:
        voices[DRUMS].add(start, start + GUST_SECONDS, hiss, "wind")
    for start, note_seconds, notes in MUSIC_BOX:
        for index, note in enumerate(notes.split()):
            if note != ".":
                when = start + index * note_seconds
                voices[LEAD].add(when, when + note_seconds, midi_of(note), "chime")
    for start, notes in SIGHS:
        for index, note in enumerate(notes.split()):
            when = start + index * SIGH_SECONDS
            voices[HARMONY].add(when, when + SIGH_SECONDS, midi_of(note), "sigh")
    add_taps(voices[DRUMS], KNOCKS, KNOCK_HISS)
    add_taps(voices[DRUMS], FOOTSTEPS, FOOTSTEP_HISS)
    add_shriek(voices)
    return [voice.encode(HAUNTING_SECONDS) for voice in voices]


def add_taps(voice: Stream, taps: tuple[float, list[float]], hiss: int) -> None:
    start, offsets = taps
    for offset in offsets:
        voice.add(start + offset, start + offset + 0.1, hiss, "knock")


def add_shriek(voices: list[Stream]) -> None:
    """Both pulses at once, a tritone apart, each buzzing through its arpeggio; a crash; a thud."""
    seconds = len(INSTRUMENTS["shriek"].volumes) / FPS
    for voice, (note, arpeggio) in zip((voices[LEAD], voices[HARMONY]), SHRIEK):
        voice.add(SHRIEK_AT, SHRIEK_AT + seconds, midi_of(note), "shriek", arpeggio)
    voices[DRUMS].add(SHRIEK_AT, SHRIEK_AT + seconds, 3, "shriek")
    voices[BASS].add(SHRIEK_AT, SHRIEK_AT + 0.4, midi_of("E1"), "bass")


# --- the sound effects ------------------------------------------------------------------------------------
# An effect is, for each voice it uses, a list of frames: (volume, duty or noise mode, period). Made after
# the remaster's music/effects.py: what each sound is, in the NES's own terms.
Frames = list[tuple[int, int, int]]


def pulse_period(pitch: float) -> int:
    return max(8, min(0x7FF, int(round(CPU_HZ / (16 * pitch) - 1))))


def triangle_period(pitch: float) -> int:
    return max(2, min(0x7FF, int(round(CPU_HZ / (32 * pitch) - 1))))


def glide(start_hz: float, end_hz: float, frames: int, period: Callable[[float], int], volume: list[int],
          duty: int = 0) -> Frames:
    """A pitch gliding from start_hz to end_hz (evenly in pitch), with a volume a frame (last held)."""
    out = []
    for frame in range(frames):
        pitch = start_hz * (end_hz / start_hz) ** (frame / max(1, frames - 1))
        out.append((volume[min(frame, len(volume) - 1)], duty, period(pitch)))
    return out


def run(midis: list[int], frames_each: int, duty: int, volume: list[int],
        period: Callable[[float], int] = pulse_period) -> Frames:
    out = []
    for midi in midis:
        for frame in range(frames_each):
            out.append((volume[min(frame, len(volume) - 1)], duty, period(chiptune.midi_hz(midi))))
    return out


def noise(frames: int, period: int, volume: list[int]) -> Frames:
    return [(volume[min(frame, len(volume) - 1)], 0, period) for frame in range(frames)]


def silence(frames: int) -> Frames:
    return [(0, 0, 0)] * frames


EFFECTS: dict[str, dict[int, Frames]] = {
    "match_strike": {DRUMS: noise(4, 3, [12, 8, 5, 3]) + noise(18, 6, [6, 9, 8, 7, 6, 5, 4, 3, 2, 1, 1, 0])},
    "match_out": {DRUMS: noise(14, 12, [4, 8, 6, 4, 3, 2, 1, 0])},
    "door_open": {HARMONY: glide(330, 210, 26, pulse_period, [3, 7, 8, 7, 6, 5, 5, 4, 4, 3, 3, 2, 1, 0])},
    "door_close": {BASS: glide(120, 55, 12, triangle_period, [15] * 11 + [0])},
    "locked": {DRUMS: (noise(2, 6, [9, 3]) + silence(2)) * 3 + silence(6),
               BASS: silence(13) + glide(90, 60, 9, triangle_period, [15] * 8 + [0])},
    "bump": {BASS: glide(100, 70, 5, triangle_period, [15, 15, 15, 15, 0])},
    "stairs_up": {HARMONY: [frame for midi in (57, 60, 62, 64, 67, 69)
                            for frame in run([midi], 6, 1, [9, 7, 5, 4, 3, 0])]},
    "stairs_down": {HARMONY: [frame for midi in (69, 67, 64, 62, 60, 57)
                              for frame in run([midi], 6, 1, [9, 7, 5, 4, 3, 0])]},
    "pickup_key": {HARMONY: run([84, 88, 84, 88], 3, 0, [10, 7, 5])},
    "pickup_scepter": {HARMONY: run([72, 76, 79, 84, 88, 91], 3, 0, [10, 7, 5])},
    "pickup_urn": {BASS: run([60, 64, 67, 72], 4, 0, [15, 15, 15, 0], triangle_period)},
    "drop": {BASS: glide(180, 90, 7, triangle_period, [15] * 6 + [0])},
    "urn_join": {HARMONY: run([67, 71, 74, 79, 83, 86, 91], 3, 0, [10, 8, 6])},
    "urn_whole": {HARMONY: run([67, 71, 74, 79, 83, 86, 91, 95], 3, 0, [10, 8, 6])
                  + run([79, 83, 86] * 8, 2, 1, fade(9, 48))[:48]},
    "caught": {LEAD: glide(900, 150, 36, pulse_period, [10, 10, 9, 9, 8, 8, 7, 7, 6, 6, 5, 5, 4, 4, 3, 2, 1],
                           1),
               DRUMS: silence(3) + noise(30, 13, fade(12, 30))},
    "thunder": {DRUMS: noise(5, 4, [8, 6, 4, 2, 1]) + noise(80, 15, [6, 9, 11, 12] + fade(12, 76))},
    "monster_ghost": {BASS: glide(220, 160, 54, triangle_period, [15] * 53 + [0])},
    "monster_bat": {DRUMS: (noise(2, 11, [8, 2]) + silence(2)) * 6},
    "monster_tarantula": {DRUMS: (noise(1, 2, [7]) + silence(1)) * 9},
    "footstep": {BASS: glide(140, 90, 3, triangle_period, [15, 15, 0])},
}
QUIET_EFFECTS = ("footstep",)   # these never cut another effect short


def effect_bytes(parts: dict[int, Frames]) -> list[int]:
    """For each voice: voice, frames, then (volume | duty << 6, period low, period high) a frame; $FF ends."""
    out = []
    for voice, frames in parts.items():
        out += [voice, len(frames)]
        for volume, duty, period in frames:
            out += [volume | duty << 6, period & 0xFF, period >> 8]
    return out + [END]


# --- the tables -------------------------------------------------------------------------------------------
def period_tables() -> tuple[list[int], list[int]]:
    """Each note's period (note n = MIDI n + 24) for the pulses, and for the triangle (an octave lower)."""
    pulses = [pulse_period(chiptune.midi_hz(LOWEST_NOTE + note)) for note in range(NOTES)]
    triangles = [triangle_period(chiptune.midi_hz(LOWEST_NOTE + note)) for note in range(NOTES)]
    return pulses, triangles


def byte_lines(data: list[int], per_line: int = 16) -> list[str]:
    return ["    .byte " + ", ".join(f"${value:02X}" for value in data[start:start + per_line])
            for start in range(0, len(data), per_line)]


def word_lines(labels: list[str]) -> list[str]:
    return ["    .word " + ", ".join(labels[start:start + 4]) for start in range(0, len(labels), 4)]


def all_songs() -> tuple[dict[str, dict], set[str]]:
    """The classic soundtrack's songs, then the mansion's own: the haunting (written out here, not in the
    remaster's notation, so not in mansion/music.json - the SNES game reads that file too), then
    mansion/music.json's; and the names of ours."""
    with open(PACK_MUSIC) as music_file:
        songs = json.load(music_file)["songs"]
    with open(MANSION_MUSIC) as music_file:
        ours = HAUNTING_SONG | json.load(music_file)["songs"]
    return songs | ours, set(ours)


def shared_block(songs: dict[str, dict], ours: set[str], labelled: bool) -> list[str]:
    """What both music banks start with, at the same places in each, so it reads the same whichever is in:
    the instruments, the notes' periods, every song's streams, whether it loops and the bank it's in. Labelled
    in the first bank only."""
    def label(name: str, what: str = "") -> str:
        return (f"{name}:" if labelled else ";") + (f"   ; {what}" if what else "")
    duties = [instrument.duty << 6 for instrument in INSTRUMENTS.values()]
    lines = [label("instrument_duty")] + byte_lines(duties)
    lines += [label("instrument_volumes", "per instrument: its volumes, $FF after the last (held)")]
    lines += word_lines([f"volumes_{name}" for name in INSTRUMENTS])
    for name, instrument in INSTRUMENTS.items():
        lines += [label(f"volumes_{name}")] + byte_lines(instrument.volumes + [END])
    pulses, triangles = period_tables()
    lines += [label("pulse_low")] + byte_lines([period & 0xFF for period in pulses])
    lines += [label("pulse_high")] + byte_lines([period >> 8 for period in pulses])
    lines += [label("triangle_low")] + byte_lines([period & 0xFF for period in triangles])
    lines += [label("triangle_high")] + byte_lines([period >> 8 for period in triangles])
    lines += [label("song_voices", "per song, its four streams")]
    lines += word_lines([f"song_{name}_{voice}" for name in songs for voice in range(4)])
    lines += [label("song_loops")] + byte_lines([1 if song["loop"] else 0 for song in songs.values()])
    lines += [label("song_banks", "per song, the program bank its streams are in, at $A000")]
    return lines + byte_lines([MUSIC_BANKS[1] if name in ours else MUSIC_BANKS[0] for name in songs])


def song_lines(songs: dict[str, dict]) -> list[str]:
    lines = []
    for name, song in songs.items():
        streams, _loop = song_streams(song)
        for voice, stream in enumerate(streams):
            lines += [f"song_{name}_{voice}:"] + byte_lines(stream)
    return lines


def include_lines() -> list[str]:
    songs, ours = all_songs()
    lines = ["; Made by tools/make_music.py from the remaster's classic soundtrack and effects, and the",
             "; mansion's own songs. It opens both music banks: MUSIC (bank 1), then MUSIC_2 (bank 4).", ""]
    lines += [f"INSTRUMENT_{name.upper()} = {number}" for name, number in INSTRUMENT_NUMBER.items()]
    lines += [f"SONG_{name.upper()} = {number}" for number, name in enumerate(songs)]
    lines += [f"EFFECT_{name.upper()} = {number}" for number, name in enumerate(EFFECTS)]
    lines += [f"SONG_COUNT = {len(songs)}", f"QUIET_EFFECT = EFFECT_{QUIET_EFFECTS[0].upper()}",
              f"MUSIC_BANK = {MUSIC_BANKS[0]}", ""]
    lines += ['.segment "MUSIC"'] + shared_block(songs, ours, True)
    lines += song_lines({name: song for name, song in songs.items() if name not in ours})
    for name, parts in EFFECTS.items():
        lines += [f"effect_{name}:"] + byte_lines(effect_bytes(parts))
    lines += ["effects:"] + word_lines([f"effect_{name}" for name in EFFECTS])
    lines += ['.segment "MUSIC_2"'] + shared_block(songs, ours, False)
    return lines + song_lines({name: song for name, song in songs.items() if name in ours})


def main() -> None:
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    lines = include_lines()
    with open(OUTPUT, "w") as include:
        include.write("\n".join(lines) + "\n")
    size = sum(line.count("$") for line in lines if line.startswith("    .byte"))
    print(f"{OUTPUT}: about {size} bytes of data")


if __name__ == "__main__":
    main()
