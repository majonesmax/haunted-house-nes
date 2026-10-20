; The full screens (docs/plan.md, step 6), as the remaster's NES look draws them: the story at power-on,
; the title (game select) with its mansion, moon and the eyes in the tower window, game over, the help,
; and the ending at dawn. Which one shows follows the game's state.
;
; A screen is drawn like a floor: a few rows a frame with the screen off (its picture from the extras
; bank, or blank), then its attributes, then its words. Its words are rows - the picture's row with the
; letters over it - and when they change (the game number, game over's words appearing, the story's next
; line) only those rows are sent again, two a frame.

SCREEN_PLAY = 0
SCREEN_TITLE = 1
SCREEN_GAME_OVER = 2
SCREEN_ENDING = 3
SCREEN_HELP = 4
SCREEN_STORY = 5
TITLE_TILES_BANK = 20     ; 1K banks: the title's tile set, then the ending's
ENDING_TILES_BANK = 24
WORD_SLOTS = 11
FULL_ROWS_PER_FRAME = 6
STRING_END = $FF
LIST_END = $FE
GAME_OVER_WORDS = 170     ; frames before game over's words appear (the remaster's)
ENDING_WORDS = 60
ENDING_VERDICT = 110
STORY_LINE_FRAMES = 45
STORY_LINES = 8
EYES_CLOSE = 90           ; game over: the eyes close...
LIGHT_FLICKER = 110       ; ...the window's light flickers...
LIGHT_OUT = 150           ; ...and goes out
TITLE_LOOK_FRAMES = 40
TITLE_LIGHTNING_EVERY = 330
TITLE_LIGHTNING_FRAMES = 4
FADE_FROM_LIGHT = 40      ; the ending fades in from the light at the door
WON_FRAMES = 240
WALK_START = 40           ; the ending: the eyes leave the door this many frames in...
WALK_SPEED = 115          ; ...0.45 px a frame (in 256ths)...
LOOK_BACK_AT = 172        ; ...stop here to look back...
LOOK_BACK_FRAMES = 60
REST_AT = 197             ; ...and rest at the end of the hill
WINDOW_EYES_X = 128       ; the eyes in the tower window: its middle
WINDOW_EYES_Y = 168
DOOR_X = 128              ; the front door's middle, where the eyes come out
GROUND_Y = 229            ; the eyes' middle, walking on the hill
MOON_X = 204              ; the moon's middle (the remaster's at 184, 52, twice its size)
MOON_Y = 73
SUN_X = 178               ; the sun's, behind the right wing
SUN_Y = 157
STORY_EYES_Y = 179
PRIORITY_BEHIND = $20     ; a sprite behind the background (the sun behind the mansion)

; Which screen this moment wants.
choose_screen:
    lda story_done
    bne @story_over
    lda #SCREEN_STORY
    jmp @chosen
@story_over:
    lda game_state
    cmp #GAME_SELECTING
    beq @selecting
    lda #0
    sta help_open
    lda #SCREEN_PLAY
    jmp @chosen
@selecting:
    lda flags
    and #WON_FLAG
    beq @not_won
    lda #SCREEN_ENDING
    jmp @chosen
@not_won:
    lda lives
    bne @not_over
    lda #SCREEN_GAME_OVER
    jmp @chosen
@not_over:
    lda help_open
    beq @title
    lda #SCREEN_HELP
    jmp @chosen
@title:
    lda #SCREEN_TITLE
@chosen:
    sta screen_wanted
    rts

; The NES's buttons besides the 2600's: any button ends the story (and does nothing else); B opens and
; closes the help on the title.
screen_buttons:
    lda pad
    eor pad_before
    and pad
    sta pad_pressed
    lda pad
    sta pad_before
    lda story_done
    bne @story_over
    lda pad_pressed
    beq @swallow
    inc story_done
@swallow:                 ; while the story shows, the game hears nothing
    lda #0
    sta stick
    sta button_down
    sta reset_down
    sta select_down
    rts
@story_over:
    lda pad_pressed
    and #PAD_B
    beq @done
    lda screen_shown
    cmp #SCREEN_TITLE
    beq @toggle
    cmp #SCREEN_HELP
    bne @done
@toggle:
    lda help_open
    eor #1
    sta help_open
@done:
    rts

; --- banks ---------------------------------------------------------------------------------------------
; The extras bank at $8000 while it's read, then the maps back. The NMI writes the bank register too; it
; puts back the value kept in bank_select, so an NMI between these two writes does no harm.
use_extras:
    lda #PROGRAM_BANK_8000
    sta bank_select
    sta BANK_SELECT
    lda #EXTRAS_BANK
    sta BANK_DATA
    rts

use_maps:
    lda #PROGRAM_BANK_8000
    sta bank_select
    sta BANK_SELECT
    lda #MAPS_BANK
    sta BANK_DATA
    rts

