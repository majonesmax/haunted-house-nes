; Moving (spec, "Moving"): one unit across and one up or down a frame at most, by the stick read last
; frame; a wall or the floor's edge stops the player with a bump.

move:
    lda #0
    sta step_x
    sta step_y
    lda stairs
    and #<~AT_EDGE
    sta stairs
    bit blocked           ; bit 6: a locked door stops moving across
    bvs @no_across
    jsr move_across
@no_across:
    bit blocked           ; bit 7: ...or up and down
    bmi @no_up_or_down
    jsr move_up_or_down
@no_up_or_down:
    lda #0
    sta blocked
    lda player_y
    jsr eyes_line_for
    sta eyes_line
    rts

probe = work_1            ; the x or y just beyond the player's box, being tested

move_across:
    lda joystick
    and #STICK_LEFT
    beq @not_left
    lda #$FF
    sta step_x
    lda player_x
    cmp #FLOOR_LEFT
    beq @edge
    sec
    sbc #1                ; left: test x - 1
    jmp @test
@not_left:
    lda joystick
    and #STICK_RIGHT
    beq @done
    lda #1
    sta step_x
    lda player_x
    cmp #FLOOR_RIGHT
    beq @edge
    clc
    adc #8                ; right: test x + 8 (the box is 8 wide)
@test:
    sta probe
    ldy player_y          ; at the box's top row...
    iny
    iny
    jsr wall_at
    bcs @bump
    lda probe             ; ...and its bottom row
    ldy player_y
    jsr wall_at
    bcs @bump
    lda player_x
    clc
    adc step_x
    sta player_x
@done:
    rts
@edge:
    jmp reach_edge
@bump:
    lda #SOUND_BUMP
    jmp start_effect

move_up_or_down:
    lda joystick
    and #(STICK_UP | STICK_DOWN)
    beq @done
    cmp #STICK_DOWN       ; down only if down alone is pushed
    bne @up
    lda #$FF
    sta step_y
    lda player_y
    cmp #FLOOR_BOTTOM
    beq @edge
    sec
    sbc #1                ; down: test y - 1
    jmp @test
@up:
    lda #1
    sta step_y
    lda player_y
    cmp #FLOOR_TOP
    beq @edge
    clc
    adc #3                ; up: test y + 3 (the box is 3 tall)
@test:
    sta probe
    tay                   ; at the box's right column...
    lda player_x
    clc
    adc #7
    jsr wall_at
    bcs @bump
    ldy probe             ; ...and its left column
    lda player_x
    jsr wall_at
    bcs @bump
    lda player_y
    clc
    adc step_y
    sta player_y
@done:
    rts
@edge:
    jmp reach_edge
@bump:
    lda #SOUND_BUMP
    jmp start_effect

; At the floor's limit: the stairs or the front door may take it from here; with no stairs, a bump.
reach_edge:
    lda stairs
    ora #AT_EDGE
    sta stairs
    cmp #(AT_EDGE | NO_STAIRS)
    bne @done
    lda #SOUND_BUMP
    jmp start_effect
@done:
    rts

; In: A = a y. Out: A = the screen line the eyes are on there - mid-screen, except near the floor's ends.
eyes_line_for:
    cmp #MIDDLE_SCREEN_LINE
    bcc @done             ; near the bottom: the line is the y
    cmp #SCROLL_STOPS
    bcc @middle
    sec                   ; near the top
    sbc #SCROLL_TOP_OFFSET
    rts
@middle:
    lda #MIDDLE_SCREEN_LINE
@done:
    rts

; The wall test for a point (spec, "The mansion"). In: A = x, Y = y. Out: carry set if it's wall.
; Uses X, Y and work_0.
column = work_0
wall_at:
    lsr
    lsr
    lsr
    lsr
    sec
    sbc #1                ; columns start at x = 16
    sta column
    tya
    lsr
    lsr
    lsr
    lsr
    tax                   ; the row
    lda column
    and #$08
    beq @in_the_plan
    cpx #MIDDLE_ROW       ; outside the eight columns: wall, except in the middle row
    bne @wall
    clc
    rts
@in_the_plan:
    txa                   ; the row in this floor's plan
    ldx floor
    clc
    adc walls_from, x
    tax
    ldy column
    lda mansion_walls, x
    and bits, y
    bne @wall
    clc
    rts
@wall:
    sec
    rts
