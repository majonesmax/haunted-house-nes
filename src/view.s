; The picture's work each frame, after the game's (docs/plan.md, "The picture"): where the view is, the
; floor's rows streamed in as it scrolls, the palettes, the match's light on the blocks around the eyes,
; and the status band's numbers. It fills buffers; the NMI sends them (ppu.s).
;
; The first nametable holds 30 rows of the floor's 64 (its picture is 240 x 512): floor row r is in
; nametable row r mod 30, columns 1-30. A new floor, or a jump of the view, redraws all 30 rows a few
; at a time with the screen off.

.include "font.inc"

FLOOR_ROWS = 64
NAMETABLE_ROWS = 30
VIEW_ROWS = 21            ; tile rows the view can touch (160 px, not aligned)
ROW_MARGIN = 4            ; rows kept loaded beyond the view, above and below
ROWS_PER_FRAME = 6        ; while a whole floor is drawn
FLOOR_TOP_PX = 176        ; the view's top in floor pixels: (176 - (player y - eyes line)) * 2
UNLIT = 1                 ; the view's palettes (docs/decisions.md): the dark...
WALLS = 2                 ; ...and lit, the walls' and the floor's, each block the one its art was cut in
FLOORS = 3
DARK_COLOURS = 6          ; a floor's colours: the walls' palette, the floor's, the dark (game 1), lightning
FLASH_COLOURS = 9
ALL_UNLIT = $55           ; an attribute byte with all four blocks unlit
STATUS_COLOURS_END = 4
BAR_TILE_COUNT = 3
FLAME = 3
EYES_LEFT = 8 + 6         ; the eyes' centre on screen: 8 + (x + 4) * 1.5
LIGHT_ROWS_AROUND = 3     ; blocks above and below the eyes' block that the light may reach
LIGHT_COLUMNS_AROUND = 2
LIGHT_RANGE = 64          ; px: no light at all this far away
LIGHT_KEY_BYTES = 7
ATTRIBUTE_ROWS = 8        ; the nametable's attribute bytes: 8 rows of 8
ATTRIBUTE_COLUMNS = 8

.segment "CODE"

prepare_picture:
    jsr choose_screen
    lda screen_wanted
    beq @play
    jmp prepare_full_screen
@play:
    lda screen_shown
    beq @playing
    lda #SCREEN_PLAY      ; back from a full screen: the floor is drawn again
    sta screen_shown
    lda #$FF
    sta shown_floor
@playing:
    lda floor
    cmp shown_floor
    beq @same_floor
    jmp start_drawing
@same_floor:
    lda drawing
    beq @drawn
    jmp continue_drawing