; --- a full screen, frame by frame ---------------------------------------------------------------------
prepare_full_screen:
    lda screen_wanted
    cmp screen_shown
    beq @same
    jmp start_full_screen
@same:
    lda drawing
    beq @live
    jmp continue_full_screen
@live:
    inc screen_frames
    bne @counted
    inc screen_frames + 1
@counted:
    jsr full_screen_triggers
    jsr send_dirty_slots
    jsr full_screen_palettes
    jsr full_screen_sprites
    lda #1
    sta render_ready
    rts

start_full_screen:
    sta screen_shown
    lda #1
    sta drawing
    lda #0
    sta screen_off
    sta full_row
    sta screen_frames
    sta screen_frames + 1
    sta queue_count
    sta slots_dirty
    sta slots_dirty + 1
    lda #$FF
    sta shown_floor       ; the play screen will need drawing again
    lda game_number
    sta shown_game
    lda #1                ; the story's first line is drawn with the screen
    sta story_lines_sent
    lda #DOOR_X           ; the ending's walk starts at the door
    sta walk_x + 1
    lda #0
    sta walk_x
    sta walk_pause
    lda #TITLE_TILES_BANK
    ldx screen_shown
    cpx #SCREEN_ENDING
    bne @set_found
    lda #ENDING_TILES_BANK
@set_found:
    sta background_bank
    jsr use_extras        ; the screen's colours, kept for every frame
    ldx #15
@colour:
    lda title_colours, x
    ldy screen_shown
    cpy #SCREEN_ENDING
    bne @kept
    lda ending_colours, x
@kept:
    sta screen_colours, x
    dex
    bpl @colour
    jmp use_maps

; With the screen off: its rows, then its attributes and words.
continue_full_screen:
    lda screen_off
    beq @done
    lda full_row
    cmp #NAMETABLE_ROWS
    bcs @rows_done
    ldx #FULL_ROWS_PER_FRAME
@row:
    txa
    pha
    lda full_row
    jsr base_row
    jsr write_word_row_now
    pla
    tax
    inc full_row
    lda full_row
    cmp #NAMETABLE_ROWS
    beq @done
    dex
    bne @row
@done:
    rts
@rows_done:                ; then a frame for the attributes, then the words a few at a time
    bne @words
    inc full_row
    lda #0
    sta words_written
    jsr start_help_page
    jmp write_screen_attributes
@words:
    jsr write_some_words
    bcc @not_yet
    lda #0
    sta drawing
    sta screen_off
    jmp full_screen_palettes
@not_yet:
    rts

; In: A = a nametable row. Out: word_row and word_tiles: the screen's picture on that row (blank for the
; help and the story).
base_row:
    sta word_row
    lda screen_shown
    cmp #SCREEN_HELP
    bcs @blank
    jsr use_extras
    lda word_row          ; the nametable: + row * 32
    sta map_pointer
    lda #0
    sta map_pointer + 1
    ldx #5
@times_32:
    asl map_pointer
    rol map_pointer + 1
    dex
    bne @times_32
    lda screen_shown
    cmp #SCREEN_ENDING
    beq @ending
    lda map_pointer
    clc
    adc #<title_nametable
    sta map_pointer
    lda map_pointer + 1
    adc #>title_nametable
    sta map_pointer + 1
    jmp @copy
@ending:
    lda map_pointer
    clc
    adc #<ending_nametable
    sta map_pointer
    lda map_pointer + 1
    adc #>ending_nametable
    sta map_pointer + 1
@copy:
    ldy #31
@tile:
    lda (map_pointer), y
    sta word_tiles, y
    dey
    bpl @tile
    jmp use_maps
@blank:
    ldy #31
    lda #0
@clear:
    sta word_tiles, y
    dey
    bpl @clear
    rts

; word_tiles straight to the PPU at word_row (the screen is off).
write_word_row_now:
    bit PPU_STATUS
    lda word_row          ; $2000 + row * 32
    lsr
    lsr
    lsr
    ora #$20
    sta PPU_ADDRESS
    lda word_row
    asl
    asl
    asl
    asl
    asl
    sta PPU_ADDRESS
    ldx #0
@tile:
    lda word_tiles, x
    sta PPU_DATA
    inx
    cpx #32
    bne @tile
    rts

; The attributes: the title's or the ending's picture's; the help's and the story's from their rows.
write_screen_attributes:
    lda screen_shown
    cmp #SCREEN_HELP
    bcs @pages
    jsr use_extras
    ldx #63
@copy:
    lda title_attributes, x
    ldy screen_shown
    cpy #SCREEN_ENDING
    bne @title
    lda ending_attributes, x
@title:
    sta screen_attributes, x
    dex
    bpl @copy
    jsr use_maps
    jmp @write
@pages:
    jsr page_attributes
@write:
    bit PPU_STATUS
    lda #$23
    sta PPU_ADDRESS
    lda #$C0
    sta PPU_ADDRESS
    ldx #0
