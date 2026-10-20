; Haunted House for the NES: power-on, the controller, and one game frame per video frame.
; The game's rules are in the other files, each following a part of the remaster's docs/spec.md.

.include "state.inc"

.segment "HEADER"
    .byte "NES", $1A      ; iNES
    .byte 1               ; 16K of program
    .byte 1               ; 8K of pictures
    .byte 0, 0            ; mapper 0 (NROM), horizontal mirroring
    .res 8, 0

PPU_CONTROL = $2000
PPU_MASK    = $2001
PPU_STATUS  = $2002
NMI_ON      = $80
CONTROLLER  = $4016

; the NES's own bytes, below the game's state
.segment "ZEROPAGE"
frame_count:    .res 1    ; +1 every frame, from the NMI
ready:          .res 1    ; $42 once the console is set up (the boot check looks for it)
frame_started:  .res 1    ; set by the NMI: time for the next game frame
pad:            .res 1    ; the controller: bit 7 A, 6 B, 5 Select, 4 Start, 3 up, 2 down, 1 left, 0 right
stick:          .res 1    ; the D-pad as the 2600 joystick (STICK_ bits)
button_down:    .res 1    ; A, the joystick's button: not 0 while held
reset_down:     .res 1    ; Start, the console's RESET switch
select_down:    .res 1    ; Select, the console's SELECT switch
busy:           .res 1    ; not 0 while a game frame is worked out
late_frames:    .res 1    ; frames the work ran past the next frame's start (the checks look for 0)

; touching (touching.s): what this frame's sprite touched
touched_eyes:   .res 1    ; not 0: the sprite overlapped the eyes
touched_walls:  .res 1    ; not 0: the sprite overlapped a wall
sprite_wide:    .res 1    ; not 0: this frame's sprite is the stairs, drawn at double width
line_top:       .res 1    ; the first line drawn
line_below:     .res 1    ; the line below the last one drawn
touch_k:        .res 1    ; the sprite's row being tested...
touch_row:      .res 1    ; ...its pixels...
sprite_row_line: .res 1   ; ...and the line it's on
wall_line:      .res 1    ; the line being tested
eyes_now:       .res 1    ; the eyes' row on it
eyes_rows:      .res 3    ; the eyes' picture, bottom row first
touch_column:   .res 1    ; the row's first column
touch_y:        .res 1    ; the floor y of wall_line
touch_wide_high: .res 1   ; the row as 16 columns
touch_wide_low: .res 1
touch_mask_high: .res 1   ; the columns in the first wall cell...
touch_mask_low: .res 1
touch_first_cell_high: .res 1   ; ...and those that are wall
touch_first_cell_low: .res 1
touch_pixels:   .res 1
touch_count:    .res 1

; the controller's bits once the D-pad has been shifted out of pad
PAD_A      = $08
PAD_SELECT = $02
PAD_START  = $01
DIRECTIONS = 4

.segment "CODE"
reset:
    sei
    cld
    ldx #$FF
    txs
    lda #0
    sta PPU_CONTROL
    sta PPU_MASK
    jsr wait_for_vblank
    jsr clear_ram         ; the 2600 starts with its RAM cleared
    jsr wait_for_vblank   ; the PPU needs two frames to warm up
    jsr power_on
    lda #$42
    sta ready
    lda #NMI_ON
    sta PPU_CONTROL
main_loop:
    lda frame_started
    beq main_loop
    lda #0
    sta frame_started
    jsr read_controller
    inc busy
    jsr game_frame
    lda #0
    sta busy
    jmp main_loop

wait_for_vblank:
    bit PPU_STATUS
    bpl wait_for_vblank
    rts

clear_ram:
    lda #0
    tax
@next:
    sta $0000, x
    sta $0200, x          ; (page 1 is the stack, in use)
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

nmi:
    inc frame_count
    inc frame_started
    pha
    lda busy
    beq @on_time
    inc late_frames
@on_time:
    pla
    rti

irq:
    rti

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

.segment "RODATA"
bits:   .byte $01, $02, $04, $08, $10, $20, $40, $80
crossing_direction: .byte 2, 2, 3, 3, 0, 1          ; the doorway crossings, in the order they're tested
direction_stick:    .byte STICK_LEFT, STICK_RIGHT, STICK_UP, STICK_DOWN   ; by direction 0-3
block_bits:         .byte $40, $80                  ; a locked door stops moving across, or up and down
; for touching's wall test: the 16 columns from x as two bytes, those up to the next wall cell set, by x mod 16
first_cell_high:    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FE, $FC, $F8, $F0, $E0, $C0, $80
first_cell_low:     .byte $FF, $FE, $FC, $F8, $F0, $E0, $C0, $80, $00, $00, $00, $00, $00, $00, $00, $00
.include "mansion.inc"

.segment "VECTORS"
    .word nmi, reset, irq

.segment "CHARS"
    .res 8192
