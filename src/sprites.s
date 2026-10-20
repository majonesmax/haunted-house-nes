; The cast as sprites (docs/plan.md, "The picture"): what's seen, by the original's rules (the remaster's
; game/visibility.py), drawn where the game has it, every frame - front to back: the match's hand, the
; eyes, the hood, the monsters, the items, the stairs. Each kind of thing has three colours; the eyes keep
; the first sprite palette, and the other three go to whatever kinds are on screen this frame.

VIEW_FIRST_LINE = 41      ; the view's lines on screen
VIEW_LAST_LINE = 200
VIEW_CENTRE_BASE = 201    ; a thing's centre on screen: 201 - 2 * (its line in the view) - its height
HEIGHT_EYES = 3           ; each kind's height on the floor, in lines (the remaster's HEIGHTS)
HEIGHT_ITEM = 8
HEIGHT_MONSTER = 10
HEIGHT_STAIRS = 17
HAND_OFFSET = 10          ; floor units from the eyes to the hand holding a lit match
HAND_DROP = 2
BLINK_EVERY = 200         ; the eyes blink for 6 frames in every 200
BLINK_FRAMES = 6
JUMP = 8                  ; a monster moved further than this: put somewhere new, not walking
STANDING = 8              ; frames without moving before a tarantula's legs stop
FACING_DOWN = 0
FACING_LEFT = 1
FACING_RIGHT = 2
FACING_UP = 3
LOOK_CENTRE = 0
LOOK_LEFT = 1
LOOK_RIGHT = 2
LOOK_UP = 3
LOOK_DOWN = 4
LOOK_BLINK = 5
NO_KIND = $FF
SPRITE_PALETTES = 16      ; where the sprites' palettes start in palette_buffer
MIRRORED = $40
URN_FIRST_SHAPE = 2

build_sprites:
    lda #0
    sta oam_next
    sta oam_full
    lda #KIND_EYES
    sta slot_kind
    lda #NO_KIND
    sta slot_kind + 1
    sta slot_kind + 2
    sta slot_kind + 3
    inc animation_clock
    inc blink_clock
    lda blink_clock
    cmp #BLINK_EVERY
    bcc @counted
    lda #0
    sta blink_clock
@counted:
    jsr update_facings
    lda flags
    and #MATCH_LIT
    beq @eyes
    jsr draw_hand
@eyes:
    jsr draw_eyes
    lda flags
    and #MATCH_LIT
    beq @others
    jsr draw_hood
@others:
    jsr draw_monsters
    jsr draw_items
    jsr draw_stairs
    jsr hide_the_rest
    jmp compose_sprite_palettes

; The sprites last frame used and this frame doesn't, hidden below the screen.
hide_the_rest:
    lda oam_full
    bne @remember
    ldx oam_next
    lda #$FF
@sprite:
    cpx oam_used
    bcs @remember
    sta OAM, x
    inx
    inx
    inx
    inx
    bne @sprite
@remember:
    lda oam_full          ; all 64 count as used
    beq @count
    lda #$FF
    sta oam_used
    rts
@count:
    lda oam_next
    sta oam_used
    rts

; Each slot's kind's three colours, after the sprites' backdrop.
compose_sprite_palettes:
    ldx #0
@slot:
    txa
    asl
    asl
    tay                   ; the slot's place in the sprites' palettes
    lda #BLACK_COLOUR
    sta palette_buffer + SPRITE_PALETTES, y
    lda slot_kind, x
    cmp #NO_KIND
    beq @next
    sta work_0            ; kind * 3
    asl
    clc
    adc work_0
    stx work_1
    tax
    lda kind_colours, x
    sta palette_buffer + SPRITE_PALETTES + 1, y
    lda kind_colours + 1, x
    sta palette_buffer + SPRITE_PALETTES + 2, y
    lda kind_colours + 2, x
    sta palette_buffer + SPRITE_PALETTES + 3, y
    ldx work_1
@next:
    inx
    cpx #4
    bne @slot
    rts