@byte:
    lda screen_attributes, x
    sta PPU_DATA
    inx
    cpx #64
    bne @byte
    rts

; The story's and the help's attributes: white words (palette 0), grey ones (palette 3) by block row:
; the story's last block row (its hint) is grey; the help's grey except its headings'.
page_attributes:
    ldx #63
    lda #0
@clear:
    sta screen_attributes, x
    dex
    bpl @clear
    lda screen_shown
    cmp #SCREEN_STORY
    bne @help
    lda #14               ; the story's hint, rows 28-29
    jmp grey_block_row
@help:
    ldx #2                ; every block row grey from row 4 (the help's first heading is rows 2-3) ...
@grey:
    txa
    pha
    jsr grey_block_row
    pla
    tax
    inx
    cpx #14
    bne @grey
    lda #HELP_SECOND_HEADING / 2   ; ...but the second heading's
    jmp white_block_row

; In: A = a block row (16 px). Its blocks grey (palette 3).
grey_block_row:
    ldy #$FF
    jmp block_row_palette
; In: A = a block row. Its blocks white (palette 0).
white_block_row:
    ldy #0
; In: A = a block row, Y = $FF for palette 3 or 0 for palette 0.
block_row_palette:
    sty work_0
    tax
    lsr                   ; the attribute byte row: block row / 2; upper or lower half of each byte
    asl
    asl
    asl
    sta work_1
    txa
    and #1
    beq @upper
    lda #$F0
    jmp @mask_found
@upper:
    lda #$0F
@mask_found:
    sta work_2
    ldx #0
@byte:
    txa
    clc
    adc work_1
    tay
    lda work_2
    eor #$FF
    and screen_attributes, y
    sta work_3
    lda work_2
    and work_0
    ora work_3
    sta screen_attributes, y
    inx
    cpx #8
    bne @byte
    rts

; --- the words -----------------------------------------------------------------------------------------
; A few of the screen's word rows a frame (with the screen off). Out: carry set once they're all done.
WORDS_PER_FRAME = 3
write_some_words:
    lda screen_shown
    cmp #SCREEN_HELP
    bne @slots
    jmp write_some_help
@slots:
    lda #WORDS_PER_FRAME
    sta work_9
@slot:
    ldx words_written
    cpx #WORD_SLOTS
    bcs @all_done
    jsr compose_slot
    bcc @next
    jsr write_word_row_now
@next:
    inc words_written
    dec work_9
    bne @slot
    clc
    rts
@all_done:
    sec
    rts

; Mark word rows to send again when what they say changes.
full_screen_triggers:
    lda screen_shown
    cmp #SCREEN_TITLE
    bne @not_title
    lda game_number       ; another game chosen: its number and rules
    cmp shown_game
    beq @done
    sta shown_game
    lda #%11111000
    ora slots_dirty
    sta slots_dirty
    lda #%00000111
    ora slots_dirty + 1
    sta slots_dirty + 1
@done:
    rts
@not_title:
    cmp #SCREEN_GAME_OVER
    bne @not_game_over
    lda screen_frames + 1
    bne @done
    lda screen_frames
    cmp #GAME_OVER_WORDS
    bne @done
    lda #%00011110        ; the logo, the game, the matches used
    ora slots_dirty
    sta slots_dirty
    rts
@not_game_over:
    cmp #SCREEN_ENDING
    bne @story
    lda screen_frames + 1
    bne @done
    lda screen_frames
    cmp #ENDING_WORDS
    bne @verdict
    lda #%00011110
    ora slots_dirty
    sta slots_dirty
    rts
@verdict:
    cmp #ENDING_VERDICT
    bne @done
    lda #%01100000
    ora slots_dirty
    sta slots_dirty
    rts
@story:                   ; a line every 45 frames, then the hint
    cmp #SCREEN_STORY
    bne @done
    jsr story_lines_due
    cmp story_lines_sent
    beq @done
    tax
    sta story_lines_sent
    dex
    cpx #STORY_LINES
    bcs @story_hint
    lda bits, x
    ora slots_dirty
    sta slots_dirty
    rts
@story_hint:
    lda #1                ; the hint: slot 8
    ora slots_dirty + 1
    sta slots_dirty + 1
    rts

; Out: A = how many of the story's lines are due by now (one at once, then one each 45 frames; then 9,
; the hint).
story_lines_due:
    lda screen_frames
    sta work_0
    lda screen_frames + 1
    sta work_1
    ldx #1
@count:
    lda work_0
    sec
    sbc #STORY_LINE_FRAMES
    sta work_0
    lda work_1
    sbc #0
    sta work_1
    bcc @found
    inx
    cpx #(STORY_LINES + 1)
    bne @count
@found:
    txa
    rts

; Up to two marked word rows a frame, into the queue the NMI sends.
send_dirty_slots:
    lda #0
    sta queue_count
    ldx #0
