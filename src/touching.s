; Touching (spec, "Touching"): on the 2600 the hardware noted where the sprite overlapped the eyes or the
; walls as it drew the picture. Here the same comes out of the rule for what shows on each scanline:
;   first scanline of a line:  the eyes' row for this line, the sprite's row for the line above
;   second scanline:           both rows for this line
; The first line drawn shows no eyes and no sprite on its first scanline; the last has no second scanline.
; So each of the sprite's rows, on line L, can touch on L's second scanline and on the first scanline of
; L - 1 - only those are tested, not every line.

find_touches:
    lda #0
    sta touched_eyes
    sta touched_walls
    lda sprite_height
    beq @done
    jsr build_eyes
    jsr drawn_lines
    lda #0
    sta touch_k
@row:
    lda touch_k
    jsr sprite_row
    beq @next_row
    sta touch_row
    lda sprite_line
    clc
    adc touch_k
    sta sprite_row_line
    jsr second_scanline
    jsr first_scanline_below
@next_row:
    inc touch_k
    lda touch_k
    cmp sprite_height
    bne @row
@done:
    rts

; The row on its own line's second scanline: if the line is drawn and isn't the last.
second_scanline:
    lda sprite_row_line
    cmp line_top
    beq @drawn
    bcs @done             ; above the lines drawn (or wrapped round below 0)
@drawn:
    cmp line_below
    beq @done
    bcc @done
    sec
    sbc #1
    cmp line_below        ; the last line drawn has no second scanline
    beq @done
    lda sprite_row_line
    jmp test_line
@done:
    rts

; The row on the first scanline of the line below: if that line is drawn and isn't the first.
first_scanline_below:
    lda sprite_row_line
    beq @done
    sec
    sbc #1
    cmp line_top
    bcs @done
    cmp line_below
    beq @done
    bcc @done
    jmp test_line
@done:
    rts

; In: A = a line, touch_row = the sprite's row shown on it. Notes what it touches.
test_line:
    sta wall_line
    cmp line_top          ; the first line drawn shows no eyes
    beq @walls
    lda touched_eyes
    bne @walls
    lda wall_line
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

; In: A = a row number. Out: A = that row of the sprite's shape.
sprite_row:
    clc
    adc sprite_pointer
    tay
    lda shapes, y
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

; Does touch_row, on wall_line, overlap a wall? A row covers at most 16 columns, so at most two wall cells:
; one wall test for each, then the row's pixels against them. (A stretched sprite has each pixel twice and
; starts a pixel to the right, as the TIA does.) In the middle row near the screen's sides, where the
; edge strips are, each pixel is tested on its own instead.
row_hits_wall:
    lda wall_line         ; the floor y: wall_line - eyes_line + player_y, if it's on the floor at all
    sec
    sbc eyes_line
    tax                   ; keep the borrow in the carry...
    lda #0
    sbc #0                ; ...as a high byte: $FF if negative
    sta touch_count
    txa
    clc
    adc player_y
    sta touch_y
    lda touch_count
    adc #0
    bne @done             ; not between 0 and 255
    jsr spread_row
    lda sprite_x
    ldx sprite_wide
    beq @start_found
    clc
    adc #1
@start_found:
    sta touch_column
    lda touch_y
    lsr
    lsr
    lsr
    lsr
    cmp #MIDDLE_ROW
    bne @by_cells
    lda touch_column
    cmp #EDGE_STRIP
    bcc @by_pixels
    cmp #(SCREEN_WIDTH - EDGE_STRIP - 15)
    bcs @by_pixels
@by_cells:
    jmp row_hits_wall_cells
@by_pixels:
    jmp row_hits_wall_pixels
@done:
    rts

; touch_row as 16 columns from touch_column: touch_wide_high, touch_wide_low (bit 7 of high is leftmost).
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
    sta touch_pixels
    ldx #8
@pixel:
    asl touch_pixels
    php
    rol touch_wide_low    ; each pixel twice
    rol touch_wide_high
    plp
    rol touch_wide_low
    rol touch_wide_high
    dex
    bne @pixel
    rts

; The two cells' walls as a 16-column mask - the columns before the cell boundary from the first, the
; rest from the second - against the row.
row_hits_wall_cells:
    lda touch_column      ; columns in the first cell: 16 - (column mod 16), 1-16
    and #15
    tax
    lda first_cell_high, x
    sta touch_mask_high
    lda first_cell_low, x
    sta touch_mask_low
    lda touch_column
    ldy touch_y
    jsr wall_at
    bcs @first_is_wall
    lda #0                ; the first cell is open: drop its columns from the mask
    sta touch_first_cell_high
    sta touch_first_cell_low
    jmp @second
@first_is_wall:
    lda touch_mask_high
    sta touch_first_cell_high
    lda touch_mask_low
    sta touch_first_cell_low
@second:
    lda touch_column
    clc
    adc #15
    ldy touch_y
    jsr wall_at
    bcc @compare
    lda touch_mask_high   ; the second cell is wall: its columns too
    eor #$FF
    ora touch_first_cell_high
    sta touch_first_cell_high
    lda touch_mask_low
    eor #$FF
    ora touch_first_cell_low
    sta touch_first_cell_low
@compare:
    lda touch_wide_high
    and touch_first_cell_high
    bne @hit
    lda touch_wide_low
    and touch_first_cell_low
    bne @hit
    rts
@hit:
    lda #1
    sta touched_walls
    rts

; Each lit pixel tested on its own (near the edge strips).
row_hits_wall_pixels:
    lda #16
    sta touch_count
@pixel:
    asl touch_wide_low
    rol touch_wide_high
    bcc @next
    lda touch_column
    jsr wall_pixel
    bcs @hit
@next:
    inc touch_column
    dec touch_count
    bne @pixel
    rts
@hit:
    lda #1
    sta touched_walls
    rts

; In: A = a screen column; touch_y = the floor y. Out: carry set if a wall is drawn there: the wall plan,
; and in the middle row a strip at each side of the screen.
wall_pixel:
    cmp #EDGE_STRIP
    bcc @edge
    cmp #(SCREEN_WIDTH - EDGE_STRIP)
    bcs @edge
@plan:
    ldy touch_y
    jmp wall_at
@edge:
    tax
    lda touch_y
    lsr
    lsr
    lsr
    lsr
    cmp #MIDDLE_ROW
    beq @strip
    txa
    jmp @plan
@strip:
    sec
    rts
