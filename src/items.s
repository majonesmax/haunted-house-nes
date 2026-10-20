; Touching's outcomes, items and the urn, dropping, and dying (spec, "Touching", "Items", "Dropping").

touching:
    lda death_timer
    bne @done
    lda touched_eyes
    beq @done
    lda drop_tries
    bne @done
    lda flags
    and #MATCH_LIT
    bne @lit
    lda monster_shown     ; in the dark, the sprite is a monster unless it's past the last one
    cmp last_monster
    beq @caught
    bcs @done
@caught:
    jmp maybe_caught
@lit:
    bit flags             ; the monsters' turn: the glow stands in for the eyes, ignored
    bmi @done
    jmp pick_up
@done:
    rts

; The scepter saves the player, except from the ghost in games 8-9.
maybe_caught:
    ldx monster_shown
    lda carried
    cmp #SCEPTER
    bne @caught
    lda game_number
    cmp #FIRST_FAST_GAME
    bcc @done
    cpx #GHOST
    bne @done
@caught:
    lda #GAME_DYING
    sta game_state
    lda #$FF
    sta death_timer
    dec lives
    stx killed_by
@done:
    rts

; Take the item touched; an urn piece touching the carried one joins it; anything else carried is put down.
pick_up:
    lda #SOUND_PICK_UP
    jsr start_effect
    ldx item_shown
    lda carried
    cmp #NOTHING
    beq @take
    cmp item_shown
    beq @swap
    cmp #URN
    bcc @swap
    cpx #URN
    bcc @swap
    clc                   ; two urn pieces: the sum of their numbers says which
    adc item_shown
    jsr join
    jmp @put_down_then_carry
@swap:
    txa
@put_down_then_carry:
    pha
    jsr start_drop
    pla
    sta carried
    rts
@take:
    stx carried
    rts

pieces = work_7

; In: A = the two pieces' numbers added. Out: A = the item now carried.
join:
    sta pieces
    lda #SOUND_JOIN
    jsr start_effect
    lda urn_shapes + 1
    ora urn_shapes + 2
    bpl @pair             ; item 3 or 4 already joined: this is the third piece
    lda #SOUND_URN_WHOLE
    jsr start_effect
    lda #WHOLE_URN
    sta urn_shapes
    lda #JOINED
    sta urn_shapes + 1
    sta urn_shapes + 2
    lda #URN
    rts
@pair:
    ldx #2                ; items 2+3: item 3 joins item 2; otherwise item 4 joins the other
    lda pieces
    cmp #5
    bne @joiner_found
    ldx #1
@joiner_found:
    lda #JOINED
    sta urn_shapes, x
    ldx #0                ; items 3+4 are held by item 3; the others by item 2
    lda pieces
    cmp #7
    bne @holder_found
    ldx #1
@holder_found:
    lda pieces
    sta urn_shapes, x
    txa
    clc
    adc #URN
    rts

; --- dropping --------------------------------------------------------------------------------------------
; Put the carried item down: first behind the player if they tried to move this frame, then the spots
; left, below, right and above in turn, one a frame, until one isn't in a wall.
start_drop:
    lda #DROP_SEARCH
    sta drop_tries
    lda carried
    sta dropped
    lda step_x
    ora step_y
    beq next_drop_spot
    lda step_y
    clc
    adc #1
    tax
    lda step_x
    clc
    adc #2
    tay
    jsr try_drop_spot
    bcs next_drop_spot
    rts

next_drop_spot:
    dec drop_tries
    beq @done
    ldx drop_tries
    dex
    txa
    tay
    jsr try_drop_spot
    bcs next_drop_spot
@done:
    rts

offset_y = work_7
x_index = work_8

; In: X = which y offset, Y = which x offset. Moves the dropped item there; carry set if that's off the
; floor (the y is written even when the x fails). Also sets where its sprite will be drawn next frame.
try_drop_spot:
    sty x_index
    lda drop_offsets + 1, x
    sta offset_y
    lda player_y
    cmp #DROP_TOO_HIGH
    bcc @low_enough
    lda offset_y
    cmp #DROP_UP
    beq @off
@low_enough:
    lda offset_y
    clc
    adc player_y
    cmp #DROP_TOO_HIGH
    bcs @off
    ldx dropped
    sta item_y, x
    jsr line_of
    sta sprite_line
    ldy x_index
    lda drop_offsets, y
    clc
    adc player_x
    cmp #DROP_TOO_FAR_RIGHT
    bcs @off
    ldx dropped
    sta item_x, x
    sta sprite_x
    clc
    rts
@off:
    sec
    rts

; --- dying ---------------------------------------------------------------------------------------------
; Count a death down. Out: carry set on the frame it ends (the monsters don't move then).
count_down_death:
    lda game_state
    and #<~GAME_JUST_RESET
    sta game_state
    and #GAME_DYING
    beq @not_ending
    dec death_timer
    bne @not_ending
    lda #GAME_PLAYING
    sta game_state
    lda #0
    sta sound
    sta touched_eyes      ; the 2600 clears its collisions here
    sta touched_walls
    lda lives
    bne @lives_left
    jsr select_mode       ; game over
@lives_left:
    jsr scatter
    jsr bat_takes_item
    sec
    rts
@not_ending:
    clc
    rts

; Games 7-9: the bat leaves what it took where it is.
bat_takes_item:
    lda killed_by
    cmp #BAT
    bne @done
    lda game_number
    cmp #FIRST_THEFT_GAME
    bcc @done
    ldx carried
    cpx #NOTHING
    beq @done
    lda monster_floor + BAT
    sta item_floor, x
    lda monster_x + BAT
    sta item_x, x
    lda monster_y + BAT
    sta item_y, x
    lda #NOTHING
    sta carried
@done:
    rts
