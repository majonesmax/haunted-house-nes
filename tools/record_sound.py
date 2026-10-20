"""Play the ROM for a while and save its sound as a WAV - to listen to the music and the effects.

Usage: python tools/record_sound.py NAME [steps...]      (steps as tools/screenshot.py takes them)
  e.g.  python tools/record_sound.py title 300                  the title's music for 5 seconds
        python tools/record_sound.py floor 30 6:start 600       floor 1's
Saves shots/sound/NAME.wav.
"""

import os
import sys
import wave

import numpy as np

from build import build, shareable_wanted
import nes as N
from screenshot import play

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOUND = os.path.join(ROOT, "shots", "sound")


def main() -> None:
    shareable = shareable_wanted(sys.argv)
    name, steps = sys.argv[1], sys.argv[2:]
    machine = N.Nes(build(shareable=shareable))
    machine.recording = True
    play(machine, steps)
    samples = np.concatenate(machine.sound) if machine.sound else np.zeros((0, 2), np.int16)
    os.makedirs(SOUND, exist_ok=True)
    path = os.path.join(SOUND, f"{name}.wav")
    with wave.open(path, "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(int(round(machine.sample_rate())))
        out.writeframes(samples.tobytes())
    print(f"{path}: {len(samples) / machine.sample_rate():.1f} s, loudest {int(np.abs(samples).max())}")


if __name__ == "__main__":
    main()