; In: A = a kind. Out: draw_palette = its sprite palette: the eyes' own, one it already has, a free one,
; or (more kinds than palettes) the last.
choose_palette:
    cmp #KIND_EYES
    bne @find
    lda #0
    sta draw_palette
    rts
@find:
    ldx #1
@same:
    cmp slot_kind, x
    beq @found
    inx
    cpx #4
    bne @same
    ldx #1
@free:
    ldy slot_kind, x
    cpy #NO_KIND
    beq @take
    inx
    cpx #4
    bne @free
    ldx #3
    jmp @found
@take:
    sta slot_kind, x
@found:
    stx draw_palette
    rts

; --- where things go -----------------------------------------------------------------------------------
; In: thing_x, thing_y (floor), thing_height (lines). Out: draw_centre_x, draw_centre_y (screen, 16 bits).
place_thing:
    lda thing_x           ; across: 8 + (x + 4) * 1.5
    clc
    adc #4
    sta work_0
    lsr
    clc
    adc work_0
    adc #8
    sta draw_centre_x
    lda player_y          ; the view's bottom line's floor y
    sec
    sbc eyes_line
    sta work_0
    lda thing_y           ; the thing's line in the view: y - that, 16 bits
    sec
    sbc work_0
    sta work_1
    lda #0
    sbc #0
    sta work_2
    asl work_1            ; * 2
    rol work_2
    lda #VIEW_CENTRE_BASE ; 201 - its height - 2 * line
    sec
    sbc thing_height
    sec
    sbc work_1
    sta draw_centre_y
    lda #0
    sbc work_2
    sta draw_centre_y + 1
    rts

; Out: carry set if any of thing_y .. thing_y + thing_height - 1 is in the view's 80 lines.
thing_on_screen:
    lda player_y
    sec
    sbc eyes_line
    sta work_0
    lda thing_y           ; bottom = y - view's bottom, 16 bits
    sec
    sbc work_0
    sta work_1
    lda #0
    sbc #0
    bmi @below            ; below the view: is its top in it?
    bne @no
    lda work_1            ; in or above the view: is its bottom under 80?
    cmp #VIEW_LINES
    bcs @no
@yes:
    sec
    rts
@below:
    lda work_1            ; bottom + height > 0
    clc
    adc thing_height
    bcc @no               ; still below 0
    bne @yes
@no:
    clc
    rts

; --- drawing a picture ---------------------------------------------------------------------------------
; In: draw_pointer (a picture: width, height, pieces, then top/left/tile/attributes each), draw_centre_x/y,
; draw_palette, draw_mirror. Its pieces go in the sprite table; those outside the view are left out.
draw_picture:
    ldy #0
    lda (draw_pointer), y
    sta picture_width
    clc                   ; padded to whole pieces, for mirroring
    adc #7
    and #$F8
    sta picture_padded
    iny
    lda (draw_pointer), y
    lsr
    sta work_0            ; half its height
    iny
    lda (draw_pointer), y
    sta pieces_left
    lda draw_centre_y     ; its top: centre - half its height
    sec
    sbc work_0
    sta picture_top
    lda draw_centre_y + 1
    sbc #0
    sta picture_top + 1
    lda picture_width
    lsr
    sta work_0
    lda draw_centre_x     ; its left: centre - half its width
    sec
    sbc work_0
    sta picture_left
    ldy #3
@piece:
    lda pieces_left
    beq @done
    dec pieces_left
    lda (draw_pointer), y ; the piece's top on screen, 16 bits
    clc
    adc picture_top
    sta work_1
    lda picture_top + 1
    adc #0
    bne @skip             ; above or below the screen
    lda work_1
    cmp #VIEW_FIRST_LINE
    bcc @skip
    cmp #(VIEW_LAST_LINE + 1)
    bcs @skip
    iny
    lda (draw_pointer), y ; its left within the picture
    ldx draw_mirror
    beq @left_found
    eor #$FF              ; mirrored: padded width - 8 - left
    sec
    adc picture_padded
    sec
    sbc #8
