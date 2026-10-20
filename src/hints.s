; The remaster's hints (its game/hints.py), in the band under the view: B during play says what you need
; next and which way - the nearest piece of the urn (up or down the stairs, or which way across the floor),
; how to take it once you're in its room, and with the whole urn in hand, the way out. Two notes come by
; themselves: when the urn becomes whole, and when taking something puts down what you held.
;
; Nothing here touches the game's state; it only reads it. A hint is a list of parts (strings) for each
; of three lines, worked out at once; the lines are made and sent one a frame, in frames with nothing
; else much for the NMI to send. After HINT_TIME the floor's name comes back the same way. The hints'
; words are in the extras bank; the floor's name is in the maps'.

HINT_FIRST_ROW = 25       ; the band's rows 25-27 (row 26 holds the floor's name)
HINT_LINES = 3
HINT_TIME = 180           ; in frames of 2: six seconds, as the remaster's
PARTS_PER_LINE = 4        ; (two bytes each: a line takes 8 bytes of hint_parts)
URN_PIECES = 3
MOST_STATUS_SENDS = 2     ; a hint row goes in a frame with no floor row, no light change and few others
THING_KEY = 0             ; what a held item is called: hint_things
THING_SCEPTER = 1
THING_PIECE = 2
THING_URN = 3

.macro part text
    lda #<text
    ldx #>text
    jsr add_part
.endmacro

; Each frame, after the picture is prepared.
hints_frame:
    lda screen_wanted
    ora screen_shown
    bne @full_screen
    jsr notes
    jsr cheat_note
    lda hint_asked
    beq @asked
    jsr start_spec
    jsr choose_hint
    jsr show_spec
@asked:
    lda drawing
    bne @drawing
    jsr hint_timing
    jsr send_hint_row
    jmp remember_held
@drawing:                 ; a floor being drawn writes its name over the band: send it all again after
    lda hint_timer
    ora hint_rows_left
    beq @remember
    lda #HINT_LINES
    sta hint_rows_left
    jmp remember_held
@full_screen:             ; another screen: the band's own words go back after
    lda hint_timer
    ora hint_rows_left
    beq @remember
    lda #0
    sta hint_timer
    sta hint_rows_left
    lda #1
    sta hint_restore_due
@remember:
    jmp remember_held

