; What's drawn each frame (spec, "What's drawn each frame"): one item, monster or stairs, in turn. The
; choice decides more than looks: touching is tested only against it. The chosen sprite goes into the
; bytes the 2600 drew from - sprite_x, sprite_line, sprite_height and sprite_pointer - which the drop
; search and RESET's frame also use.

choose_sprite:
    lda #0
    sta sprite_wide
    lda game_state
    cmp #GAME_JUST_RESET
    beq @leftover
    and #WON_BIT
    beq @choose
    lda clock             ; won: when the clock comes round, game over
    bne @leftover
    jsr select_mode
@leftover:                ; nothing new is chosen: the bytes keep last frame's sprite (spec, "The leftover sprite")
    jmp drift_colours
@choose:
    lda death_timer
    beq @not_dying
    jsr next_monster
    jmp drift_colours
@not_dying:
    lda drop_tries
    beq @not_dropping
    jsr dropped_item
    jmp drift_colours
@not_dropping:
    lda flags
    and #MATCH_LIT
    beq @monster
    bit flags             ; bit 7: the monsters' turn
    bmi @monster
    jsr next_item
    jmp drift_colours
@monster:
    jsr next_monster
    jmp drift_colours

; Game over and select: colour_cycle counts every 256 frames, and the colours drift with it.
drift_colours:
    lda colour_cycle
    and #ATTRACT
    beq @done
    lda clock
    bne @keep_attract
    inc colour_cycle
@keep_attract:
    lda colour_cycle
    ora #ATTRACT
    sta colour_cycle
@done:
    rts

no_sprite:
    lda #0
    sta sprite_x
    sta sprite_height
    rts

; In: A = a floor y. Out: A = the screen line it's drawn on.
line_of:
    clc
    adc eyes_line
    sec
    sbc player_y
    rts

; In: A = the line of a sprite's bottom row. Out: carry set if any of it shows.
on_screen:
    cmp #VIEW_LINES
    bcc @shows
    cmp #LAST_LINE_BELOW  ; just below the view, with its top rows reaching in (carry set if so)
    rts
@shows:
    sec
    rts

; --- items ---------------------------------------------------------------------------------------------
last_shown = work_6

; The next item in turn that may show, counting down from the last one shown and wrapping.
next_item:
    ldx item_shown
    stx last_shown
@next:
    dex
    bpl @check
    ldx #4
@check:
    jsr item_may_show
    bcs @found
    cpx last_shown
    bne @next
    jmp no_sprite
@found:
    stx item_shown
    jmp set_item_sprite

; In: X = an item. Out: carry set if it may be drawn. Keeps X.
item_may_show:
    cpx carried
    beq @no
    cpx #URN
    bcc @not_a_piece
    lda urn_shapes - URN, x
    bmi @no               ; joined into another piece
@not_a_piece:
    lda game_number
    cmp #FIRST_LOCKED_GAME
    bcs @key_counts
    cpx #KEY              ; games 1-2 have no locks, and no key
    beq @no
@key_counts:
    lda item_floor, x
    cmp floor
    bne @no
    jsr light_distance
    cmp #ITEM_REACH
    bcs @no
    lda item_y, x
    jsr line_of
    jmp on_screen
@no:
    clc
    rts

across = work_7
up_down = work_8

; In: X = an item. Out: A = the game's cheap distance to it - the larger difference plus half the smaller.
light_distance:
    lda player_x
    sec
    sbc item_x, x
    bcs @across_found
    eor #$FF              ; negative: make it positive
    adc #1
@across_found:
    sta across
    lda player_y
    sec
    sbc item_y, x
    bcs @up_down_found
    eor #$FF
    adc #1
@up_down_found:
    sta up_down
    cmp across
    bcs @up_down_larger
    lsr
    clc
    adc across
    rts
@up_down_larger:
    lda across
    lsr
    clc
    adc up_down
    rts

; In: X = an item. Out: A = the low byte of its shape's address: shape * 8 + 8, with the carry out of the
; shifts added too - which only matters for a joined piece, shape $FF, giving $01 (spec, "Dropping").
item_shape:
    txa
    cpx #URN
    bcc @shape_found
    lda urn_shapes - URN, x