@left_found:
    clc
    adc picture_left
    sta work_2
    iny
    lda (draw_pointer), y ; the tile
    sta work_3
    iny
    lda (draw_pointer), y ; the attributes: mirrored, and the palette
    eor draw_mirror
    ora draw_palette
    iny
    ldx oam_next
    sta OAM + 2, x
    lda work_1
    sec
    sbc #1                ; the NES draws a sprite a line below its y
    sta OAM, x
    lda work_3
    sta OAM + 1, x
    lda work_2
    sta OAM + 3, x
    txa
    clc
    adc #4
    sta oam_next
    bne @piece
    inc oam_full          ; all 64 used
    rts
@skip:
    iny
    iny
    iny
    iny
    jmp @piece
@done:
    rts

; In: A = a kind; thing_x, thing_y, thing_height; draw_pointer; draw_mirror.
draw_thing:
    jsr choose_palette
    jsr place_thing
    jmp draw_picture

; --- the eyes, the hood, the hand ---------------------------------------------------------------------
draw_eyes:
    lda player_x
    sta thing_x
    lda player_y
    sta thing_y
    lda #HEIGHT_EYES
    sta thing_height
    jsr eyes_look
    asl
    tax
    lda eyes_pictures, x
    sta draw_pointer
    lda eyes_pictures + 1, x
    sta draw_pointer + 1
    lda #0
    sta draw_mirror
    lda #KIND_EYES
    jmp draw_thing

; Out: A = where the eyes look: sideways first, then up or down; now and then they blink.
eyes_look:
    lda blink_clock
    cmp #BLINK_FRAMES
    bcs @open
    lda game_state
    bne @open
    lda #LOOK_BLINK
    rts
@open:
    lda stick
    bpl @not_right
    lda #LOOK_RIGHT
    rts
@not_right:
    and #STICK_LEFT
    beq @not_left
    lda #LOOK_LEFT
    rts
@not_left:
    lda stick
    and #STICK_UP
    beq @not_up
    lda #LOOK_UP
    rts
@not_up:
    lda stick
    and #STICK_DOWN
    beq @ahead
    lda #LOOK_DOWN
    rts
@ahead:
    lda #LOOK_CENTRE
    rts

draw_hood:
    lda player_x
    sta thing_x
    lda player_y
    sta thing_y
    lda #HEIGHT_EYES
    sta thing_height
    lda #<picture_hood
    sta draw_pointer
    lda #>picture_hood
    sta draw_pointer + 1
    lda #0
    sta draw_mirror
    lda #KIND_LIGHT
    jmp draw_thing

; The hand holding up the match, on the side the player last looked.
draw_hand:
    lda stick
    and #(STICK_LEFT | STICK_RIGHT)
    beq @side_found
    sta hand_side
@side_found:
    lda hand_side
    and #STICK_LEFT
    beq @right
    lda #MIRRORED
    sta draw_mirror
    lda player_x
    sec
    sbc #HAND_OFFSET
    jmp @placed
@right:
    lda #0
    sta draw_mirror
    lda player_x
    clc
    adc #HAND_OFFSET
@placed:
    sta thing_x
    lda player_y
    sec
    sbc #HAND_DROP
    sta thing_y
    lda #HEIGHT_EYES
    sta thing_height
    lda animation_clock
    and #8
    beq @first_frame
    lda #<picture_match_hand_right_1
    sta draw_pointer
    lda #>picture_match_hand_right_1
    jmp @frame_found
@first_frame:
    lda #<picture_match_hand_right_0
    sta draw_pointer
    lda #>picture_match_hand_right_0
@frame_found:
    sta draw_pointer + 1
    lda #KIND_LIGHT
    jmp draw_thing

; --- the monsters --------------------------------------------------------------------------------------
draw_monsters:
    ldx #0
@monster:
    stx drawn_monster
    jsr monster_seen
    bcc @next
    jsr draw_monster
@next:
    ldx drawn_monster
    inx
    cpx last_monster
    beq @monster
    bcc @monster
    rts

