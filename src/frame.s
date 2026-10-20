; One frame of the game, in the order the 2600 does it (spec, "One frame, in order"), and the switches:
; RESET, SELECT, a new game, select mode.

game_frame:
    inc clock
    jsr switches
    lda game_state
    and #NO_PLAY
    bne @picture
    jsr move
    jsr front_door_and_match
@picture:
    jsr choose_sprite
    jsr next_random
    jsr find_touches
    jsr sound_frame
    lda game_state
    and #NO_LOGIC
    bne @done
    jsr count_down_death  ; carry set: a death has just ended, the monsters don't move
    bcs @after_monsters
    jsr move_monsters
@after_monsters:
    jsr take_stairs
    jsr read_button
    jsr touching
    jsr doorways
@done:
    rts

; The console switches (spec, "The switches, game select and RESET").
switches:
    lda reset_down
    beq @no_reset
    jmp start_new_game
@no_reset:
    lda select_down
    bne @select
    lda #1
    sta select_delay
    rts
@select:
    dec select_delay
    bne @done
    lda #SELECT_REPEAT
    sta select_delay
    ldx game_number
    inx
    cpx #GAME_COUNT
    bcc @next_game
    ldx #0
@next_game:
    stx game_number
    jmp select_mode
@done:
    rts

; A new game (spec, "A new game"): done every frame RESET is held.
start_new_game:
    lda random_low        ; stir the random numbers by swapping their bytes
    ldx random_high
    sta random_high
    stx random_low
    lda #0
    ldx #death_timer
@clear:
    sta 0, x
    inx
    cpx #lives
    bne @clear
    ldx #0
@copy:
    lda new_game, x
    sta lives, x
    inx
    cpx #10
    bne @copy
    lda #FRONT_DOOR_FLOOR ; on the floor with the front door (cleared to 0 above: the original's is 0; a
    sta floor             ; mansion with a cellar has its front door higher)
    jsr scatter
    lda #GHOST_START_FLOOR
    sta monster_floor + GHOST
    ldx #4
@items_where_monsters_are:
    lda monster_floor, x
    sta item_floor, x
    lda monster_x, x
    sta item_x, x
    lda monster_y, x
    sta item_y, x
    dex
    bpl @items_where_monsters_are
    lda game_number
    cmp #GAME_3
    bne @key_placed
    lda #GAME_3_KEY_FLOOR  ; game 3: the master key beside the player
    sta item_floor + KEY
    lda #GAME_3_KEY_X
    sta item_x + KEY
    lda #GAME_3_KEY_Y
    sta item_y + KEY
@key_placed:
    jsr room_changed
    ldx #2
    lda game_number
    cmp #FIRST_FIVE_MONSTER_GAME
    bcc @three_monsters
    ldx #4
@three_monsters:
    stx last_monster
    lda #START_X
    sta player_x
    lda #START_Y
    sta player_y
    lda #MIDDLE_SCREEN_LINE
    sta eyes_line
    rts

; Game over and game select look the same: the match goes out, the colours start to drift.
select_mode:
    jsr match_out
    jsr flip_turn
    lda #GAME_SELECTING
    sta game_state
    lda #ATTRACT
    sta colour_cycle
    lda #0
    sta monster_shown
    sta death_timer
    sta monsters_here
    rts
