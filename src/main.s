; Haunted House for the NES - the start: the console is set up and the frame counter runs.
; The game itself comes routine by routine, each checked against the remaster's model (docs/plan.md).

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

.segment "ZEROPAGE"
frame_count: .res 1       ; +1 every frame, from the NMI
ready:       .res 1       ; $42 once the console is set up (the boot check looks for it)

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
    jsr wait_for_vblank   ; the PPU needs two frames to warm up
    lda #$42
    sta ready
    lda #NMI_ON
    sta PPU_CONTROL
forever:
    jmp forever

wait_for_vblank:
    bit PPU_STATUS
    bpl wait_for_vblank
    rts

nmi:
    inc frame_count
    rti

irq:
    rti

.segment "VECTORS"
    .word nmi, reset, irq

.segment "CHARS"
    .res 8192