; In: X = a monster. Out: carry set if it's seen (the remaster's visibility.monster_visible).
monster_seen:
    lda monster_floor, x
    cmp floor
    bne @no
    lda monster_y, x
    sta thing_y
    lda #HEIGHT_MONSTER
    sta thing_height
    lda game_number       ; game 1, or dying: any on the floor that's on screen
    beq @on_screen
    lda death_timer
    bne @on_screen
    lda monsters_here
    beq @no
    lda monster_room, x
    cmp room
    beq @on_screen
    cmp room_beyond
    bne @no
@on_screen:
    jmp thing_on_screen
@no:
    clc
    rts

; In: drawn_monster. Its picture for its facing and step of its walk.
draw_monster:
    ldx drawn_monster
    lda monster_x, x
    sta thing_x
    lda monster_y, x
    sta thing_y
    lda #HEIGHT_MONSTER
    sta thing_height
    lda animation_clock   ; the step: every 8 frames...
    lsr
    lsr
    lsr
    and #3
    sta work_4
    cpx #2                ; ...but a tarantula standing still keeps its legs still
    bcc @step_found
    lda monster_still, x
    cmp #STANDING
    bcc @step_found
    lda #0
    sta work_4
@step_found:
    txa                   ; monster * 4 + facing...
    asl
    asl
    ora monster_facing, x
    tay
    lda monster_mirrored, y
    beq @not_mirrored
    lda #MIRRORED
@not_mirrored:
    sta draw_mirror
    tya                   ; ...* 4 + step, * 2 for the address
    asl
    asl
    ora work_4
    asl
    tay
    bcs @second_half      ; past 128 entries' worth of bytes
    lda monster_pictures, y
    sta draw_pointer
    lda monster_pictures + 1, y
    jmp @pointer_found
@second_half:
    lda monster_pictures + 256, y
    sta draw_pointer
    lda monster_pictures + 257, y
@pointer_found:
    sta draw_pointer + 1
    lda drawn_monster     ; its kind: the ghost, the bat, a tarantula
    clc
    adc #KIND_GHOST
    jmp draw_thing

; Which way each monster faces, from how it moved since last frame (the remaster's Facing, a frame at a
; time): along the longer side; exactly diagonal keeps the old facing if it's one of the two.
update_facings:
    ldx #4
@monster:
    lda monster_floor, x
    cmp monster_last_floor, x
    bne @jumped
    lda monster_x, x
    sec
    sbc monster_last_x, x
    sta work_0            ; dx
    jsr distance_of
    sta work_2
    lda monster_y, x
    sec
    sbc monster_last_y, x
    sta work_1            ; dy
    jsr distance_of
    sta work_3
    lda work_2
    cmp #(JUMP + 1)
    bcs @jumped
    lda work_3
    cmp #(JUMP + 1)
    bcs @jumped
    lda work_2
    ora work_3
    bne @moved
    lda monster_still, x
    cmp #$FF
    beq @remember
    inc monster_still, x
    jmp @remember
@moved:
    lda #0
    sta monster_still, x
    jsr judge_facing
    jmp @remember
@jumped:
    lda #STANDING         ; somewhere new: not walking yet; facing the way its plan heads
    sta monster_still, x
    lda monster_route, x
    rol
    rol
    rol
    and #3
    tay
    lda heading_facing, y
    sta monster_facing, x
@remember:
    lda monster_floor, x
    sta monster_last_floor, x
    lda monster_x, x
    sta monster_last_x, x
    lda monster_y, x
    sta monster_last_y, x
    dex
    bpl @monster
    rts

; In: A = a signed difference. Out: A = its size.
distance_of:
    bpl @positive
    eor #$FF
    clc
    adc #1
@positive:
    rts

; In: X = a monster; work_0, work_1 = dx, dy; work_2, work_3 = their sizes.
judge_facing:
    lda work_0
    bmi @left
    lda #FACING_RIGHT
    jmp @across_found
