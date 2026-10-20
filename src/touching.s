; Touching (spec, "Touching"): on the 2600 the hardware noted where the sprite overlapped the eyes or the
; walls as it drew the picture. Here the same comes out of the rule for what each line shows:
;   its first scanline:   the eyes' row for this line, the sprite's row for the line above
;   its second scanline:  both rows for this line
; The first line drawn shows no eyes and no sprite on its first scanline; the last has no second. Only
; the lines with sprite rows are walked, and each line's walls are worked out once, for both scanlines.

find_touches:
    lda #0
    sta touched_eyes
    sta touched_walls
    lda sprite_height
    beq @done
    jsr build_eyes
    jsr drawn_lines
    jsr start_walls
    lda sprite_line       ; from the line below the sprite's bottom row to its top row
    sec
    sbc #1
    sta wall_line
    lda sprite_height
    clc
    adc #1
    sta touch_lines_left
@line:
    jsr test_line
    inc wall_line
    dec touch_lines_left
    bne @line
@done:
    rts

; One line (wall_line), if it's drawn: its first scanline (unless it's the first line drawn), its second
; (unless it's the last).
test_line:
    lda wall_line
    cmp #$80              ; below line 0 (wrapped)
    bcs @done
    cmp line_top
    beq @drawn
    bcs @done
@drawn:
    cmp line_below
    beq @done
    bcc @done
    lda wall_line         ; the first scanline: the row of the line above, unless this is the top line
    cmp line_top
    beq @second
    clc
    adc #1
    jsr sprite_row_on
    jsr test_scanline
@second:
    lda wall_line         ; the second scanline: this line's row, unless the next line down isn't drawn
    sec
    sbc #1
    cmp line_below
    beq @done
    lda wall_line
    jsr sprite_row_on
    jmp test_scanline
@done:
    rts

; In: A = a line. Out: A = the sprite's row drawn on it, or 0.
sprite_row_on:
    sec
    sbc sprite_line
    cmp sprite_height
    bcs @none
    clc
    adc sprite_pointer
    tay
    lda shapes, y
    rts
@none:
    lda #0
    rts

; In: A = the sprite's row on a scanline of wall_line. Notes what it touches.
test_scanline:
    beq @done
    sta touch_row
    lda touched_eyes
    bne @walls
    lda wall_line         ; the first line drawn shows no eyes
    cmp line_top
    beq @walls
    jsr eyes_row_on
    beq @walls
    sta eyes_now
    jsr rows_overlap
@walls:
    lda drop_tries        ; only the drop search asks about the walls
    beq @done
    lda touched_walls
    bne @done
    jmp row_hits_wall
@done:
    rts

; The eyes' three rows, bottom first: two eyes in each, and in one row the pupils, looking the way the
; stick is pushed this frame.
build_eyes:
    lda #eyes_row
    sta eyes_rows
    sta eyes_rows + 1
    sta eyes_rows + 2
    ldy #1                ; the pupils' row: the middle one...
    lda stick
    and #STICK_DOWN
    beq @not_down
    dey                   ; ...the bottom one looking down...
@not_down:
    lda stick
    and #STICK_UP
    beq @not_up
    iny                   ; ...the top one looking up
@not_up:
    lda #pupils_ahead
    ldx stick
    bpl @not_right        ; bit 7: right
    lda #pupils_right
@not_right:
    pha
    txa
    and #STICK_LEFT
    beq @pupils_found
    pla
    lda #pupils_left      ; left wins
    pha
@pupils_found:
    pla
    sta eyes_rows, y
    rts

; The lines drawn: 79 down to 1, or with a match lit in games 2-9, outside a doorway, only the room's.
drawn_lines:
    lda #TOP_LINE
    sta line_top
    lda #0
    sta line_below
    lda flags
    and #MATCH_LIT
    beq @done
    bit doorway
    bmi @done
    lda game_number
    beq @done
    lda room_bottom
    beq @top
    jsr line_of
    cmp #$80
    bcs @top
    sta line_below
@top:
    lda room_top
    beq @done
    jsr line_of
    cmp #VIEW_LINES
    bcs @done
    sta line_top
@done:
    rts

; In: A = a line. Out: A = the eyes' row drawn on it, or 0.
eyes_row_on:
    sec
    sbc eyes_line
    cmp #3
    bcs @none
    tay
    lda eyes_rows, y
    rts
@none:
    lda #0
    rts

; Does touch_row (at sprite_x) overlap eyes_now (at player_x)? Columns line up when the eyes' row is
; shifted by the difference in x.
rows_overlap:
    lda sprite_x
    sec
    sbc player_x
    cmp #8
    bcc @sprite_to_the_right
    cmp #$F9
    bcs @sprite_to_the_left
    rts
@sprite_to_the_right:
    tay
    lda eyes_now
@shift_left:
    dey
    bmi @compare
    asl
    jmp @shift_left
@sprite_to_the_left:
    eor #$FF              ; how far to the left
    clc
    adc #1
    tay
    lda eyes_now
@shift_right:
    lsr
    dey
    bne @shift_right
@compare:
    and touch_row
    beq @done
    lda #1
    sta touched_eyes
@done:
    rts

; touch_row as 16 columns from touch_column: touch_wide_high, touch_wide_low (bit 7 of high is leftmost).
; Stretched, each pixel twice: four at a time, from a table.
spread_row:
    lda sprite_wide
    bne @stretch
    lda touch_row
    sta touch_wide_high
    lda #0
    sta touch_wide_low
    rts
@stretch:
    lda touch_row
    lsr
    lsr
    lsr
    lsr
    tax
    lda stretched, x
    sta touch_wide_high
    lda touch_row
    and #$0F
    tax
    lda stretched, x
    sta touch_wide_low
    rts

; The sprite's first column on screen (a stretched sprite starts a pixel to the right, as the TIA does).
start_walls:
    lda #$FF
    sta walls_line        ; no line's walls worked out yet
    sta walls_row         ; nor any wall row's
    lda sprite_x
    ldx sprite_wide
    beq @found
    clc
    adc #1
@found:
    sta touch_column
    rts

; Does touch_row, on wall_line, overlap a wall?
row_hits_wall:
    lda wall_line
    cmp walls_line
    beq @compare
    jsr line_walls
@compare:
    lda walls_on_line
    beq @done             ; not on the floor
    jsr spread_row
    lda touch_wide_high
    and walls_high
    bne @hit
    lda touch_wide_low
    and walls_low
    bne @hit
@done:
    rts
@hit:
    lda #1
    sta touched_walls
    rts

; The walls in the 16 columns from touch_column on wall_line, as walls_high/walls_low (bit 7 of high is
; leftmost): the two wall cells those columns cross - the first's columns up to the boundary, then the
; second's - and in the middle row, the strips at the screen's sides instead of the cells outside the plan.
line_walls:
    sta walls_line
    lda #0
    sta walls_on_line
    lda wall_line         ; the floor y: wall_line - eyes_line + player_y, if it's on the floor at all
    sec
    sbc eyes_line
    tax
    lda #0
    sbc #0                ; the borrow as a high byte: $FF if negative
    sta touch_count
    txa
    clc
    adc player_y
    sta touch_y
    lda touch_count
    adc #0
    bne @done             ; not between 0 and 255
    inc walls_on_line
    lda touch_y
    lsr
    lsr
    lsr
    lsr
    sta touch_wall_row
    cmp walls_row         ; the walls change only from one wall row (16 units) to the next
    beq @done
    sta walls_row
    lda #0
    sta walls_high
    sta walls_low
    lda touch_column      ; the first cell's columns: 16 - (column mod 16)
    and #15
    tax
    lda first_cell_high, x
    sta touch_mask_high
    lda first_cell_low, x
    sta touch_mask_low
    lda touch_column
    jsr cell_is_wall
    bcc @second
    lda touch_mask_high
    sta walls_high
    lda touch_mask_low
    sta walls_low
@second:
    lda touch_column
    clc
    adc #15
    jsr cell_is_wall
    bcc @strips
    lda touch_mask_high   ; the rest of the 16 columns
    eor #$FF
    ora walls_high
    sta walls_high
    lda touch_mask_low
    eor #$FF
    ora walls_low
    sta walls_low
@strips:
    lda touch_wall_row
    cmp #MIDDLE_ROW
    bne @done
    jsr edge_strips
@done:
    rts

; In: A = a column; touch_wall_row, touch_y. Out: carry set if its wall cell is wall. Outside the plan's
; columns that's every row but the middle one (where only the strips are, added separately).
cell_is_wall:
    tax
    lsr
    lsr
    lsr
    lsr
    sec
    sbc #1
    and #$08
    beq @plan
    lda touch_wall_row
    cmp #MIDDLE_ROW
    beq @open
    sec
    rts
@open:
    clc
    rts
@plan:
    txa
    ldy touch_y
    jmp wall_at

; The middle row's strips: columns 0-3 and 156-159, where they fall in the 16 from touch_column.
; first_cell_high/low[m] has the first 16 - m of the 16 columns set.
edge_strips:
    lda touch_column
    cmp #EDGE_STRIP
    bcs @right
    clc                   ; the first 4 - column columns: index 16 - (4 - column) = 12 + column
    adc #(16 - EDGE_STRIP)
    tax
    lda first_cell_high, x
    ora walls_high
    sta walls_high
    lda first_cell_low, x
    ora walls_low
    sta walls_low
@right:
    lda touch_column      ; the columns from 156 - column on: all but the first (156 - column), i.e. the
    cmp #(SCREEN_WIDTH - EDGE_STRIP - 15)   ; inverse of index 16 - (156 - column) = column - 140
    bcc @done
    sec
    sbc #(SCREEN_WIDTH - EDGE_STRIP - 16)
    tax
    lda first_cell_high, x
    eor #$FF
    ora walls_high
    sta walls_high
    lda first_cell_low, x
    eor #$FF
    ora walls_low
    sta walls_low
@done:
    rts
