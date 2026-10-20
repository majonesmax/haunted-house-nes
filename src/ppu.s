; The board and the picture chip: the MMC3's banks, what's sent to the PPU in each vertical blank, and the
; two scanline interrupts that split the screen (docs/plan.md, "The picture"):
;   lines 0-39     the status band     - the second nametable, from its top
;   lines 40-199   the view            - the first nametable, scrolled to the floor around the eyes
;   lines 200-239  the band below      - the second nametable again, from line 200

PPU_SCROLL   = $2005
PPU_ADDRESS  = $2006
PPU_DATA     = $2007
OAM_ADDRESS  = $2003
OAM_DMA      = $4014
BANK_SELECT  = $8000      ; the MMC3's registers
BANK_DATA    = $8001
MIRRORING    = $A000
IRQ_LATCH    = $C000
IRQ_RELOAD   = $C001
IRQ_OFF      = $E000
IRQ_ON       = $E001
CONTROL_STATUS = $A1      ; NMI on, 8x16 sprites, background tiles at $0000, the second nametable
CONTROL_VIEW   = $A0      ; ...the first nametable
CONTROL_DRAWING = $80     ; NMI on, VRAM address +1 a write (while a whole floor is drawn)
RENDER_ON    = $1E        ; background and sprites, both in the leftmost 8 pixels too
VIEW_TOP_LINE = 40
VIEW_HEIGHT  = 160
BELOW_TOP_LINE = 197      ; (three lines above row 25, so the hints' top line clears the view)
SPRITE_TILES_BANK = FLOOR_COUNT * 4   ; the sprites' 4K, after the floors' (1K banks)
MAPS_BANK = 0             ; program banks (src/mmc3.cfg)
EXTRAS_BANK = 2
PROGRAM_BANK_8000 = 6     ; the MMC3's register for the bank at $8000...
PROGRAM_BANK_A000 = 7     ; ...and at $A000 (MUSIC_BANK, from sound.inc, is the music's first bank)
OAM          = $0200

.segment "CODE"

; The MMC3 at power-on: the program's banks in order, the sprites' tiles, vertical mirroring, no interrupt.
set_up_board:
    ldx #0
@bank:
    stx BANK_SELECT
    lda power_on_banks, x
    sta BANK_DATA
    inx
    cpx #8
    bne @bank
    lda #0
    sta MIRRORING         ; vertical: the two nametables side by side
    sta IRQ_OFF
    lda #$FF
    sta shown_floor
    rts

; The screen's tile set for the background (2K + 2K at $0000): a floor's, the title's or the ending's.
; Then the bank register back as the main loop left it (screens.s, use_extras).
set_floor_tiles:
    lda background_bank
    ldx #0
    stx BANK_SELECT
    sta BANK_DATA
    clc
    adc #2
    ldx #1
    stx BANK_SELECT
    sta BANK_DATA
    lda bank_select
    sta BANK_SELECT
    rts

nmi:
    pha
    txa
    pha
    tya
    pha
    inc frame_count
    inc frame_started
    lda busy
    beq @on_time
    inc late_frames
    lda work_part
    sta late_part
@on_time:
    lda drawing
    beq @picture
    lda #0                ; a whole floor being drawn: keep the screen off and leave the PPU alone
    sta PPU_MASK
    lda #1
    sta screen_off
    jmp @done
@picture:
    lda render_ready
    beq @scroll
    lda #0
    sta OAM_ADDRESS
    lda #>OAM
    sta OAM_DMA
    jsr send_palettes
    lda screen_shown
    bne @full_screen_sends
    jsr send_row
    jsr send_attributes
    jsr send_status
    jsr send_word_rows    ; (the hints' rows, one a frame, never with a floor row: see hints.s)
    jmp @sent
@full_screen_sends:
    jsr send_word_rows
@sent:
    lda #0
    sta render_ready
@scroll:
    jsr set_floor_tiles
    lda #RENDER_ON
    sta PPU_MASK
    bit PPU_STATUS
    lda screen_shown
    beq @split
    lda #CONTROL_VIEW     ; a full screen: the first nametable, no splits
    sta PPU_CONTROL
    lda #0
    sta PPU_SCROLL
    sta PPU_SCROLL
    sta IRQ_OFF
    jmp @done
@split:
    lda #CONTROL_STATUS   ; the status band: the second nametable, from its top
    sta PPU_CONTROL
    lda #0
    sta PPU_SCROLL
    sta PPU_SCROLL
    sta irq_stage
    sta IRQ_OFF
    lda #VIEW_TOP_LINE    ; the interrupt comes near the end of line 39; the change waits for the
    sta IRQ_LATCH         ; horizontal blank, so the view starts a line late, at 41 - unseen, and clean
    sta IRQ_RELOAD
    sta IRQ_ON
@done:
    pla
    tay
    pla
    tax
    pla
    rti

; The splits. Changing the scroll in the middle of the picture takes the PPU address register: the
; nametable, then the y, then the x, then the address's low byte (worked out ahead in split_low).
irq:
    pha
    sta IRQ_OFF           ; acknowledge
    lda irq_stage
    bne @below
    lda #0                ; the view: the first nametable at scroll_y
    sta PPU_ADDRESS
    lda scroll_y
    sta PPU_SCROLL
    lda #0
    sta PPU_SCROLL
    jsr wait_for_line_end ; the last write takes effect at once: in the horizontal blank, not mid-line
    lda split_low
    sta PPU_ADDRESS
    lda #(VIEW_HEIGHT - 2)   ; 160 lines of view, 41-200
    sta IRQ_LATCH
    sta IRQ_RELOAD
    sta IRQ_ON
    inc irq_stage
    pla
    rti
@below:
    lda #4                ; the band below: the second nametable at line 200
    sta PPU_ADDRESS
    lda #BELOW_TOP_LINE
    sta PPU_SCROLL
    lda #0
    sta PPU_SCROLL
    jsr wait_for_line_end
    lda #((BELOW_TOP_LINE & $F8) << 2) & $FF
    sta PPU_ADDRESS
    pla
    rti

SPLIT_WAIT = 10           ; loops (5 cycles each): from the interrupt to the next horizontal blank
wait_for_line_end:
    txa
    pha
    ldx #SPLIT_WAIT
@wait:
    dex
    bne @wait
    pla
    tax
    rts

; --- what's sent in the vertical blank -------------------------------------------------------------------
send_palettes:
    lda #$3F
    sta PPU_ADDRESS
    lda #$00
    sta PPU_ADDRESS
    ldx #0
@colour:
    lda palette_buffer, x
    sta PPU_DATA
    inx
    cpx #32
    bne @colour
    rts

send_row:
    lda row_waiting
    beq @done
    lda row_address + 1
    sta PPU_ADDRESS
    lda row_address
    sta PPU_ADDRESS
    ldx #0
@tile:
    lda row_buffer, x
    sta PPU_DATA
    inx
    cpx #VIEW_COLUMNS
    bne @tile
    lda #0
    sta row_waiting
@done:
    rts

send_attributes:
    ldy #0
@next:
    cpy changed_count
    beq @done
    lda #$23              ; the first nametable's attributes: $23C0-$23FF
    sta PPU_ADDRESS
    lda changed_index, y
    ora #$C0
    sta PPU_ADDRESS
    lda changed_value, y
    sta PPU_DATA
    iny
    jmp @next
@done:
    rts

; Word rows (screens.s, hints.s): each row's 32 tiles, in the nametable at queue_pages ($20 or $24).
; (The NMI keeps to its own bytes: the main loop's work_ bytes may be in use when it comes.)
send_word_rows:
    ldx #0
    ldy #0
@row:
    cpx queue_count
    beq @done
    lda queue_rows, x     ; the page + row * 32
    lsr
    lsr
    lsr
    ora queue_pages, x
    sta PPU_ADDRESS
    lda queue_rows, x
    asl
    asl
    asl
    asl
    asl
    sta PPU_ADDRESS
    lda #32
    sta nmi_count
@tile:
    lda queue_tiles, y
    sta PPU_DATA
    iny
    dec nmi_count
    bne @tile
    inx
    jmp @row
@done:
    lda #0
    sta queue_count
    rts

send_status:
    ldx #0
@next:
    cpx status_count
    beq @done
    lda status_address_high, x
    sta PPU_ADDRESS
    lda status_address_low, x
    sta PPU_ADDRESS
    lda status_tile, x
    sta PPU_DATA
    inx
    jmp @next
@done:
    rts

.segment "RODATA"
power_on_banks:           ; R0-R7: background 2K + 2K, sprites 1K x 4, program 8K x 2 (the maps, the music)
    .byte 0, 2, SPRITE_TILES_BANK, SPRITE_TILES_BANK + 1, SPRITE_TILES_BANK + 2, SPRITE_TILES_BANK + 3
    .byte MAPS_BANK, MUSIC_BANK
.segment "CODE"