@slot:
    cpx #8
    bcs @high
    lda slots_dirty
    and bits, x
    beq @next
    eor slots_dirty
    sta slots_dirty
    jmp @send
@high:
    lda slots_dirty + 1
    and bits - 8, x
    beq @next
    eor slots_dirty + 1
    sta slots_dirty + 1
@send:
    txa
    pha
    jsr compose_slot
    bcc @sent
    jsr queue_word_row
@sent:
    pla
    tax
    lda queue_count
    cmp #2
    beq @done
@next:
    inx
    cpx #WORD_SLOTS
    bne @slot
@done:
    rts

; word_row/word_tiles into the queue.
queue_word_row:
    lda queue_count
    asl
    asl
    asl
    asl
    asl                   ; * 32
    tay
    ldx #0
@tile:
    lda word_tiles, x
    sta queue_tiles, y
    iny
    inx
    cpx #32
    bne @tile
    ldx queue_count
    lda word_row
    sta queue_rows, x
    inc queue_count
    rts

; In: X = a slot. Out: carry set and word_row/word_tiles if this screen has it.
compose_slot:
    stx slot
    lda screen_shown
    cmp #SCREEN_ENDING
    beq @ending
    cmp #SCREEN_STORY
    beq @story
    cmp #SCREEN_HELP
    beq @none             ; the help's words are written with it, once
    jmp title_slot
@none:
    clc
    rts
@ending:
    jmp ending_slot
@story:
    jmp story_slot

; The title's (and game over's) words.
title_slot:
    lda slot
    bne @not_hint
    lda #1                ; the hint, row 1 (grey)
    jsr base_row
    lda #<title_hint
    ldx #>title_hint
    jsr put_centred
    sec
    rts
@not_hint:
    cmp #3
    bcs @not_logo
    clc                   ; the logo, rows 2 and 3
    adc #1
    jsr base_row
    jsr game_over_words_yet
    bcc @shown
    lda slot
    sec
    sbc #1                ; 0 the top half, 1 the bottom
    sta big_half
    lda #<logo_title
    ldx #>logo_title
    ldy screen_shown
    cpy #SCREEN_GAME_OVER
    bne @logo_found
    lda #<logo_game_over
    ldx #>logo_game_over
@logo_found:
    jsr put_big_centred
@shown:
    sec
    rts
@not_logo:
    bne @not_game
    lda #5                ; "GAME n", row 5
    jsr base_row
    jsr game_over_words_yet
    bcc @shown
    jsr game_line
    sec
    rts
@not_game:
    lda slot              ; rows 7-13: the game's rules, or game over's matches used
    clc
    adc #3
    jsr base_row
    lda screen_shown
    cmp #SCREEN_GAME_OVER
    beq @matches
    lda slot
    sec
    sbc #4
    jsr put_rule
    sec
    rts
@matches:
    lda slot
    cmp #4
    bne @shown
    jsr game_over_words_yet
    bcc @shown
    jsr matches_used_line
    sec
    rts

; Out: carry set if game over's words are due (always, on the title).
game_over_words_yet:
    lda screen_shown
    cmp #SCREEN_GAME_OVER
    bne @yes
    lda screen_frames + 1
    bne @yes
    lda screen_frames
    cmp #GAME_OVER_WORDS
    rts
@yes:
    sec
    rts

; The ending's words: the logo (rows 1-2), the game (4), the matches used (5), the verdict (6), the hint (7).
ending_slot:
    lda slot
    beq @none
    cmp #7
    bcs @none
    jsr base_row_for_ending_slot
    lda screen_frames + 1
    bne @due
    lda slot
    cmp #5
    bcs @late
    lda screen_frames
    cmp #ENDING_WORDS
    bcc @blank
    jmp @due
@late:
    lda screen_frames
    cmp #ENDING_VERDICT
    bcc @blank
@due:
    lda slot
    cmp #3
    bcs @not_logo
    sec
    sbc #1
    sta big_half
    lda #<logo_ending
    ldx #>logo_ending
    jsr put_big_centred
    sec
    rts
@not_logo:
    bne @not_game
    jsr with_the_urn_line
    sec
    rts
@not_game:
    cmp #4
    bne @not_matches
    jsr matches_line
    sec
    rts
@not_matches:
    cmp #5
    bne @hint
    jsr verdict_line
    sec
    rts
@hint:
    lda #<ending_hint
    ldx #>ending_hint
    jsr put_centred
@blank:
    sec
    rts
@none:
    clc
    rts

base_row_for_ending_slot:
    lda slot
    cmp #3
    bcs @after_logo
    jmp base_row          ; rows 1 and 2
@after_logo:
    clc
    adc #1                ; rows 4-7
    jmp base_row