@drawn:
    jsr find_view
    lda view_top_row      ; the view has jumped beyond the loaded rows: draw it all again
    cmp loaded_first
    bcc @jumped
    sec
    sbc loaded_first
    cmp #(NAMETABLE_ROWS - VIEW_ROWS + 1)
    bcc @in_view
    lda loaded_first      ; (at the floor's bottom the view, aligned there, needs only 20 rows: if the
    cmp #(FLOOR_ROWS - NAMETABLE_ROWS)   ; loaded rows reach the floor's end, they hold all it can need)
    bcc @jumped
@in_view:
    jsr stream_rows
    jsr compose_frame
    rts
@jumped:
    jmp start_drawing

compose_frame:
    jsr compose_palettes
    jsr build_sprites
    jsr won_lighten
    lda #3
    sta work_part
    jsr light_blocks
    lda #4
    sta work_part
    jsr compare_attributes
    jsr compose_status
    lda #1
    sta render_ready
    rts

; Every sprite below the screen (the sprites come next).
hide_sprites:
    lda #$FF
    ldx #0
@sprite:
    sta OAM, x
    inx
    inx
    inx
    inx
    bne @sprite
    rts

; view_top = (FLOOR_TOP_PX - (player_y - eyes_line)) * 2; the nametable's scroll is that mod 240.
find_view:
    lda player_y
    sec
    sbc eyes_line         ; the floor y at the view's bottom
    sta view_top
    lda #FLOOR_TOP_PX
    sec
    sbc view_top
    asl
    sta view_top
    lda #0
    rol
    sta view_top + 1
    lda view_top + 1      ; in tile rows: / 8
    sta work_0
    lda view_top
    lsr work_0
    ror
    lsr work_0
    ror
    lsr work_0
    ror
    sta view_top_row
    lda view_top          ; the scroll: view_top mod 240
    ldx view_top + 1
    bne @past_240
    cmp #240
    bcc @scroll_found
@past_240:
    sec
    sbc #240
@scroll_found:
    sta scroll_y
    and #$F8
    asl
    asl
    sta split_low
    rts

; --- the floor's rows ------------------------------------------------------------------------------------
; Keep ROW_MARGIN rows loaded beyond the view at each end: one new row a frame at most.
stream_rows:
    lda row_waiting
    bne @done
    lda view_top_row
    sec
    sbc loaded_first
    cmp #ROW_MARGIN
    bcs @below
    lda loaded_first
    beq @below
    dec loaded_first
    lda loaded_first
    jsr fill_row_buffer
    jmp row_streamed
@below:
    lda loaded_first      ; rows loaded below the view's top
    clc
    adc #NAMETABLE_ROWS
    sec
    sbc view_top_row
    cmp #(VIEW_ROWS + ROW_MARGIN)
    bcs @done
    lda loaded_first
    cmp #(FLOOR_ROWS - NAMETABLE_ROWS)
    bcs @done
    clc
    adc #NAMETABLE_ROWS
    jsr fill_row_buffer
    inc loaded_first
    jmp row_streamed
@done:
    rts

; A row is ready to send (fill_row_buffer put its nametable row in row_address); with the cheat on, its
; attribute row is worked out again, from the floor's blocks now there.
row_streamed:
    lda #1
    sta row_waiting
    lda row_address       ; the nametable row: (row_address - $2001) / 32
    sta work_0
    lda row_address + 1
    and #$03
    sta work_1
    ldx #5
@divide:
    lsr work_1
    ror work_0
    dex
    bne @divide
    lda work_0
    lsr
    lsr                   ; / 4: its attribute row
    sta cheat_row_due
    rts

; In: A = a floor row. Fills row_buffer with its tiles and row_address with where it goes.
floor_row = work_1
fill_row_buffer:
    sta floor_row
    ldx #0                ; its nametable row: floor row mod 30
@modulo:
    cmp #NAMETABLE_ROWS
    bcc @nametable_row_found
    sbc #NAMETABLE_ROWS
    jmp @modulo
@nametable_row_found:
    sta row_address       ; $2000 + row * 32 + 1
    lda #0
    sta row_address + 1
    ldx #5
@times_32:
    asl row_address
    rol row_address + 1
    dex
    bne @times_32
    inc row_address
    lda row_address + 1
    ora #$20
    sta row_address + 1
    lda shown_floor       ; the map: floor<n>_map + row * 30 (= row * 32 - row * 2)
    asl
    tax
    lda floor_maps, x
    sta map_pointer
    lda floor_maps + 1, x
    sta map_pointer + 1
    lda floor_row
    sta work_2
    lda #0
    sta work_3
    ldx #5
@row_times_32:
    asl work_2
    rol work_3
    dex
    bne @row_times_32
    lda floor_row         ; less row * 2
    asl
    sta work_4
    lda #0
    rol
    sta work_5
    lda work_2
    sec
    sbc work_4
    sta work_2
    lda work_3
    sbc work_5
    sta work_3
    lda map_pointer
    clc
    adc work_2
    sta map_pointer
    lda map_pointer + 1
    adc work_3
    sta map_pointer + 1
    ldy #0
@tile:
    lda (map_pointer), y
    sta row_buffer, y
    iny
    cpy #VIEW_COLUMNS
    bne @tile
    rts

; --- a whole floor --------------------------------------------------------------------------------------
start_drawing:
    jsr use_maps          ; (floors 4-6 have their maps in a bank of their own)
    lda floor
    sta shown_floor
    asl                   ; its tile set: 1K banks floor * 4 on
    asl
    sta background_bank
    lda #1
    sta drawing
    lda #0
    sta attributes_written
    sta screen_off
    sta draw_count
    sta row_waiting
    jsr find_view
    lda view_top_row      ; the 30 rows: from 5 above the view, kept within the floor
    sec
    sbc #5
    bcs @not_above
    lda #0
@not_above:
    cmp #(FLOOR_ROWS - NAMETABLE_ROWS + 1)
    bcc @first_found
    lda #(FLOOR_ROWS - NAMETABLE_ROWS)
@first_found:
    sta loaded_first
    sta draw_row
    rts

; With the screen off (the NMI says so), write a few rows a frame straight to the PPU; then the
; attributes, and the bands' words if they're not there yet.
continue_drawing:
    lda screen_off
    beq @done
    ldx #ROWS_PER_FRAME
@row:
    lda draw_count
    cmp #NAMETABLE_ROWS
    bcs @rows_done        ; (it goes on counting while the bands are cleared)
    txa
    pha
    lda draw_row
    jsr fill_row_buffer
    jsr write_row_now
    pla
    tax
    inc draw_row
    inc draw_count
    dex
    bne @row
@done:
    rts
@rows_done:
    lda bands_drawn
    bne @bands_there
    jsr clear_bands       ; a few frames of their own, the first time
    rts
@bands_there:
    lda attributes_written
    bne @compose
    jsr write_floor_name
    jsr write_all_attributes
    inc attributes_written   ; (the sprites and colours next frame: both in one were too much for a frame
    rts                      ; that also has a lot to touch - dying with a match lit)
@compose:
    lda #0
    sta attributes_written
    sta drawing
    jmp compose_frame

write_row_now:
    bit PPU_STATUS
    lda row_address + 1
    sta PPU_ADDRESS
    lda row_address
    sta PPU_ADDRESS
    ldx #0
@tile:
    lda row_buffer, x
    sta PPU_DATA
    inx
    cpx #VIEW_COLUMNS
    bne @tile
    rts

; The view's attributes all unlit; the bands' all the status palette.
write_all_attributes:
    ldx #0
    lda #ALL_UNLIT
@unlit:
    sta attributes, x
    inx
    cpx #64
    bne @unlit
    lda lights_on         ; the cheat: each block in its own palette
    beq @send
    jsr point_at_kinds
    lda #0
@cheat_row:
    pha
    jsr cheat_attribute_row
    pla
    clc
    adc #1
    cmp #ATTRIBUTE_ROWS
    bne @cheat_row
@send:
    bit PPU_STATUS
    lda #$23
    sta PPU_ADDRESS
    lda #$C0
    sta PPU_ADDRESS
    ldx #0
@view:
    lda attributes, x
    sta PPU_DATA
    sta attributes_sent, x
    inx
    cpx #64
    bne @view
    lda #0
    sta lit_count
    sta was_lit_count
    lda #$FF              ; and whatever the light is next, work it out
    sta last_light_key
    rts

; The second nametable: blank, with the bands' words; 8 rows a frame (its 30 rows and attributes).
band_rows_cleared = draw_count
clear_bands:
    lda draw_count        ; draw_count goes on from 30: rows of the second nametable cleared so far + 30
    sec
    sbc #NAMETABLE_ROWS
    cmp #32               ; 30 rows and the 2 rows' worth of attributes (all 0: the status palette)
    bcs @words
    sta work_0            ; $2400 + row * 32
    lda #0
    sta work_1
    ldx #5
@times_32:
    asl work_0
    rol work_1
    dex
    bne @times_32
    bit PPU_STATUS
    lda work_1
    ora #$24
    sta PPU_ADDRESS
    lda work_0
    sta PPU_ADDRESS
    lda #0
    ldy #8
@rows:
    ldx #32
@tile:
    sta PPU_DATA
    dex
    bne @tile
    inc draw_count
    dey
    bne @rows
    rts
@words:
    jsr write_band_words
    lda #1
    sta bands_drawn
    rts

; --- the palettes --------------------------------------------------------------------------------------
compose_palettes:
    lda shown_floor
    asl
    tax
    lda floor_colours, x
    sta colours_pointer
    lda floor_colours + 1, x
    sta colours_pointer + 1
    ldx #0
@status:
    lda status_colours, x
    sta palette_buffer, x
    inx
    cpx #16               ; the status palette, and three placeholders the view overwrites
    bne @status
    ldy #0                ; lit: the walls' palette and the floor's
    ldx #(WALLS * 4 + 1)
    jsr copy_three_colours
    ldy #3
    ldx #(FLOORS * 4 + 1)
    jsr copy_three_colours
    lda #0                ; unlit: in game 1 the walls, dim (the floor black); in games 2-9 black; a
    sta lightning_flash   ; lightning flash shows the walls
    jsr lightning_now
    bcc @no_lightning
    inc lightning_flash   ; (the thunder follows it: audio.s)
    ldy #FLASH_COLOURS
    jmp @unlit
@no_lightning:
    lda game_number
    bne @black
    ldy #DARK_COLOURS
@unlit:
    jsr copy_colours_to_unlit
    jmp @lit
@black:
    lda #BLACK_COLOUR
    sta palette_buffer + UNLIT * 4 + 1
    sta palette_buffer + UNLIT * 4 + 2
    sta palette_buffer + UNLIT * 4 + 3
@lit:
    ldx #0
@sprites:
    lda sprite_colours, x
    sta palette_buffer + 16, x
    inx
    cpx #16
    bne @sprites
    rts

copy_colours_to_unlit:
    ldx #(UNLIT * 4 + 1)
; In: Y = which three of the floor's colours (0 the walls', 3 the floor's, 6 the dark, 9 lightning), X = where
; in the buffer.
copy_three_colours:
    lda (colours_pointer), y
    sta palette_buffer, x
    iny
    inx
    lda (colours_pointer), y
    sta palette_buffer, x
    iny
    inx
    lda (colours_pointer), y
    sta palette_buffer, x
    rts

; Out: carry set if the walls flash this frame (spec, "Lightning").
lightning_now:
    lda death_timer
    beq @not_dying
    lda clock
    and #3
    bne @no
    jmp @coin
@not_dying:
    lda monsters_here
    beq @no
    lda lightning_off
    bne @no
    lda clock
    and #$27
    bne @no
@coin:
    lda random_low
    lsr                   ; bit 0 into the carry
    rts
@no:
    clc
    rts

; --- the light -----------------------------------------------------------------------------------------
; The blocks lit last frame back to unlit, then with a match lit, the blocks around the eyes lit or dim
; by light_levels - not beyond the room's limits in games 2-9. Each column's distance across, and each
; row's down, is worked out once; then a block is a table look-up and a masked store. Only the attribute
; bytes in lit_list (this frame's) and was_lit (last frame's) can have changed.
light_blocks:
    lda lights_on
    beq @light
    jmp cheat_blocks      ; the cheat: every block in its own palette (not the match's light)
@light:
    jsr light_key_changed
    bcs @work_it_out
    lda #0                ; the same light as last frame: nothing to do, nothing to send
    sta lit_count_same
    rts
@work_it_out:
    lda #1
    sta lit_count_same
    ldx #0
@unlight:
    cpx lit_count
    beq @unlit
    lda lit_list, x
    sta was_lit, x
    tay
    lda #ALL_UNLIT
    sta attributes, y
    inx
    jmp @unlight
@unlit:
    stx was_lit_count
    lda #0
    sta lit_count
    lda flags
    and #MATCH_LIT
    bne @lit
    rts
@lit:
    lda shown_floor       ; the floor's blocks: which take the floor's palette
    asl
    tax
    lda floor_kinds, x
    sta kinds_pointer
    lda floor_kinds + 1, x
    sta kinds_pointer + 1
    jsr measure_columns
    jsr start_rows
@each_row:
    jsr light_row
    lda block_row
    cmp block_last_row
    beq @done
    cmp #(FLOOR_ROWS / 2 - 1)
    beq @done
    inc block_row
    jsr next_row
    jmp @each_row
@done:
    rts

; Out: carry set if the light may differ from last frame's: what it depends on - a match lit, where the
; eyes are (to the light table's 4 px), the room's limits, game 1 or not, the floor - has changed.
light_key_changed:
    jsr find_eyes
    lda flags
    and #MATCH_LIT
    sta light_key
    lda eye_x
    lsr
    lsr
    sta light_key + 1
    lda eye_y + 1
    sta work_0
    lda eye_y
    lsr work_0
    ror
    lsr work_0
    ror
    sta light_key + 2
    lda room_top
    sta light_key + 3
    lda room_bottom
    sta light_key + 4
    lda game_number
    sta light_key + 5
    lda shown_floor
    sta light_key + 6
    ldx #(LIGHT_KEY_BYTES - 1)
    ldy #0                ; (1 once anything has changed: cmp uses the carry, so it can't keep the answer)
@compare:
    lda light_key, x
    cmp last_light_key, x
    beq @same
    sta last_light_key, x
    ldy #1
@same:
    dex
    bpl @compare
    cpy #1                ; the carry set if anything changed
    rts

; The eyes' centre, in nametable pixels across and floor pixels down, and the blocks around it.
find_eyes:
    lda player_x          ; across: 8 + (x + 4) * 1.5
    clc
    adc #4
    sta work_0
    lsr
    clc
    adc work_0
    adc #8
    sta eye_x
    lda #254              ; down: (254 - y) * 2
    sec
    sbc player_y
    asl
    sta eye_y
    lda #0
    rol
    sta eye_y + 1
    sta work_0            ; the eyes' block row: / 16
    lda eye_y
    ldx #4
@rows_of_16:
    lsr work_0
    ror
    dex
    bne @rows_of_16
    tax
    sec
    sbc #LIGHT_ROWS_AROUND
    bcs @first_row_found
    lda #0
@first_row_found:
    sta block_row
    txa
    clc
    adc #LIGHT_ROWS_AROUND
    sta block_last_row
    lda eye_x             ; the eyes' block column
    lsr
    lsr
    lsr
    lsr
    tax
    sec
    sbc #LIGHT_COLUMNS_AROUND
    bcs @first_column_found
    lda #0
@first_column_found:
    sta block_column
    txa
    clc
    adc #LIGHT_COLUMNS_AROUND
    cmp #16
    bcc @last_column_found
    lda #15
@last_column_found:
    sta block_last_column
    rts

; For each column i from block_column: column_distance[i] = its across distance / 4 ($FF: out of reach),
; column_byte[i] = its attribute byte's column, column_quadrant[i] = 0 or 1 (left or right block).
measure_columns:
    ldx #0
    lda block_column
    sta work_0
@column:
    lsr
    sta column_byte, x
    lda work_0
    and #1
    sta column_quadrant, x
    lda work_0
    asl
    asl
    asl
    asl
    ora #8
    sec
    sbc eye_x
    bcs @positive
    eor #$FF
    adc #1
@positive:
    cmp #LIGHT_RANGE
    bcc @in_reach
    lda #$FF
    jmp @measured
@in_reach:
    lsr
    lsr
@measured:
    sta column_distance, x
    inx
    lda work_0
    cmp block_last_column
    beq @done
    inc work_0
    lda work_0
    jmp @column
@done:
    stx column_count
    rts

; The first row: row_offset = block_row * 16 + 8 - eye_y (16 bits), its nametable block row, the floor y of
; its middle. next_row steps them on by a row.
start_rows:
    lda block_row
    sta work_0
    lda #0
    sta work_1
    ldx #4
@times_16:
    asl work_0
    rol work_1
    dex
    bne @times_16
    lda work_0
    ora #8
    sec
    sbc eye_y
    sta row_offset
    lda work_1
    sbc eye_y + 1
    sta row_offset + 1
    lda block_row
    jsr nametable_block_row
    sta light_nametable_row
    lda block_row         ; the middle's floor y: 251 - row * 8
    asl
    asl
    asl
    sta work_0
    lda #251
    sec
    sbc work_0
    sta light_floor_y
    rts

next_row:
    lda row_offset
    clc
    adc #16
    sta row_offset
    lda row_offset + 1
    adc #0
    sta row_offset + 1
    inc light_nametable_row
    lda light_nametable_row
    cmp #(NAMETABLE_ROWS / 2)
    bcc @row_found
    lda #0
    sta light_nametable_row
@row_found:
    lda light_floor_y
    sec
    sbc #8
    sta light_floor_y
    rts

; One row of blocks: if it's in reach and within the room's limits, each column's light from the table,
; into its attribute byte.
light_row:
    lda row_offset + 1
    bmi @negative
    bne @none             ; 256 px or more below
    lda row_offset
    jmp @down_found
@negative:
    cmp #$FF
    bne @none
    lda row_offset
    eor #$FF
    clc
    adc #1
@down_found:
    cmp #LIGHT_RANGE
    bcs @none
    and #$3C              ; light_levels' row: (down / 4) * 16
    asl
    asl
    sta light_row_start
    jsr within_room_limits
    bcc @none
    lda block_row         ; which of the row's blocks take the floor's palette
    asl
    tay
    lda (kinds_pointer), y
    sta row_kinds
    iny
    lda (kinds_pointer), y
    sta row_kinds + 1
    lda light_nametable_row
    and #$FE              ; the attribute bytes' row: (row / 2) * 8
    asl
    asl
    sta light_byte_row
    lda light_nametable_row
    and #1
    asl
    sta light_quadrant_row  ; 0 or 2
    ldx #0
@column:
    lda column_distance, x
    bmi @next             ; $FF: out of reach
    ora light_row_start
    tay
    lda light_levels, y
    beq @next
    jsr block_kind
    sta block_palette
    jsr set_block_palette
@next:
    inx
    cpx column_count
    bne @column
@none:
    rts

; --- the lights-on cheat -------------------------------------------------------------------------------
; Every block in the palette its art was cut in (the floor's blocks map), so the whole floor is seen. Written
; with the floor (write_all_attributes), then an attribute row again whenever a new row lands in it.
cheat_blocks:
    lda #0
    sta was_lit_count
    sta lit_count
    sta lit_count_same
    lda cheat_row_due
    bmi @done
    jsr point_at_kinds
    lda cheat_row_due
    jsr cheat_attribute_row
    lda #$FF
    sta cheat_row_due
    lda #1
    sta lit_count_same    ; (compare_attributes: something to send)
@done:
    rts

point_at_kinds:
    lda shown_floor
    asl
    tax
    lda floor_kinds, x
    sta kinds_pointer
    lda floor_kinds + 1, x
    sta kinds_pointer + 1
    rts

; In: A = a nametable attribute row (0-7). Its 8 bytes in attributes, from the floor's blocks in its two
; nametable block rows, each noted in lit_list to be sent.
cheat_attribute_row:
    sta cheat_row
    asl
    jsr kinds_at_block_row
    lda row_kinds
    sta cheat_top
    lda row_kinds + 1
    sta cheat_top + 1
    lda cheat_row
    asl
    clc
    adc #1
    jsr kinds_at_block_row   ; (block row 15 is past the nametable: it reads row 0's, unseen)
    lda cheat_row
    asl
    asl
    asl
    tax                   ; the row's first byte
    ldy #ATTRIBUTE_COLUMNS
@byte:
    sty cheat_left
    lda cheat_top         ; the top two blocks' palettes...
    and #3
    tay
    lda pair_palettes, y
    sta work_0
    lda row_kinds         ; ...and the bottom two's
    and #3
    tay
    lda pair_palettes, y
    asl
    asl
    asl
    asl
    ora work_0
    sta attributes, x
    ldy lit_count
    txa
    sta lit_list, y
    inc lit_count
    ldy #2                ; on two columns
@shift:
    lsr cheat_top + 1
    ror cheat_top
    lsr row_kinds + 1
    ror row_kinds
    dey
    bne @shift
    inx
    ldy cheat_left
    dey
    bne @byte
    rts

; In: A = a nametable block row (0-14). Out: row_kinds: the floor's block row that's there now. The loaded
; rows are floor rows loaded_first to loaded_first + 29, each at its nametable row mod 30.
kinds_at_block_row:
    asl                   ; its first nametable tile row
    sta work_0
    lda loaded_first      ; less loaded_first's nametable row, mod 30: how far past loaded_first
    jsr nametable_tile_row
    sta work_1
    lda work_0
    sec
    sbc work_1
    bcs @past
    adc #NAMETABLE_ROWS
@past:
    clc
    adc loaded_first      ; the floor tile row, then its block row
    lsr
    asl                   ; * 2 bytes a row of kinds
    tay
    lda (kinds_pointer), y
    sta row_kinds
    iny
    lda (kinds_pointer), y
    sta row_kinds + 1
    rts

; In: A = a floor tile row. Out: A = its nametable row (mod 30).
nametable_tile_row:
@modulo:
    cmp #NAMETABLE_ROWS
    bcc @found
    sbc #NAMETABLE_ROWS
    jmp @modulo
@found:
    rts

; In: X = the column (in the row's columns). Out: A = its lit palette, as set_block_palette takes it: 1 the
; walls', 2 the floor's (row_kinds: a bit per block column). Keeps X.
block_kind:
    txa
    clc
    adc block_column
    cmp #8                ; the carry: the right half's byte...
    and #7                ; (and and lda leave the carry be)
    tay
    lda row_kinds
    bcc @half_found
    lda row_kinds + 1
@half_found:
    and bits, y
    beq @walls
    lda #(FLOORS - UNLIT)
    rts
@walls:
    lda #(WALLS - UNLIT)
    rts

; In: A = a floor block row. Out: A = its row in the nametable's blocks (mod 15).
nametable_block_row:
@modulo:
    cmp #(NAMETABLE_ROWS / 2)
    bcc @found
    sbc #(NAMETABLE_ROWS / 2)
    jmp @modulo
@found:
    rts

; Out: carry set if this row may be lit: always in game 1; in games 2-9 its middle's floor y must be
; within the room's limits (an unset top limit is none).
within_room_limits:
    lda game_number
    beq @yes
    lda light_floor_y
    cmp room_bottom
    bcc @no
    ldx room_top
    beq @yes
    cmp room_top
    beq @yes
    bcs @no
@yes:
    sec
    rts
@no:
    clc
    rts

; In: X = the column (in the row's columns), block_palette = its lit palette (1 the walls', 2 the floor's: the
; palette less UNLIT). Its two bits in its
; attribute byte, noting the byte the first time it's lit this frame. Keeps X.
set_block_palette:
    lda column_byte, x
    ora light_byte_row
    tay
    lda column_quadrant, x
    ora light_quadrant_row
    sta work_7            ; the quadrant
    asl
    asl
    ora block_palette
    clc
    adc #UNLIT            ; (quadrant * 4 + palette) for palette_bits
    sta work_6
    stx work_8
    lda attributes, y
    cmp #ALL_UNLIT        ; the first block lit in this byte: note the byte
    bne @noted
    ldx lit_count
    pha
    tya
    sta lit_list, x
    pla
    inc lit_count
@noted:
    ldx work_7
    and keep_other_blocks, x
    ldx work_6
    ora palette_bits, x
    sta attributes, y
    ldx work_8
    rts

; The bytes lit this frame or last, where they differ from what the PPU has.
compare_attributes:
    ldy #0
    lda lit_count_same
    bne @worked_out
    sty changed_count     ; the light didn't change
    rts
@worked_out:
    ldx #0
@this_frame:
    cpx lit_count
    beq @last_frame
    lda lit_list, x
    jsr compare_one
    inx
    jmp @this_frame
@last_frame:
    ldx #0
@each_was_lit:
    cpx was_lit_count
    beq @done
    lda was_lit, x
    jsr compare_one
    inx
    jmp @each_was_lit
@done:
    sty changed_count
    rts

; In: A = an attribute byte's index; Y = the changes so far. Out: Y + 1 if it changed. Keeps X.
compare_one:
    stx work_8
    tax
    lda attributes, x
    cmp attributes_sent, x
    beq @same
    sta attributes_sent, x
    sta changed_value, y
    txa
    sta changed_index, y
    iny
@same:
    ldx work_8
    rts

; --- the bands' words ----------------------------------------------------------------------------------
STATUS_LABELS_ROW = 1
STATUS_VALUES_ROW = 2
NAME_ROW = 26
GAME_ROW = 28

.macro place row, column
    .byte >($2400 + (row) * 32 + (column)), <($2400 + (row) * 32 + (column))
.endmacro

write_band_words:
    ldx #0
@word:
    lda band_words, x
    beq @eyes
    bit PPU_STATUS
    sta PPU_ADDRESS
    inx
    lda band_words, x
    sta PPU_ADDRESS
    inx
    lda band_words, x     ; the ink
    sta work_0
    inx
@letter:
    lda band_words, x
    inx
    cmp #$FF
    beq @word
    clc
    adc work_0
    sta PPU_DATA
    jmp @letter
@eyes:                    ; the lives' eyes
    bit PPU_STATUS
    lda lives_eyes_place
    sta PPU_ADDRESS
    lda lives_eyes_place + 1
    sta PPU_ADDRESS
    lda #LIVES_EYES
    sta PPU_DATA
    lda #(LIVES_EYES + 1)
    sta PPU_DATA
    lda #$FF              ; and send every changing tile afresh
    ldx #(STATUS_TILES - 1)
@unsent:
    sta status_sent, x
    dex
    bpl @unsent
    rts

; The floor's name, centred in the band below (its row cleared first).
write_floor_name:
    bit PPU_STATUS
    lda #>($2400 + NAME_ROW * 32)
    sta PPU_ADDRESS
    lda #<($2400 + NAME_ROW * 32)
    sta PPU_ADDRESS
    lda #0
    ldx #32
@clear:
    sta PPU_DATA
    dex
    bne @clear
    lda shown_floor
    asl
    tax
    lda floor_names, x
    sta map_pointer
    lda floor_names + 1, x
    sta map_pointer + 1
    ldy #0
@length:
    lda (map_pointer), y
    cmp #$FF
    beq @measured
    iny
    jmp @length
@measured:
    sty work_0            ; start at column (32 - length) / 2
    lda #32
    sec
    sbc work_0
    lsr
    clc
    adc #<($2400 + NAME_ROW * 32)
    bit PPU_STATUS
    ldx #>($2400 + NAME_ROW * 32)
    stx PPU_ADDRESS
    sta PPU_ADDRESS
    ldy #0
@letter:
    lda (map_pointer), y
    cmp #$FF
    beq @done
    sta PPU_DATA
    iny
    jmp @letter
@done:
    rts

; The status band's changing tiles (status_places, in order): the matches used, the burning match, what's
; held, the urn so far, lives, the game and the floor. Each frame they're worked out into status_wanted
; (X counts through them); those that differ from status_sent are listed for the NMI.
STATUS_TILES = 24
STATUS_KEY_BYTES = 10
compose_status:
    jsr status_key_changed
    bcs @work_it_out
    lda #0                ; nothing it shows has changed
    sta status_count
    rts
@work_it_out:
    ldx #0
    lda matches_used
    lsr
    lsr
    lsr
    lsr
    jsr want_digit
    lda matches_used
    and #$0F
    jsr want_digit
    jsr want_match_bar
    jsr want_held
    jsr want_urn
    lda lives
    jsr want_digit
    lda game_number
    clc
    adc #(1 + GREY_TEXT)
    jsr want_digit
    lda shown_floor       ; the floor's number: 1 for the front door's, B below it
    sec
    sbc #FRONT_DOOR_FLOOR
    bcc @below_ground
    adc #GREY_TEXT        ; (+ 1: the carry is set)
    jsr want_digit
    jmp list_changed_status
@below_ground:
    lda #('B' + GREY_TEXT)
    jsr want_tile
    jmp list_changed_status

; Out: carry set if anything the status band shows has changed since last frame.
status_key_changed:
    lda matches_used
    sta status_key
    lda flags
    and #MATCH_LIT
    beq @unlit
    lda match_time        ; (the burning match only while lit)
@unlit:
    sta status_key + 1
    lda carried
    sta status_key + 2
    lda urn_shapes
    sta status_key + 3
    lda urn_shapes + 1
    sta status_key + 4
    lda urn_shapes + 2
    sta status_key + 5
    lda lives
    sta status_key + 6
    lda game_number
    sta status_key + 7
    lda shown_floor
    sta status_key + 8
    lda status_sent       ; the bands redrawn: everything goes again
    sta status_key + 9
    ldx #(STATUS_KEY_BYTES - 1)
    clc
@compare:
    lda status_key, x
    cmp last_status_key, x
    beq @same
    sta last_status_key, x
    sec
@same:
    dex
    bpl @compare
    rts

; In: A = a digit (plus GREY_TEXT for grey), X = its place. Out: X + 1.
want_digit:
    clc
    adc #DIGIT_ZERO
; In: A = a tile, X = its place. Out: X + 1, A kept.
want_tile:
    sta status_wanted, x
    inx
    rts

; The burning match: the ember as long as the seconds left, in pixels, then 3 of flame (3 tiles).
bar_length = work_9
bar_pixel = work_10
want_match_bar:
    lda flags
    and #MATCH_LIT
    bne @lit
    lda #0
    jsr want_tile
    jsr want_tile
    jmp want_tile
@lit:
    lda match_time
    sta bar_length
    lda #0
    sta bar_pixel         ; the tile's first pixel
@tile:
    lda bar_pixel
    clc
    adc #7
    cmp bar_length
    bcs @not_all_ember
    lda #BAR_EMBER        ; the whole tile is ember
    jmp @found
@not_all_ember:
    lda bar_length
    sec
    sbc bar_pixel
    bcc @spill
    clc                   ; the ember ends in this tile, and the flame starts
    adc #BAR_END
    jmp @found
@spill:
    eor #$FF              ; past the end: the flame's first (tile's first - length) columns are behind;
    clc                   ; 3 - that spill into this tile
    adc #1
    sta work_11
    lda #FLAME
    sec
    sbc work_11
    beq @blank
    bmi @blank
    clc
    adc #BAR_FLAME
    jmp @found
@blank:
    lda #0
@found:
    jsr want_tile
    lda bar_pixel
    clc
    adc #8
    sta bar_pixel
    cmp #(8 * BAR_TILE_COUNT)
    bne @tile
    rts

; What's held: its slot (2 x 2 tiles), or an empty one.
want_held:
    lda carried
    cmp #NOTHING
    beq @empty
    cmp #URN
    bcc @item             ; the key 0 or the scepter 1
    tay
    lda urn_shapes - URN, y   ; an urn piece: its shape, 2-8
@item:
    asl
    asl
    clc
    adc #SLOT_ITEMS
    jmp want_slot
@empty:
    lda #SLOT_EMPTY
; In: A = a slot's first tile, X = its place. Its four tiles, in order. Out: X + 4.
want_slot:
    jsr want_tile
    clc
    adc #1
    jsr want_tile
    clc
    adc #1
    jsr want_tile
    clc
    adc #1
    jmp want_tile

; The urn so far (the remaster's rule): the pieces held, or else the biggest group of pieces joined
; together - a lone piece on the floor doesn't count. A slot for each piece, filled if it's in.
urn_best = work_9
urn_piece = work_10
want_urn:
    stx status_place
    lda carried
    cmp #NOTHING
    beq @on_the_floor
    cmp #URN
    bcc @on_the_floor
    tay
    lda urn_shapes - URN, y
    jsr shape_pieces
    sta urn_best
    jmp @slots
@on_the_floor:
    lda #0
    sta urn_best
    ldx #0
@group:
    lda urn_shapes, x
    jsr shape_pieces
    tay
    lda pieces_counted, y
    sta work_11
    ldy urn_best
    lda pieces_counted, y
    cmp work_11
    bcs @not_bigger
    lda urn_shapes, x
    jsr shape_pieces
    sta urn_best
@not_bigger:
    inx
    cpx #3
    bne @group
    ldy urn_best          ; one piece alone isn't the urn mended
    lda pieces_counted, y
    cmp #2
    bcs @slots
    lda #0
    sta urn_best
@slots:
    ldx status_place
    lda #0
    sta urn_piece
@slot:
    ldy urn_piece
    lda urn_best
    and bits, y
    beq @empty
    tya                   ; piece 2-4's own slot: shape 2-4
    clc
    adc #URN
    asl
    asl
    clc
    adc #SLOT_ITEMS
    jmp @want
@empty:
    lda #SLOT_EMPTY
@want:
    jsr want_slot
    inc urn_piece
    lda urn_piece
    cmp #3
    bne @slot
    rts

; In: A = an urn shape. Out: A = its pieces, a bit each ($FF, joined into another: none). Uses Y.
shape_pieces:
    cmp #9
    bcs @none
    tay
    lda pieces_of_shape, y
    rts
@none:
    lda #0
    rts

list_changed_status:
    ldy #0
    ldx #0
@each:
    lda status_wanted, x
    cmp status_sent, x
    beq @same
    sta status_sent, x
    sta status_tile, y
    stx status_place
    txa
    asl
    tax
    lda status_places, x
    sta status_address_high, y
    lda status_places + 1, x
    sta status_address_low, y
    ldx status_place
    iny
@same:
    inx
    cpx #STATUS_TILES
    bne @each
    sty status_count
    rts

.segment "RODATA"
BLACK_COLOUR = $0F
status_colours:   .byte BLACK_COLOUR, $30, $10, $27,  BLACK_COLOUR, 0, 0, 0
                  .byte BLACK_COLOUR, 0, 0, 0,        BLACK_COLOUR, 0, 0, 0
sprite_colours:   .byte BLACK_COLOUR, $30, $10, $27,  BLACK_COLOUR, $30, $10, $00
                  .byte BLACK_COLOUR, $24, $14, $30,  BLACK_COLOUR, $16, $27, $12
keep_other_blocks: .byte %11111100, %11110011, %11001111, %00111111
pair_palettes:    ; two blocks side by side, by their kinds (bit 0 the left): their palettes, as two quadrants
    .byte WALLS | WALLS << 2, FLOORS | WALLS << 2, WALLS | FLOORS << 2, FLOORS | FLOORS << 2
palette_bits:     ; a palette 0-3 in each of the four blocks of an attribute byte
    .byte $00, $01, $02, $03,  $00, $04, $08, $0C,  $00, $10, $20, $30,  $00, $40, $80, $C0
status_places:    ; where each changing tile goes (compose_status's order)
    place STATUS_VALUES_ROW, 1          ; the matches used
    place STATUS_VALUES_ROW, 2
    place STATUS_VALUES_ROW, 3          ; the burning match
    place STATUS_VALUES_ROW, 4
    place STATUS_VALUES_ROW, 5
    place STATUS_VALUES_ROW, 11         ; what's held
    place STATUS_VALUES_ROW, 12
    place STATUS_VALUES_ROW + 1, 11
    place STATUS_VALUES_ROW + 1, 12
    place STATUS_VALUES_ROW, 15         ; the urn's three slots
    place STATUS_VALUES_ROW, 16
    place STATUS_VALUES_ROW + 1, 15
    place STATUS_VALUES_ROW + 1, 16
    place STATUS_VALUES_ROW, 17
    place STATUS_VALUES_ROW, 18
    place STATUS_VALUES_ROW + 1, 17
    place STATUS_VALUES_ROW + 1, 18
    place STATUS_VALUES_ROW, 19
    place STATUS_VALUES_ROW, 20
    place STATUS_VALUES_ROW + 1, 19
    place STATUS_VALUES_ROW + 1, 20
    place STATUS_VALUES_ROW, 28         ; lives
    place GAME_ROW, 6                   ; the game
    place GAME_ROW, 30                  ; the floor
pieces_of_shape:  .byte 0, 0, 1, 2, 4, 3, 5, 6, 7   ; an urn shape's pieces, a bit each
pieces_counted:   .byte 0, 1, 1, 2, 1, 2, 2, 3      ; how many bits
band_words:       ; where, the ink (0 white, GREY_TEXT grey), the letters, $FF; a 0 ends the list
    place STATUS_LABELS_ROW, 1
    .byte GREY_TEXT, "MATCHES", $FF
    place STATUS_LABELS_ROW, 10
    .byte GREY_TEXT, "HOLD", $FF
    place STATUS_LABELS_ROW, 16
    .byte GREY_TEXT, "URN", $FF
    place STATUS_LABELS_ROW, 25
    .byte GREY_TEXT, "LIVES", $FF
    place STATUS_VALUES_ROW, 27
    .byte 0, "X", $FF
    place GAME_ROW, 1
    .byte GREY_TEXT, "GAME", $FF
    place GAME_ROW, 24
    .byte GREY_TEXT, "FLOOR", $FF
    .byte 0
lives_eyes_place:
    place STATUS_VALUES_ROW, 25
.segment "CODE"
