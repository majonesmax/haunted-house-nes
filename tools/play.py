"""Play the ROM on this computer, with the keyboard: a window, the sound, and the FCEUmm core the checks use
(tools/nes.py). Builds the ROM first if it isn't built.

Keys (the NES controller's buttons):
  arrow keys or W A S D    the D-pad: walk
  Space or X               A: light a match; put down what you hold
  Z or G                   B: a hint in play (when you let go); the help on the title
  Enter                    Start: start a game
  Tab                      Select: choose the game, 1-9
  O                        B and Select together: the lights-on cheat
  Escape                   quit

Usage: python tools/play.py [--shareable]      (the faithful build without --shareable)
"""

import collections
import os
import sys

import numpy as np
import pygame
import sounddevice

import nes as N
from build import build, rom_path, shareable_wanted

SCALE = 3
FPS = 60.0988               # the NES's frames a second
CHEAT_FRAMES = 6            # how long O holds B and Select together
AUDIO_BLOCK = 512           # samples the sound card asks for at a time
MOST_QUEUED = 8000          # samples kept waiting at most: past this the oldest go, so the sound keeps up
KEYS = {
    pygame.K_UP: N.BUTTON_UP, pygame.K_w: N.BUTTON_UP,
    pygame.K_DOWN: N.BUTTON_DOWN, pygame.K_s: N.BUTTON_DOWN,
    pygame.K_LEFT: N.BUTTON_LEFT, pygame.K_a: N.BUTTON_LEFT, pygame.K_RIGHT: N.BUTTON_RIGHT,
    pygame.K_d: N.BUTTON_RIGHT, pygame.K_SPACE: N.BUTTON_A, pygame.K_x: N.BUTTON_A, pygame.K_z: N.BUTTON_B,
    pygame.K_g: N.BUTTON_B, pygame.K_RETURN: N.BUTTON_START, pygame.K_TAB: N.BUTTON_SELECT,
}


class Speaker:
    """The game's sound, played as it's made: each frame's samples join a queue the sound card reads."""

    def __init__(self, rate: float):
        self.queue: collections.deque[np.ndarray] = collections.deque()
        self.waiting = 0
        self.stream = sounddevice.OutputStream(samplerate=rate, channels=2, dtype="int16",
                                               blocksize=AUDIO_BLOCK, callback=self.fill)
        self.stream.start()

    def add(self, samples: np.ndarray) -> None:
        self.queue.append(samples)
        self.waiting += len(samples)
        while self.waiting > MOST_QUEUED and len(self.queue) > 1:
            self.waiting -= len(self.queue.popleft())

    def fill(self, out: np.ndarray, frames: int, _time: object, _status: object) -> None:
        filled = 0
        while filled < frames and self.queue:
            chunk = self.queue[0]
            taken = min(frames - filled, len(chunk))
            out[filled:filled + taken] = chunk[:taken]
            filled += taken
            self.waiting -= taken
            if taken == len(chunk):
                self.queue.popleft()
            else:
                self.queue[0] = chunk[taken:]
        out[filled:] = 0


def held_buttons(cheat_left: int) -> set[int]:
    pressed = pygame.key.get_pressed()
    held = {button for key, button in KEYS.items() if pressed[key]}
    if cheat_left > 0:
        held |= {N.BUTTON_B, N.BUTTON_SELECT}
    return held


def main() -> None:
    shareable = shareable_wanted(sys.argv)
    rom = rom_path(shareable)
    if not os.path.exists(rom):
        build(shareable=shareable)
    machine = N.Nes(rom)
    pygame.init()
    window = pygame.display.set_mode((256 * SCALE, 240 * SCALE))
    pygame.display.set_caption("Haunted House: By Matchlight")
    speaker = Speaker(machine.sample_rate())
    machine.recording = True
    clock = pygame.time.Clock()
    cheat_left = 0
    while True:
        for event in pygame.event.get():
            if event.type == pygame.QUIT or (event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE):
                return
            if event.type == pygame.KEYDOWN and event.key == pygame.K_o:
                cheat_left = CHEAT_FRAMES
        machine.sound.clear()
        machine.run(1, held_buttons(cheat_left))
        cheat_left -= 1
        for samples in machine.sound:
            speaker.add(samples)
        if machine.picture is not None:
            frame = pygame.surfarray.make_surface(machine.picture[..., :3].swapaxes(0, 1))
            window.blit(pygame.transform.scale(frame, window.get_size()), (0, 0))
            pygame.display.flip()
        clock.tick(FPS)


if __name__ == "__main__":
    main()