; The hint's time, then the band put back.
hint_timing:
    lda hint_rows_left
    bne @done             ; (its time starts once it's all on screen)
    lda hint_timer
    beq @put_back
    lda clock
    lsr
    bcc @done
    dec hint_timer
    bne @done
    lda #1
    sta hint_restore_due
@put_back:
    lda hint_restore_due
    beq @done
    lda #0
    sta hint_restore_due
    jsr start_spec        ; a blank row, the floor's name, a blank row
    lda #0
    sta hint_in_extras
    jsr next_line
    lda shown_floor
    asl
    tay
    lda floor_names, y
    ldx floor_names + 1, y
    jsr add_part
    lda #HINT_LINES
    sta hint_rows_left
@done:
    rts

; The next of the hint's rows, into the NMI's queue - if this frame has room for it.
send_hint_row:
    lda hint_rows_left
    beq @done
    lda row_waiting
    ora queue_count
    ora changed_count
    bne @done
    lda status_count
    cmp #(MOST_STATUS_SENDS + 1)
    bcs @done
    lda hint_in_extras
    beq @compose
    jsr use_extras
@compose:
    lda #HINT_LINES
    sec
    sbc hint_rows_left
    jsr compose_hint_row
    jsr use_maps
    jsr queue_word_row
    dec hint_rows_left
@done:
    rts

; In: A = a line of the hint (0-2). Out: word_row, word_page and word_tiles: its row, centred.
compose_hint_row:
    pha
    clc
    adc #HINT_FIRST_ROW
    sta word_row
    lda #$24              ; the second nametable
    sta word_page
    pla
    asl
    asl
    asl                   ; * 8: the line's parts
    sta hint_slot
    lda #0
    sta hint_width
    ldx #31
@clear:
    sta word_tiles, x
    dex
    bpl @clear
    ldx hint_slot
@measure:
    jsr point_at_part
    bcc @measured
    jsr text_length
    clc
    adc hint_width
    sta hint_width
    inx
    inx
    txa
    and #(PARTS_PER_LINE * 2 - 1)
    bne @measure
@measured:
    lda #32               ; start at column (32 - width) / 2
    sec
    sbc hint_width
    lsr
    sta text_column
    ldx hint_slot
@put:
    jsr point_at_part
    bcc @done
    stx hint_slot
    jsr put_text_pointer
    stx text_column       ; (put_text_pointer leaves X after the last letter)
    ldx hint_slot
    inx
    inx
    txa
    and #(PARTS_PER_LINE * 2 - 1)
    bne @put
@done:
    rts

; In: X = a place in hint_parts. Out: carry set and text_pointer if a part is there.
point_at_part:
    lda hint_parts + 1, x
    beq @none
    sta text_pointer + 1
    lda hint_parts, x
    sta text_pointer
    sec
    rts
@none:
    clc
    rts

; --- making a hint's parts -----------------------------------------------------------------------------
start_spec:
    lda #0
    sta spec_slot
    ldx #(HINT_LINES * PARTS_PER_LINE * 2 - 1)
@clear:
    sta hint_parts, x
    dex
    bpl @clear
    rts

; In: A/X = a string's address (low/high): the next part of this line.
add_part:
    ldy spec_slot
    sta hint_parts, y
    txa
    sta hint_parts + 1, y
    iny
    iny
    sty spec_slot
    rts

; The parts that follow go on the next line.
next_line:
    lda spec_slot
    ora #(PARTS_PER_LINE * 2 - 1)
    clc
    adc #1
    sta spec_slot
    rts

; In: A = 1-9: the digit as a part.
add_digit:
    sec
    sbc #1
    asl
    clc
    adc #<digit_texts
    pha
    lda #>digit_texts
    adc #0
    tax
    pla
    jmp add_part

; In: A = a THING_ number: its name as a part.
add_thing_name:
    asl
    tay
    lda hint_things, y
    ldx hint_things + 1, y
    jmp add_part

; Two lines go on the first and last rows, apart (the font's lines are only a pixel apart).
show_spec:
    lda hint_parts + PARTS_PER_LINE * 4 + 1
    bne @placed           ; three lines
    lda hint_parts + 1
    beq @placed           ; one line, already in the middle
    ldx #(PARTS_PER_LINE * 2 - 1)
@move:
    lda hint_parts + PARTS_PER_LINE * 2, x
    sta hint_parts + PARTS_PER_LINE * 4, x
    lda #0
    sta hint_parts + PARTS_PER_LINE * 2, x
    dex
    bpl @move
@placed:
    lda #1
    sta hint_in_extras
    lda #HINT_LINES
    sta hint_rows_left
    lda #HINT_TIME
    sta hint_timer
    lda #0
    sta hint_restore_due
    rts

; --- what the hint says --------------------------------------------------------------------------------
; The remaster's hint() for this moment.
choose_hint:
    jsr holding_whole_urn
    bcc @not_whole
    jmp get_out_hint
@not_whole:
    jsr find_nearest_urn
    lda aim_item
    bpl @found
    jsr next_line         ; one line, in the middle
    part nothing_left
    rts
@found:
    tax
    lda item_floor, x
    sta aim_floor
    lda item_x, x
    ldy item_y, x
    jsr room_at
    lda aim_floor
    cmp floor
    bne @elsewhere
    lda aim_room
    cmp room
    bne @elsewhere
    jmp take_it_hint
@elsewhere:
    jsr left_to_find
    jsr next_line
    jmp way

; With the whole urn: out of the front door, and which way.
get_out_hint:
    part have_urn
    jsr next_line
    lda floor
    cmp #FRONT_DOOR_FLOOR
    bne @elsewhere
    lda room
    cmp #FRONT_DOOR_ROOM
    bne @elsewhere
    part walk_out
    jsr next_line
    part right_edge
    rts
@elsewhere:
    part door_is
    jsr next_line
    lda #FRONT_DOOR_FLOOR
    sta aim_floor
    lda #FRONT_DOOR_ROOM
    sta aim_room
    jmp way

; In the aim's room: how to take it.
take_it_hint:
    ldx aim_item
    lda urn_shapes - URN, x
    cmp #WHOLE_URN
    beq @whole
    part a_piece_is
    jmp @what
@whole:
    part the_urn_is
@what:
    part in_this_room
    jsr next_line
    bit flags
    bvc @not_lit          ; (MATCH_LIT is bit 6)
    part walk_while
    jsr next_line
    part match_burns
    rts
@not_lit:
    part light_a_match
    jsr next_line
    part walk_into
    rts

; "3 PIECES LEFT. THE NEAREST IS" - counting what's in your hands as found.
left_to_find:
    lda #URN_PIECES
    sta hint_number
    ldx carried
    cpx #URN
    bcc @counted
    cpx #(URN + URN_PIECES)
    bcs @counted
    lda urn_shapes - URN, x
    tay
    lda pieces_of_shape, y
    tay
    lda hint_number
    sec
    sbc pieces_counted, y
    sta hint_number
@counted:
    lda hint_number
    cmp #1
    bne @several
    part one_piece_left
    rts
@several:
    jsr add_digit
    part pieces_left_text
    rts

; Which way to aim_floor and aim_room: up or down the stairs, else across the floor.
way:
    lda aim_floor
    cmp floor
    beq way_across
    bcc @down
    part up_the_stairs
    lda aim_floor
    sec
    sbc floor
    jmp @floors
@down:
    part down_the_stairs
    lda floor
    sec
    sbc aim_floor
@floors:
    sta hint_number
    jsr add_digit
    lda hint_number
    cmp #1
    bne @several
    part one_floor
    rts
@several:
    part several_floors
    rts

; Across a floor, from room to aim_room: up or down a row, left or right a column (rooms: even on the
; right, 0-1 at the bottom).
way_across:
    lda room              ; the columns: from the left (odd) to the right (even) is right
    and #1
    sta hint_number
    lda aim_room
    and #1
    sec
    sbc hint_number       ; 0 the same column, 1 left, $FF right
    sta hint_sideways
    lda aim_room          ; the rows
    lsr
    sta hint_number
    lda room
    lsr
    cmp hint_number
    beq @sideways
    bcs @down
    lda hint_sideways
    bne @up_and
    part up_word
    jmp @sideways
@up_and:
    part up_and
    jmp @sideways
@down:
    lda hint_sideways
    bne @down_and
    part down_word
    jmp @sideways
@down_and:
    part down_and
@sideways:
    lda hint_sideways
    beq @end
    bmi @right
    part to_the_left
    jmp @end
@right:
    part to_the_right
@end:
    part full_stop
    rts

; --- the notes -----------------------------------------------------------------------------------------
; The urn just became whole in your hands; or taking something put down what you held.
notes:
    jsr holding_whole_urn
    bcc @not_whole
    lda hint_was_whole
    bne @not_whole
    jsr start_spec
    part urn_whole
    jsr next_line
    part get_it_out
    jsr next_line
    part front_door_where
    jsr show_spec
@not_whole:
    lda hint_was_carried
    cmp #NOTHING
    beq @done
    lda carried
    cmp #NOTHING
    beq @done
    cmp hint_was_carried
    beq @done
    jsr start_spec
    part you_put_down
    lda hint_was_thing
    jsr add_thing_name
    jsr next_line
    part to_take
    ldx carried
    jsr thing_of
    jsr add_thing_name
    part full_stop
    jsr next_line
    part one_at_a_time
    jsr show_spec
@done:
    rts

; What's held, for next frame's notes.
remember_held:
    jsr holding_whole_urn
    lda #0
    rol
    sta hint_was_whole
    ldx carried
    stx hint_was_carried
    cpx #NOTHING
    beq @done
    jsr thing_of
    sta hint_was_thing
@done:
    rts

; --- what the state says -------------------------------------------------------------------------------
; Out: carry set if what's held is the whole urn.
holding_whole_urn:
    ldx carried
    cpx #URN
    bcc @no
    cpx #(URN + URN_PIECES)
    bcs @no
    lda urn_shapes - URN, x
    cmp #WHOLE_URN
    bne @no
    sec
    rts
@no:
    clc
    rts

; In: X = an item (not NOTHING). Out: A = what it's called: a THING_ number.
thing_of:
    cpx #URN
    bcs @urn
    txa                   ; the key and the scepter are items 0 and 1
    rts
@urn:
    lda urn_shapes - URN, x
    tay
    lda pieces_of_shape, y
    tay
    lda pieces_counted, y
    cmp #1
    bne @whole
    lda #THING_PIECE
    rts
@whole:
    lda #THING_URN
    rts

; Out: aim_item: the nearest piece, pieces or whole urn that isn't in your hands, or NOTHING. Another
; floor is always further than anywhere on this one.
find_nearest_urn:
    lda #NOTHING
    sta aim_item
    ldx #URN
@item:
    lda urn_shapes - URN, x
    cmp #JOINED
    beq @next
    cpx carried
    beq @next
    lda item_floor, x
    sec
    sbc floor
    bcs @floors
    eor #$FF
    adc #1
@floors:
    sta try_floors
    lda #0
    sta try_distance
    sta try_distance + 1
    lda player_x
    sta hint_other
    lda item_x, x
    jsr add_difference
    lda player_y
    sta hint_other
    lda item_y, x
    jsr add_difference
    lda aim_item
    bmi @take             ; the first found
    lda try_floors
    cmp aim_floors
    bcc @take
    bne @next
    jsr nearer
    bcc @next
@take:
    stx aim_item
    lda try_floors
    sta aim_floors
    jsr keep_distance
@next:
    inx
    cpx #(URN + URN_PIECES)
    bne @item
    rts

; In: A = x, Y = y on the floor. Out: aim_room: the room whose middle (its first waypoint) is nearest,
; across and up added (for rooms in a grid, as the original's are, the same room as the nearest straight).
room_at:
    sta hint_x
    sty hint_y
    ldy #0
@room:
    lda #0
    sta try_distance
    sta try_distance + 1
    lda hint_x
    sta hint_other
    lda waypoint_x, y
    jsr add_difference
    lda hint_y
    sta hint_other
    lda waypoint_y, y
    jsr add_difference
    cpy #0
    beq @take
    jsr nearer
    bcc @next
@take:
    sty aim_room
    jsr keep_distance
@next:
    iny
    cpy #ROOM_COUNT
    bne @room
    rts

; try_distance += |A - hint_other|.
add_difference:
    sec
    sbc hint_other
    bcs @positive
    eor #$FF
    adc #1                ; (the carry is clear here)
@positive:
    clc
    adc try_distance
    sta try_distance
    bcc @done
    inc try_distance + 1
@done:
    rts

; Out: carry set if try_distance is less than aim_distance.
nearer:
    lda try_distance + 1
    cmp aim_distance + 1
    bne @decided
    lda try_distance
    cmp aim_distance
@decided:                 ; carry clear if try < aim: turn it round
    rol
    eor #1
    ror
    rts

keep_distance:
    lda try_distance
    sta aim_distance
    lda try_distance + 1
    sta aim_distance + 1
    rts

.segment "RODATA"
hint_things:      .word the_key, the_scepter, the_piece, the_urn   ; (read while the maps' bank is in)
.segment "EXTRAS"
digit_texts:      .byte "1", STRING_END, "2", STRING_END, "3", STRING_END, "4", STRING_END
                  .byte "5", STRING_END, "6", STRING_END, "7", STRING_END, "8", STRING_END
                  .byte "9", STRING_END
nothing_left:     .byte "NOTHING LEFT TO FIND.", STRING_END
have_urn:         .byte "YOU HAVE THE URN! GET OUT NOW!", STRING_END
walk_out:         .byte "WALK OUT OF THIS ROOM'S", STRING_END
right_edge:       .byte "RIGHT-HAND EDGE.", STRING_END
door_is:          .byte "THE FRONT DOOR IS", STRING_END
a_piece_is:       .byte "A PIECE IS", STRING_END
the_urn_is:       .byte "THE URN IS", STRING_END
in_this_room:     .byte " IN THIS ROOM.", STRING_END
walk_while:       .byte "WALK INTO IT WHILE THE", STRING_END
match_burns:      .byte "MATCH BURNS.", STRING_END
light_a_match:    .byte "LIGHT A MATCH - A - AND", STRING_END
walk_into:        .byte "WALK INTO IT.", STRING_END
one_piece_left:   .byte "1 PIECE LEFT. IT IS", STRING_END
pieces_left_text:      .byte " PIECES LEFT. THE NEAREST IS", STRING_END
up_the_stairs:    .byte "UP THE STAIRS, ", STRING_END
down_the_stairs:  .byte "DOWN THE STAIRS, ", STRING_END
one_floor:        .byte " FLOOR.", STRING_END
several_floors:   .byte " FLOORS.", STRING_END
up_word:          .byte "UP", STRING_END
down_word:        .byte "DOWN", STRING_END
up_and:           .byte "UP AND ", STRING_END
down_and:         .byte "DOWN AND ", STRING_END
to_the_left:      .byte "TO THE LEFT", STRING_END
to_the_right:     .byte "TO THE RIGHT", STRING_END
full_stop:        .byte ".", STRING_END
urn_whole:        .byte "THE URN IS WHOLE!", STRING_END
get_it_out:       .byte "NOW GET IT OUT OF THE", STRING_END
front_door_where: .byte "FRONT DOOR - FLOOR 1, RIGHT.", STRING_END
you_put_down:     .byte "YOU PUT DOWN ", STRING_END
to_take:          .byte "TO TAKE ", STRING_END
one_at_a_time:    .byte "YOU HOLD ONE THING AT A TIME.", STRING_END
the_key:          .byte "THE KEY", STRING_END
the_scepter:      .byte "THE SCEPTER", STRING_END
the_piece:        .byte "THE PIECE", STRING_END
the_urn:          .byte "THE URN", STRING_END
.segment "CODE"
