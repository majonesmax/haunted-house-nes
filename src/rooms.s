; Doors, stairs and a room's limits (spec, "Doors and rooms", "Stairs").

; Take the stairs if the player is at the edge of a room that has them. In games 1-5 the game reads the
; button here too, so on that frame it's read twice (spec, "Stairs").
take_stairs:
    lda stairs
    and #NO_STAIRS
    cmp #NO_STAIRS
    beq @done
    bit stairs
    bmi @at_edge
    sta stairs            ; away from the edge: "just used" is forgotten
    rts
@at_edge:
    bvs @done             ; just used: step away first
    lda game_number
    cmp #FIRST_FOLLOW_GAME
    bcs @followed
    jsr read_button
    jmp @climb
@followed:
    jsr follow_up_stairs
@climb:
    lda stairs
    and #GOES_UP
    beq @down
    inc floor
    lda #SOUND_STAIRS_UP
    jmp @sound
@down:
    dec floor
    lda #SOUND_STAIRS_DOWN
@sound:
    jsr start_effect
    jsr room_changed
    lda stairs
    ora #JUST_USED_STAIRS
    sta stairs
@done:
    rts

direction = work_2
place = work_3

; Six crossings, tested in order; the first whose start or end the player is on, pushing that way, ends
; the search: up from the bottom row, up from the middle, down into the middle, down into the bottom,
; left, right.
doorways:
    ldx floor
    lda crossings_from, x
    sta crossings_start
    ldx #0
@crossing:
    lda crossing_direction, x
    sta direction
    tay
    lda direction_stick, y
    and joystick
    beq @next
    lda player_x          ; across: x; up and down: y
    cpy #2
    bcc @place_found
    lda player_y
@place_found:
    sta place
    txa
    asl
    clc
    adc crossings_start
    tay
    lda place
    cmp doorway_lines, y
    beq @enter
    cmp doorway_lines + 1, y
    beq @leave
@next:
    inx
    cpx #6
    bne @crossing
    rts
@enter:
    lda direction
    jmp enter_doorway
@leave:
    lda direction
    jmp leave_doorway

; In: A = the direction. Into a doorway - unless its door is locked and the player has no key.
enter_doorway:
    sta direction
    bit doorway
    bmi @done
    jsr door_shut
    bcc @open
    lda carried
    cmp #KEY
    beq @open
    lda direction
    lsr
    tay
    lda block_bits, y     ; stop moving that way next frame
    sta blocked
    lda #SOUND_BLOCKED
    jmp door_sound
@open:
    ldy direction
    lda room
    clc
    adc room_step, y
    sta room_beyond
    lda direction
    ora #IN_DOORWAY
    sta doorway
    lda #SOUND_DOORWAY
    jmp door_sound
@done:
    rts

; In: A = the direction. Out of the far side of a doorway, into the next room. Turning back counts from
; the room beyond, so the step lands back where the player came from.
leave_doorway:
    sta direction
    bit doorway
    bpl @done
    ora #IN_DOORWAY
    cmp doorway
    beq @went_on
    lda room_beyond
    sta room
@went_on:
    lda direction
    pha
    jsr follow_through_door
    pla
    sta doorway
    tay
    lda room
    clc
    adc room_step, y
    sta room
    lda #NOTHING
    sta room_beyond
    jsr room_changed
    lda #SOUND_NEW_ROOM
    jmp door_sound
@done:
    rts

; Game 1 has no door sounds.
door_sound:
    ldx game_number
    beq @done
    jmp start_effect
@done:
    rts

; In: direction. Out: carry set if the way out of this room is locked (or isn't a door).
door_shut:
    lda room
    ldy direction
    ldx floor
    jsr door_way_out
    bmi @shut
    ldy floor
    jmp door_locked
@shut:
    sec
    rts

; In: A = a door, Y = a floor. Out: carry set if that door is locked on that floor in this game.
locked_door = work_4
door_locked:
    sta locked_door
    lda game_number
    cmp #FIRST_LOCKED_GAME
    bcc @open
    tya
    jsr floor_index
    tax
    ldy locked_door
    lda locked_doors, x
    and bits, y
    beq @open
    sec
    rts
@open:
    clc
    rts

; In: A = a floor. Out: A = its index in the per-floor tables (game 9 has its own, after the others).
floor_index:
    ldx game_number
    cpx #GAME_9
    bne @done
    clc
    adc #FLOOR_COUNT
@done:
    rts

; The room's limits, the blocks' places and its stairs, whenever the room or floor changes.
room_changed:
    lda #2
    jsr room_bound
    sta room_top
    lda #3
    jsr room_bound
    sta room_bottom
    lda #0
    jsr room_bound
    beq @no_left_door
    lda #MASK_WITH_LEFT_DOOR
    sta mask_x
    lda #MASK_2_WITH_LEFT_DOOR
    sta mask_x_2
    jmp @stairs
@no_left_door:
    lda #MASK_WITHOUT
    sta mask_x
    lda #MASK_2_WITHOUT
    sta mask_x_2
@stairs:
    jsr stairs_here_value
    sta stairs
    rts

; In: A = a direction. Out: A = the y limit through the door that way, or 0 for none. (For a side door
; this reads past the table's end, as the 2600 does; only "is it 0" is asked of it, and it never is.)
room_bound:
    tay
    lda room
    ldx floor
    jsr door_way_out
    bmi @none
    lsr
    clc
    adc bounds_from, x
    tay
    lda room_bounds, y
    rts
@none:
    lda #0
    rts

; Out: A = the stairs byte for this room: $0F for none, else the edge plus 4 if they go up.
stairs_here_value:
    lda floor
    jsr floor_index
    tax
    ldy room
    lda stairs_here, x
    and bits, y
    bne @has_stairs
    lda #NO_STAIRS
    rts
@has_stairs:
    lda stairs_go_up, x
    and bits, y
    beq @going_down
    lda #GOES_UP
@going_down:
    sta stairs_going
    on_this_floor rooms_from
    lda stairs_edge, y
    ora stairs_going
    rts