; The story: its lines on rows 6, 8, ... 20, as they're due; the hint on row 28.
story_slot:
    lda slot
    cmp #STORY_LINES
    beq @hint
    bcs @none
    asl
    clc
    adc #6
    jsr base_row
    jsr story_lines_due
    cmp slot
    beq @blank
    bcc @blank
    lda slot              ; the slot-th line of story_lines
    jsr use_extras
    lda #<story_lines
    sta text_pointer
    lda #>story_lines
    sta text_pointer + 1
    lda slot
    jsr skip_lines
    jsr put_text_pointer_centred
    jsr use_maps
@blank:
    sec
    rts
@hint:
    lda #28
    jsr base_row
    jsr story_lines_due
    cmp #(STORY_LINES + 1)
    bcc @blank
    lda #<story_hint
    ldx #>story_hint
    jsr put_centred
    sec
    rts
@none:
    clc
    rts

; --- lines of words ------------------------------------------------------------------------------------
game_line:
    lda #<game_word       ; "GAME n", centred: the word at 13, the number at 18
    ldx #>game_word
    ldy #13
    jsr put_at
    lda game_number
    clc
    adc #1
    ldy #18
    jmp put_digit

; "MATCHES USED nn", centred.
matches_used_line:
    lda #<matches_used_words
    ldx #>matches_used_words
    ldy #8
    jsr put_at
    ldy #21
    jmp put_matches

; "WITH THE URN - GAME n"
with_the_urn_line:
    lda #<with_the_urn
    ldx #>with_the_urn
    ldy #5
    jsr put_at
    lda game_number
    clc
    adc #1
    ldy #25
    jmp put_digit

; "nn MATCHES USED" (or "1 MATCH USED")
matches_line:
    ldy #8
    jsr put_matches
    lda matches_used
    cmp #1
    bne @plural
    lda #<match_used
    ldx #>match_used
    ldy #11
    jmp put_at
@plural:
    lda #<matches_used_end
    ldx #>matches_used_end
    ldy #11
    jmp put_at

; The verdict for the matches used: the first line whose most isn't fewer (the remaster's guide.verdict).
verdict_line:
    jsr use_extras
    lda #<verdicts
    sta text_pointer
    lda #>verdicts
    sta text_pointer + 1
    jsr matches_number
    sta work_4
@verdict:
    ldy #0
    lda (text_pointer), y
    cmp work_4
    bcs @found
    jsr skip_one_line_after_byte
    jmp @verdict
@found:
    inc text_pointer
    bne @line
    inc text_pointer + 1
@line:
    jsr put_text_pointer_centred
    jmp use_maps

; In: A = which rule (0-6). The game's rule at column 1 (blank if it has fewer).
put_rule:
    sta work_4
    jsr use_extras
    lda game_number       ; the game's own rules (game_rules: where each game's start)
    asl
    tax
    lda game_rules, x
    sta text_pointer
    lda game_rules + 1, x
    sta text_pointer + 1
    lda work_4
@skip_rules:
    beq @rule_found
    pha
    ldy #0
    lda (text_pointer), y
    cmp #LIST_END
    beq @no_rule
    jsr skip_one_line
    pla
    sec
    sbc #1
    jmp @skip_rules
@no_rule:
    pla
    jmp use_maps
@rule_found:
    ldy #0
    lda (text_pointer), y
    cmp #LIST_END
    beq @done
    lda #1
    sta text_column
    jsr put_text_pointer
@done:
    jmp use_maps

; text_pointer past one $FF-ended line. Keeps X.
skip_one_line:
    ldy #0
@letter:
    lda (text_pointer), y
    iny
    cmp #STRING_END
    bne @letter
    tya
    clc
    adc text_pointer
    sta text_pointer
    bcc @done
    inc text_pointer + 1
@done:
    rts

skip_one_line_after_byte:
    inc text_pointer
    bne skip_one_line
    inc text_pointer + 1
    jmp skip_one_line

; In: A = how many lines to skip.
skip_lines:
    tax
    beq @done
@line:
    jsr skip_one_line
    dex
    bne @line
@done:
    rts

; --- putting letters on word_tiles ---------------------------------------------------------------------
; In: A/X = a string's address (low/high), Y = its column.
put_at:
    sta text_pointer
    stx text_pointer + 1
    sty text_column
    jmp put_text_pointer

; In: A/X = a string's address. Centred.
put_centred:
    sta text_pointer
    stx text_pointer + 1
put_text_pointer_centred:
    jsr text_length
    eor #$FF              ; column (32 - length) / 2
    sec
    adc #32
    lsr
    sta text_column
; The string at text_pointer at text_column.
put_text_pointer:
    ldy #0
    ldx text_column
@letter:
    lda (text_pointer), y
    cmp #STRING_END
    beq @done
    sta word_tiles, x
    inx
    iny
    cpx #32
    bcc @letter
@done:
    rts

; Out: A = the string at text_pointer's length.
text_length:
    ldy #0
