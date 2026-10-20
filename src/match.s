; The front door, the match and the button (spec, "Winning", "The match", "The button").

front_door_and_match:
    bit stairs            ; bit 7: at the floor's edge
    bpl @clock
    lda floor
    cmp #FRONT_DOOR_FLOOR
    bne @clock
    lda room
    cmp #FRONT_DOOR_ROOM
    bne @clock
    lda carried
    cmp #URN
    bne @stay_inside
    lda urn_shapes        ; item 2 is the whole urn once all three have joined
    cmp #WHOLE_URN
    bne @stay_inside
    lda #1                ; won
    sta clock
    lda #WON_FLAG
    sta flags
    lda #GAME_WON
    sta game_state
    jmp @clock
@stay_inside:
    lda #SOUND_BLOCKED
    jsr start_effect
@clock:
    dec second_counter    ; runs all the time; a lit match loses a second each time it comes round
    bne @going_out
    lda #FRAMES_PER_SECOND
    sta second_counter
    dec match_time
@going_out:
    lda flags
    and #MATCH_LIT
    beq @turn
    lda monsters_here     ; a monster in the room blows it out
    bne @out
    lda match_time
    bne @turn
@out:
    jsr match_out
@turn:
    jmp flip_turn

match_out:
    lda #0
    sta monster_shown
    lda flags
    and #KEEP_ON_MATCH_OUT
    sta flags
    rts

; Items and monsters take turns to be drawn while a match is lit.
flip_turn:
    lda flags
    eor #MONSTER_TURN
    sta flags
    rts

; Read the stick for next frame; a press of the button lights a match, or with one lit drops what's
; carried; and move the drop search on. While a monster is in the room the button isn't read at all.
read_button:
    lda stick
    sta joystick
    lda monsters_here
    bne @drop_search
    lsr button_history    ; this frame's bit in at the top: 0 if pressed
    lda button_down
    bne @history_kept
    lda button_history
    ora #$80
    sta button_history
@history_kept:
    lda button_history
    cmp #PRESSED          ; pressed now, up for the 7 frames before
    bne @drop_search
    lda flags
    and #MATCH_LIT
    bne @lit
    jmp light_match
@lit:
    lda carried
    cmp #NOTHING
    beq @drop_search
    lda #SOUND_DROP
    jsr start_effect
    jsr start_drop
    lda #NOTHING
    sta carried
    rts
@drop_search:
    lda drop_tries
    beq @done
    lda touched_walls     ; the item touched a wall where it was tried: the next spot
    beq @search_over
    jmp next_drop_spot
@search_over:
    lda #0
    sta drop_tries
@done:
    rts

light_match:
    lda #MATCH_SECONDS
    sta match_time
    lda matches_used      ; two decimal digits, plus one (the NES has no decimal mode)
    and #$0F
    cmp #9
    bcc @add_one
    lda matches_used
    and #$F0
    clc
    adc #$10
    cmp #$A0
    bcc @counted
    lda #0
    jmp @counted
@add_one:
    lda matches_used
    clc
    adc #1
@counted:
    sta matches_used
    lda flags
    ora #MATCH_LIT
    sta flags
    rts