@left:
    lda #FACING_LEFT
@across_found:
    sta work_4            ; across
    lda work_1
    bmi @down
    lda #FACING_UP        ; the game's y counts up the floor
    jmp @up_down_found
@down:
    lda #FACING_DOWN
@up_down_found:
    sta work_5            ; up or down
    lda work_2
    cmp work_3
    beq @diagonal
    bcc @mostly_up_down
    lda work_4
    sta monster_facing, x
    rts
@mostly_up_down:
    lda work_5
    sta monster_facing, x
    rts
@diagonal:
    lda monster_facing, x
    cmp work_4
    beq @keep
    cmp work_5
    beq @keep
    lda work_4
    sta monster_facing, x
@keep:
    rts

; --- the items and the stairs --------------------------------------------------------------------------
draw_items:
    ldx #0
@item:
    stx drawn_item
    jsr item_seen
    bcc @next
    jsr draw_item
@next:
    ldx drawn_item
    inx
    cpx #5
    bne @item
    rts

; In: X = an item. Out: carry set if it's seen: with a match lit, on the floor, not carried, not joined
; into another piece, near enough (the remaster's visibility.item_visible).
item_seen:
    lda flags
    and #MATCH_LIT
    beq @no
    lda item_floor, x
    cmp floor
    bne @no
    cpx carried
    beq @no
    cpx #URN
    bcc @not_a_piece
    lda urn_shapes - URN, x
    bmi @no
@not_a_piece:
    cpx #KEY
    bne @near
    lda game_number
    cmp #FIRST_LOCKED_GAME
    bcc @no
@near:
    jsr light_distance
    cmp #ITEM_REACH
    bcs @no
    sec
    rts
@no:
    clc
    rts

draw_item:
    ldx drawn_item
    lda item_x, x
    sta thing_x
    lda item_y, x
    sta thing_y
    lda #HEIGHT_ITEM
    sta thing_height
    lda #0
    sta draw_mirror
    cpx #URN
    bcs @urn
    txa                   ; the key or the scepter
    asl
    tay
    lda item_pictures, y
    sta draw_pointer
    lda item_pictures + 1, y
    sta draw_pointer + 1
    txa
    clc
    adc #KIND_KEY
    jmp draw_thing
@urn:
    lda urn_shapes - URN, x
    sec
    sbc #URN_FIRST_SHAPE
    asl
    tay
    lda urn_pictures, y
    sta draw_pointer
    lda urn_pictures + 1, y
    sta draw_pointer + 1
    lda #KIND_URN
    jmp draw_thing

; This room's stairs, while a match is lit.
draw_stairs:
    lda flags
    and #MATCH_LIT
    beq @none
    lda stairs
    and #NO_STAIRS
    cmp #NO_STAIRS
    beq @none
    and #3
    tay
    lda stairs_y, y
    sta thing_y
    ldy room
    lda stairs_x, y
    sta thing_x
    lda #HEIGHT_STAIRS
    sta thing_height
    lda #0
    sta draw_mirror
    lda stairs
    and #GOES_UP
    beq @down
    lda #<picture_stairs_up
    sta draw_pointer
    lda #>picture_stairs_up
    jmp @found
@down:
    lda #<picture_stairs_down
    sta draw_pointer
    lda #>picture_stairs_down
@found:
    sta draw_pointer + 1
    lda #KIND_STAIRS
    jmp draw_thing
@none:
    rts

.segment "RODATA"
eyes_pictures:  .word picture_eyes_centre, picture_eyes_left, picture_eyes_right, picture_eyes_up
                .word picture_eyes_down, picture_eyes_blink
item_pictures:  .word picture_key, picture_scepter
urn_pictures:   .word picture_urn2_0, picture_urn3_0, picture_urn4_0, picture_urn5_0, picture_urn6_0
                .word picture_urn7_0, picture_urn8_0
heading_facing: .byte FACING_LEFT, FACING_RIGHT, FACING_UP, FACING_DOWN   ; a plan's direction 0-3
.segment "CODE"