@letter:
    lda (text_pointer), y
    cmp #STRING_END
    beq @done
    iny
    jmp @letter
@done:
    tya
    rts

; In: A = a digit, Y = its column.
put_digit:
    clc
    adc #DIGIT_ZERO
    sta word_tiles, y
    rts

; The matches used at column Y (no leading 0).
put_matches:
    lda matches_used
    lsr
    lsr
    lsr
    lsr
    beq @ones
    jsr put_digit
    iny
@ones:
    lda matches_used
    and #$0F
    jmp put_digit

; Out: A = the matches used as a number (they're kept as two decimal digits).
matches_number:
    lda matches_used
    lsr
    lsr
    lsr
    lsr
    tax
    lda #0
@tens:
    cpx #0
    beq @ones
    clc
    adc #10
    dex
    jmp @tens
@ones:
    sta work_5
    lda matches_used
    and #$0F
    clc
    adc work_5
    rts

; In: A/X = a string's address (of LOGO_LETTERS and spaces); big_half 0 or 1. Its big letters' top or
; bottom halves, centred: each letter two tiles wide.
put_big_centred:
    sta text_pointer
    stx text_pointer + 1
    jsr text_length
    asl                   ; two tiles a letter
    eor #$FF
    sec
    adc #32
    lsr
    tax
    ldy #0
@letter:
    lda (text_pointer), y
    cmp #STRING_END
    beq @done
    cmp #0                ; a space
    beq @space
    sty work_5
    jsr big_letter_number
    asl
    asl                   ; its four tiles: top left, top right, bottom left, bottom right
    clc
    adc #BIG_LETTERS
    ldy big_half
    beq @top
    clc
    adc #2
@top:
    sta word_tiles, x
    clc
    adc #1
    sta word_tiles + 1, x
    ldy work_5
@space:
    inx
    inx
    iny
    jmp @letter
@done:
    rts

; In: A = a letter's tile. Out: A = its place in the big letters (LOGO_LETTERS).
big_letter_number:
    ldy #0
@find:
    cmp logo_letter_tiles, y
    beq @found
    iny
    cpy #LOGO_LETTER_COUNT
    bne @find
    ldy #0
@found:
    tya
    rts

; --- the help page -------------------------------------------------------------------------------------
HELP_FIRST_ROW = 2
HELP_SECOND_HEADING = 10  ; (page_attributes keeps this row white)
start_help_page:
    lda #<help_lines
    sta help_pointer
    lda #>help_lines
    sta help_pointer + 1
    lda #HELP_FIRST_ROW
    sta help_row
    rts

; A few of the help's lines a frame. Out: carry set when it's all written (its hint last).
HELP_LINES_PER_FRAME = 4
write_some_help:
    jsr use_extras
    lda help_pointer
    sta text_pointer
    lda help_pointer + 1
    sta text_pointer + 1
    lda #HELP_LINES_PER_FRAME
    sta work_9
@line:
    ldy #0
    lda (text_pointer), y
    cmp #LIST_END
    beq @hint
    sta work_6            ; 1: a heading
    inc text_pointer
    bne @read
    inc text_pointer + 1
@read:
    lda work_6
    beq @plain
    lda help_row          ; a heading starts a block row, with a blank row after it
    and #1
    beq @aligned
    inc help_row
@aligned:
@plain:
    lda help_row
    jsr base_row
    jsr use_extras        ; (base_row's blank page doesn't switch, but be sure)
    lda #1
    sta text_column
    jsr put_text_pointer
    jsr write_word_row_now
    jsr skip_one_line
    inc help_row
    lda work_6
    beq @counted
    inc help_row
@counted:
    dec work_9
    bne @line
    lda text_pointer      ; more next frame
    sta help_pointer
    lda text_pointer + 1
    sta help_pointer + 1
    jsr use_maps
    clc
    rts
@hint:
    jsr use_maps
    lda #27
    jsr base_row
    lda #<help_hint
    ldx #>help_hint
    jsr put_centred
    jsr write_word_row_now
    sec
    rts

; --- colours and sprites -------------------------------------------------------------------------------
full_screen_palettes:
    ldx #15
@colour:
    lda screen_colours, x
    sta palette_buffer, x
    dex
    bpl @colour
    lda screen_shown
    cmp #SCREEN_ENDING
    beq @ending
    jsr title_lightning   ; the sky flashes now and then
    bcc @done
    lda #TITLE_FLASH
    sta palette_buffer
    rts
@ending:
    lda screen_frames + 1 ; it fades in from the light at the door
    bne @done
    lda screen_frames
    cmp #FADE_FROM_LIGHT
    bcs @done
    eor #$FF              ; rows lighter: (40 - frames) / 14, 0-2
    sec
    adc #FADE_FROM_LIGHT
    ldx #0
@rows:
    cmp #14
    bcc @rows_found
    sbc #14
    inx
    jmp @rows
@rows_found:
    txa
    jmp lighten_backgrounds
@done:
    rts

; Out: carry set on the title's lightning frames: 4 in every 330.
title_lightning:
    lda screen_frames
    sta work_0
    lda screen_frames + 1
    sta work_1
@modulo:
    lda work_0
    sec
    sbc #<TITLE_LIGHTNING_EVERY
    tax
    lda work_1
    sbc #>TITLE_LIGHTNING_EVERY
    bcc @found
    sta work_1
    stx work_0
    jmp @modulo
@found:
    lda work_0
    cmp #TITLE_LIGHTNING_FRAMES
    bcc @flash
    clc
    rts
@flash:
    sec
    rts

; In: A = rows. The background palettes that many palette rows lighter (black stays black), the way NES
; games fade to white.
lighten_backgrounds:
    sta work_2
    beq @done
    ldx #15
@colour:
    lda palette_buffer, x
    jsr lighter
    sta palette_buffer, x
    dex
    bpl @colour
@done:
    rts

; In: A = a colour, work_2 = rows. Out: A lighter by that many rows (up to the top row).
lighter:
    sta work_3
    and #$0F
    cmp #$0D
    bcs @black            ; hues $D-$F: black (and the greys there)
    lda work_3
    ldy work_2
@row:
    cmp #$30
    bcs @done
    clc
    adc #$10
    dey
    bne @row
@done:
    rts
@black:
    lda work_3
    rts

; The win at the door, in the play screen: it lightens as the game holds the moment.
won_lighten:
    lda game_state
    cmp #GAME_WON
    beq @won
    lda #0
    sta won_frames
    rts
@won:
    lda won_frames
    cmp #$FF
    beq @counted
    inc won_frames
@counted:
    lda won_frames        ; rows: frames / 80, up to 2
    ldx #0
@rows:
    cmp #80
    bcc @rows_found
    sbc #80
    inx
    cpx #2
    bne @rows
@rows_found:
    txa
    beq @done
    sta work_2
    ldx #31
@colour:
    lda palette_buffer, x
    jsr lighter
    sta palette_buffer, x
    dex
    bpl @colour
@done:
    rts

full_screen_sprites:
    lda #0                ; sprites anywhere on the screen
    sta sprites_from
    lda #239
    sta sprites_to
    lda #0
    sta oam_next
    sta oam_full
    sta draw_priority
    lda #KIND_EYES
    sta slot_kind
    lda #NO_KIND
    sta slot_kind + 1
    sta slot_kind + 2
    sta slot_kind + 3
    inc animation_clock
    lda screen_shown
    cmp #SCREEN_ENDING
    beq @ending
    cmp #SCREEN_STORY
    beq @story
    cmp #SCREEN_HELP
    beq @done
    jsr window_eyes
    jsr draw_moon
    jmp @done
@ending:
    jsr walking_eyes
    jsr dark_window
    jsr draw_sun
    jmp @done
@story:
    jsr story_eyes
@done:
    jsr hide_the_rest
    jmp compose_sprite_palettes

; In: A/X = a picture's address, Y = its kind; draw_centre_x, draw_centre_y set.
draw_at:
    sta draw_pointer
    stx draw_pointer + 1
    tya
    jsr choose_palette
    jmp draw_picture

; Sets draw_centre_x/y. In: A = x, X = y.
centre_at:
    sta draw_centre_x
    stx draw_centre_y
    lda #0
    sta draw_centre_y + 1
    sta draw_mirror
    rts

draw_moon:
    lda #MOON_X
    ldx #MOON_Y
    jsr centre_at
    lda #<picture_world_title_moon_2
    ldx #>picture_world_title_moon_2
    ldy #KIND_MOON
    jmp draw_at

draw_sun:
    lda #PRIORITY_BEHIND
    sta draw_priority
    lda #SUN_X
    ldx #SUN_Y
    jsr centre_at
    lda #<picture_sunrise_title_moon_2
    ldx #>picture_sunrise_title_moon_2
    ldy #KIND_SUN
    jsr draw_at
    lda #0
    sta draw_priority
    rts

; The title's eyes in the lit window, looking around and blinking; at game over they close, and the
; window's light flickers and goes out.
window_eyes:
    lda screen_shown
    cmp #SCREEN_GAME_OVER
    bne @looking
    lda screen_frames + 1
    bne @out
    lda screen_frames
    cmp #LIGHT_OUT
    bcs @out
    cmp #LIGHT_FLICKER
    bcc @lit
    sec                   ; flickering: lit or not, 4 frames a step
    sbc #LIGHT_FLICKER
    lsr
    lsr
    tax
    lda window_flicker, x
    beq @out
@lit:
    lda screen_frames
    cmp #EYES_CLOSE
    bcc @looking
    lda #LOOK_BLINK
    jmp @look_found
@out:
    jmp dark_window
@looking:
    lda screen_frames     ; blinking now and then
    and #127
    cmp #8
    bcs @not_blinking
    lda #LOOK_BLINK
    jmp @look_found
@not_blinking:
    lda screen_frames     ; else looking around: a look every 40 frames, from TITLE_LOOKS
    ldx #0
@look:
    cmp #TITLE_LOOK_FRAMES
    bcc @look_counted
    sbc #TITLE_LOOK_FRAMES
    inx
    cpx #6
    bne @look
    ldx #0
    jmp @look
@look_counted:
    lda title_looks, x
@look_found:
    asl
    tax
    lda eyes_pictures, x
    pha
    lda eyes_pictures + 1, x
    pha
    lda #WINDOW_EYES_X
    ldx #WINDOW_EYES_Y
    jsr centre_at
    pla
    tax
    pla
    ldy #KIND_EYES
    jsr draw_at
    lda #<picture_patch_16x8   ; the dark room behind them
    ldx #>picture_patch_16x8
    ldy #KIND_EYES
    jmp draw_at

dark_window:
    lda #WINDOW_EYES_X
    ldx #WINDOW_EYES_Y
    jsr centre_at
    lda #<picture_patch_18x12
    ldx #>picture_patch_18x12
    ldy #KIND_EYES
    jmp draw_at

; The story: the eyes below the words, blinking now and then.
story_eyes:
    lda #128
    ldx #STORY_EYES_Y
    jsr centre_at
    lda animation_clock
    and #127
    cmp #6
    bcs @open
    lda #<picture_eyes_blink
    ldx #>picture_eyes_blink
    jmp @draw
@open:
    lda #<picture_eyes_centre
    ldx #>picture_eyes_centre
@draw:
    ldy #KIND_EYES
    jmp draw_at

; The ending: from the front door the eyes walk down the hill to the right with the whole urn, stop to
; look back at the house, and go on to the end of the hill.
walking_eyes:
    jsr walk_position
    lda walk_x + 1
    ldx #GROUND_Y
    jsr centre_at
    lda walk_bob
    beq @level
    dec draw_centre_y
@level:
    lda walk_looking_back
    beq @right
    lda #<picture_eyes_left
    ldx #>picture_eyes_left
    jmp @eyes
@right:
    lda #<picture_eyes_right
    ldx #>picture_eyes_right
@eyes:
    ldy #KIND_EYES
    jsr draw_at
    lda draw_centre_x     ; the urn beside them
    clc
    adc #15
    sta draw_centre_x
    lda #<picture_urn8_0
    ldx #>picture_urn8_0
    ldy #KIND_URN
    jmp draw_at

; walk_x (8.8 px), walk_looking_back, walk_bob from screen_frames.
walk_position:
    lda #0
    sta walk_looking_back
    sta walk_bob
    lda screen_frames + 1
    bne @going
    lda screen_frames
    cmp #WALK_START
    bcs @going
    lda #DOOR_X           ; still at the door
    sta walk_x + 1
    lda #0
    sta walk_x
    rts
@going:
    lda walk_x + 1
    cmp #REST_AT
    bcs @resting
    cmp #LOOK_BACK_AT
    bne @step
    lda walk_pause        ; looking back for a while
    cmp #LOOK_BACK_FRAMES
    bcs @step
    inc walk_pause
    inc walk_looking_back
    rts
@step:
    lda walk_x
    clc
    adc #WALK_SPEED
    sta walk_x
    bcc @bob
    inc walk_x + 1
@bob:
    lda screen_frames
    and #8
    sta walk_bob
@resting:
    rts

.segment "RODATA"
title_hint:       .byte "SELECT GAME   START   B HELP", STRING_END
ending_hint:      .byte "SELECT GAME  START PLAY", STRING_END
story_hint:       .byte "PRESS ANY BUTTON", STRING_END
help_hint:        .byte "B GOES BACK", STRING_END
logo_title:       .byte "HAUNTED HOUSE", STRING_END
logo_game_over:   .byte "GAME OVER", STRING_END
logo_ending:      .byte "YOU ESCAPED!", STRING_END
game_word:        .byte "GAME", STRING_END
matches_used_words: .byte "MATCHES USED", STRING_END
with_the_urn:     .byte "WITH THE URN - GAME", STRING_END
matches_used_end: .byte "MATCHES USED", STRING_END
match_used:       .byte "MATCH USED", STRING_END
logo_letter_tiles: .byte "HAUNTEDOSGMVRYCP!"   ; LOGO_LETTERS, as the font's tiles
LOGO_LETTER_COUNT = 17
title_looks:      .byte LOOK_CENTRE, LOOK_LEFT, LOOK_CENTRE, LOOK_RIGHT, LOOK_UP, LOOK_CENTRE
window_flicker:   .byte 1, 0, 1, 1, 0, 1, 0, 0, 1, 0   ; the light, 4 frames a step, as it fails
.segment "CODE"
