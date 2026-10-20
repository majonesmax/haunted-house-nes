; Haunted House for the NES: power-on, the controller, and one game frame per video frame.
; The game's rules are in the other files, each following a part of the remaster's docs/spec.md.

.include "state.inc"
.include "ram.inc"

.segment "HEADER"
    .byte "NES", $1A      ; iNES
    .byte 4               ; 64K of program
    .byte 4               ; 32K of tiles
    .byte $41, 0          ; mapper 4 (MMC3)
    .res 8, 0

PPU_CONTROL = $2000
PPU_MASK    = $2001
PPU_STATUS  = $2002
NMI_ON      = $80
CONTROLLER  = $4016
APU_FRAME   = $4017

; the controller's bits once the D-pad has been shifted out of pad
PAD_A      = $08
PAD_B      = $04
PAD_SELECT = $02
PAD_START  = $01
DIRECTIONS = 4

.segment "CODE"
reset:
    sei
    cld
    ldx #$40
    stx APU_FRAME         ; no sound-chip interrupts
    ldx #$FF
    txs
    lda #0
    sta PPU_CONTROL
    sta PPU_MASK
    jsr set_up_board
    jsr wait_for_vblank
    jsr clear_ram         ; the 2600 starts with its RAM cleared
    jsr wait_for_vblank   ; the PPU needs two frames to warm up
    jsr set_up_sound
    jsr power_on
    lda #$42
    sta ready
    lda #NMI_ON
    sta PPU_CONTROL
    cli                   ; the board's scanline interrupts split the screen
main_loop:
    lda frame_started
    bne @next_frame
    inc spare             ; counting while there's nothing to do: the frame's spare time
    bne main_loop
    inc spare + 1
    jmp main_loop
@next_frame:
    lda spare             ; keep it for the checks (the loop above is 13 cycles a count)
    sta last_spare
    lda spare + 1
    sta last_spare + 1
    lda #0
    sta spare
    sta spare + 1
    sta frame_started
    jsr read_controller
    jsr screen_buttons
    inc busy
.ifdef PROFILE
    lda #(RENDER_ON | $E0) ; a debug build tints the screen while the game works (all emphasis bits)
    sta PPU_MASK
.endif
    lda #1
    sta work_part
    jsr game_frame
    lda #2
    sta work_part
.ifdef PROFILE
    lda #(RENDER_ON | $20) ; ...red while the picture is prepared
    sta PPU_MASK
.endif
    jsr prepare_picture
    jsr hints_frame
    lda #5
    sta work_part
    jsr audio_frame
.ifdef PROFILE
    lda #RENDER_ON
    sta PPU_MASK
.endif
    lda #0
    sta busy
    jmp main_loop

wait_for_vblank:
    bit PPU_STATUS
    bpl wait_for_vblank
    rts

clear_ram:
    lda #$FF              ; the sprites' table: every sprite below the screen
    ldx #0
@sprites:
    sta $0200, x
    inx
    bne @sprites
    stx oam_used          ; (0: hide_the_rest has nothing more to hide)
    lda #0
@next:
    sta $0000, x
    sta $0300, x
    sta $0400, x
    sta $0500, x
    sta $0600, x
    sta $0700, x
    inx
    bne @next
    rts

; The 2600 starts as if RESET had been pressed, then goes to game select with game 1.
power_on:
    jsr start_new_game
    jmp select_mode

; Read the controller into pad, then into the 2600's controls.
read_controller:
    lda #1
    sta CONTROLLER
    lda #0
    sta CONTROLLER
    ldx #8
@next_button:
    lda CONTROLLER
    lsr                   ; the button's state into the carry
    rol pad
    dex
    bne @next_button
    lda #0
    ldx #DIRECTIONS
@next_direction:          ; right, left, down, up come out of pad in that order...
    lsr pad
    rol
    dex
    bne @next_direction
    asl                   ; ...and move up to the stick's bits 7-4
    asl
    asl
    asl
    sta stick
    lda pad               ; now 0000 A B Select Start
    and #PAD_A
    sta button_down
    lda pad
    and #PAD_START
    sta reset_down
    lda pad
    and #PAD_SELECT
    sta select_down
    rts


.include "random.s"
.include "frame.s"
.include "moving.s"
.include "match.s"
.include "picture.s"
.include "touching.s"
.include "items.s"
.include "rooms.s"
.include "monsters.s"
.include "sound.s"
.include "view.s"
.include "sprites.s"
.include "audio.s"
.include "screens.s"
.include "hints.s"
.include "cheat.s"
.include "ppu.s"

.segment "RODATA"
bits:   .byte $01, $02, $04, $08, $10, $20, $40, $80
crossing_direction: .byte 2, 2, 3, 3, 0, 1          ; the doorway crossings, in the order they're tested
direction_stick:    .byte STICK_LEFT, STICK_RIGHT, STICK_UP, STICK_DOWN   ; by direction 0-3
block_bits:         .byte $40, $80                  ; a locked door stops moving across, or up and down
; for touching's wall test: the 16 columns from x as two bytes, those up to the next wall cell set, by x mod 16
stretched:          ; four pixels, each twice
    .byte $00, $03, $0C, $0F, $30, $33, $3C, $3F, $C0, $C3, $CC, $CF, $F0, $F3, $FC, $FF
first_cell_high:    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FE, $FC, $F8, $F0, $E0, $C0, $80
first_cell_low:     .byte $FF, $FE, $FC, $F8, $F0, $E0, $C0, $80, $00, $00, $00, $00, $00, $00, $00, $00
.include "mansion.inc"

.segment "MAPS"
.include "art.inc"
.segment "MUSIC"
.include "sound.inc"
.segment "EXTRAS"
.include "screens.inc"
.segment "RODATA"
.include "sprites.inc"

.segment "VECTORS"
    .word nmi, reset, irq

.segment "CHARS"
    .incbin "tiles.chr"