@shape_found:
    asl
    asl
    asl
    adc #ITEM_SHAPES
    rts

; In: X = an item.
set_item_sprite:
    lda item_x, x
    sta sprite_x
    lda item_y, x
    jsr line_of
    sta sprite_line
set_item_shape:
    jsr item_shape
    sta sprite_pointer
    lda #SHAPES_PAGE
    sta sprite_pointer + 1
    lda #SHAPE_HEIGHT_ITEM
    sta sprite_height
    rts

; The item being put down, drawn (in black) where the search left sprite_x and sprite_line.
dropped_item:
    ldx dropped
    lda floor
    sta item_floor, x
    stx item_shown
    jmp set_item_shape

; --- monsters ------------------------------------------------------------------------------------------
lost_returns = work_9     ; the 2600 loses a return address on the stack for each of these (the crash)
rounds_left = work_10

; The next monster in turn that may show; with a match lit, the stairs take the slot after the last.
next_monster:
    lda monster_shown
    sta last_shown
    lda #0
    sta lost_returns
    lda last_monster      ; a bound on the search, for a state the game itself can't reach
    clc
    adc #2
    sta rounds_left
    asl
    adc rounds_left
    sta rounds_left
    ldx monster_shown
@next:
    dec rounds_left
    beq @none
    dex
    bpl @monster
    ldx last_monster
    lda flags
    and #MATCH_LIT
    beq @monster
    inx                   ; the stairs' slot
    lda stairs
    and #NO_STAIRS
    cmp #NO_STAIRS
    beq @no_stairs
    stx monster_shown
    jmp set_stairs_sprite
@no_stairs:
    cpx last_shown
    beq @none
    jmp @next
@monster:
    jsr monster_rules_allow
    bcc @not_this_one
    lda monster_y, x
    jsr line_of
    jsr on_screen
    bcc @off_screen
    stx monster_shown
    jmp set_monster_sprite
@off_screen:
    inc lost_returns
@not_this_one:
    cpx last_shown
    bne @next
@none:
    jmp no_sprite

; In: X = a monster. Out: carry set if it may be drawn, wherever it is on the screen. Keeps X.
monster_rules_allow:
    lda monster_floor, x
    cmp floor
    bne @no
    lda game_number       ; game 1: any on the floor
    beq @yes
    lda death_timer       ; dying: any on the floor
    bne @yes
    lda monsters_here
    beq @no
    lda monster_room, x
    cmp room
    beq @yes
    cmp room_beyond
    beq @yes
@no:
    clc
    rts
@yes:
    sec
    rts

; In: X = a monster. Its picture: one of two frames, by bit 6 of the random numbers.
set_monster_sprite:
    lda monster_x, x
    sta sprite_x
    lda monster_y, x
    jsr line_of
    sta sprite_line
    lda monster_frames, x
    clc
    adc #MONSTER_SHAPES
    bit random_low
    bvs @first_frame
    clc
    adc #MONSTER_SECOND_FRAME
@first_frame:
    sta sprite_pointer
    lda #SHAPES_PAGE
    sta sprite_pointer + 1
    lda #SHAPE_HEIGHT_MONSTER
    sta sprite_height
    rts

stairs_here_now = work_7
stairs_picture = work_8

; This room's stairs: the picture by edge and direction, at the edge's line, at double width.
set_stairs_sprite:
    lda stairs
    and #NO_STAIRS
    sta stairs_here_now
    cmp #GOES_UP
    bcc @picture_found    ; going down: picture number = the edge
    and #3                ; going up: the edge XOR 1
    eor #1
@picture_found:
    sta stairs_picture
    asl
    asl
    asl
    asl
    clc
    adc stairs_picture    ; * 17
    adc #STAIRS_SHAPES
    sta sprite_pointer
    lda #SHAPES_PAGE
    sta sprite_pointer + 1
    lda stairs_here_now
    and #3
    tay
    lda stairs_y, y
    jsr line_of
    sta sprite_line
    ldy room
    lda stairs_x, y
    sta sprite_x
    lda #SHAPE_HEIGHT_STAIRS
    sta sprite_height
    lda #1
    sta sprite_wide
    rts
