; The NES's own bytes: everything besides the game's state (state.inc), declared before any code uses
; them so the assembler can use their short (zero page) addresses.

VIEW_COLUMNS = 30         ; the view's tiles across

.segment "ZEROPAGE"
frame_count:    .res 1    ; +1 every frame, from the NMI
ready:          .res 1    ; $42 once the console is set up (the boot check looks for it)
frame_started:  .res 1    ; set by the NMI: time for the next game frame
pad:            .res 1    ; the controller: bit 7 A, 6 B, 5 Select, 4 Start, 3 up, 2 down, 1 left, 0 right
stick:          .res 1    ; the D-pad as the 2600 joystick (STICK_ bits)
button_down:    .res 1    ; A, the joystick's button: not 0 while held
reset_down:     .res 1    ; Start, the console's RESET switch
select_down:    .res 1    ; Select, the console's SELECT switch
busy:           .res 1    ; not 0 while a game frame is worked out
late_frames:    .res 1    ; frames the work ran past the next frame's start (the checks look for 0)
spare:          .res 2    ; counts while the main loop waits for the next frame...

; touching (touching.s): what this frame's sprite touched
touched_eyes:   .res 1    ; not 0: the sprite overlapped the eyes
touched_walls:  .res 1    ; not 0: the sprite overlapped a wall
sprite_wide:    .res 1    ; not 0: this frame's sprite is the stairs, drawn at double width
line_top:       .res 1    ; the first line drawn
line_below:     .res 1    ; the line below the last one drawn
touch_row:      .res 1    ; ...its pixels...
wall_line:      .res 1    ; the line being tested
eyes_now:       .res 1    ; the eyes' row on it
eyes_rows:      .res 3    ; the eyes' picture, bottom row first
touch_column:   .res 1    ; the row's first column
touch_y:        .res 1    ; the floor y of wall_line
touch_wide_high: .res 1   ; the row as 16 columns
touch_wide_low: .res 1
touch_mask_high: .res 1   ; the columns in the first wall cell...
touch_mask_low: .res 1
touch_pixels:   .res 1
touch_count:    .res 1
walls_line:     .res 1    ; the line whose walls are in walls_high/low...
walls_row:      .res 1    ; the wall row whose walls they are
walls_high:     .res 1
walls_low:      .res 1
walls_on_line:  .res 1    ; ...0 if that line isn't on the floor
touch_wall_row: .res 1    ; the wall plan's row of touch_y
touch_lines_left: .res 1


; ppu.s
.segment "ZEROPAGE"
render_ready:   .res 1    ; not 0: this frame's buffers are filled, send them in the next vertical blank
drawing:        .res 1    ; not 0: a whole floor is being drawn, with the screen off
screen_off:     .res 1    ; not 0: the NMI has turned the screen off (the main loop may write to the PPU)
irq_stage:      .res 1    ; which split comes next: 0 the view, 1 the band below
scroll_y:       .res 1    ; the view's scroll in the first nametable, 0-239
split_low:      .res 1    ; the PPU address's low byte for that scroll (worked out ahead, for the interrupt)
shown_floor:    .res 1    ; the floor whose tiles are in the first nametable ($FF: none yet)

; view.s
.segment "ZEROPAGE"
view_top:       .res 2    ; the view's top, in floor pixels (0-352)
view_top_row:   .res 1    ; ...in tile rows
loaded_first:   .res 1    ; the first of the 30 floor rows in the nametable
row_waiting:    .res 1    ; not 0: row_buffer is to be sent to row_address
row_address:    .res 2
map_pointer:    .res 2
colours_pointer: .res 2

.segment "BSS"
palette_buffer: .res 32
row_buffer:     .res VIEW_COLUMNS
attributes:     .res 64   ; the first nametable's attributes as they should be...
attributes_sent: .res 64  ; ...and as the PPU has them
changed_count:  .res 1
lit_list:       .res 32
was_lit:        .res 32
changed_index:  .res 64
changed_value:  .res 64
status_count:   .res 1
status_address_high: .res 24
status_address_low: .res 24
status_tile:    .res 24
status_wanted:  .res 24   ; the status band's changing tiles, as they should be...
status_sent:    .res 24   ; ...and as the PPU has them
status_place:   .res 1
status_key:     .res 10   ; what the status band shows, this frame...
last_status_key: .res 10  ; ...and last

; sprites.s
.segment "ZEROPAGE"
draw_pointer:   .res 2    ; the picture being drawn...
draw_centre_x:  .res 1    ; ...its centre on screen...
draw_centre_y:  .res 2
draw_palette:   .res 1    ; ...its sprite palette...
draw_mirror:    .res 1    ; ...and $40 if mirrored
picture_width:  .res 1
picture_padded: .res 1
picture_top:    .res 2
picture_left:   .res 1
pieces_left:    .res 1
oam_next:       .res 1    ; the next free place in the sprite table...
oam_full:       .res 1    ; ...or not 0 when all 64 are used
oam_used:       .res 1    ; how far last frame's sprites went in the table
thing_x:        .res 1    ; a thing on the floor: where, and how tall
thing_y:        .res 1
thing_height:   .res 1
.segment "BSS"
slot_kind:      .res 4    ; the kind each sprite palette has this frame
monster_last_floor: .res 5
monster_last_x: .res 5
monster_last_y: .res 5
monster_facing: .res 5
monster_still:  .res 5    ; frames since it last moved

; moved out of the zero page, which is full (the game's state takes its top half)
.segment "BSS"
last_spare:     .res 2    ; ...and last frame's count (x 13 cycles: its spare time)
work_part:      .res 1    ; which part the work is in: 1 the game, 2 the picture...
late_part:      .res 1    ; ...and which part it was in when a frame ran late
draw_row:       .res 1    ; drawing a whole floor: the next row...
draw_count:     .res 1    ; ...and how many are done
bands_drawn:    .res 1    ; not 0: the status band and the band below have their words
eye_x:          .res 1    ; the eyes' centre in nametable pixels...
eye_y:          .res 2    ; ...and in floor pixels
block_row:      .res 1
block_column:   .res 1
block_last_row: .res 1
block_last_column: .res 1
light_row_start: .res 1  ; the light: light_levels' row for this block row
light_byte_row: .res 1    ; ...the attribute bytes' row...
light_quadrant_row: .res 1  ; ...and the upper or lower pair of blocks in them
block_palette:  .res 1
column_distance: .res 8   ; each column's distance across, / 4 ($FF: out of reach)...
column_byte:    .res 8    ; ...its attribute byte's column...
column_quadrant: .res 8   ; ...and its left or right block
column_count:   .res 1
row_offset:     .res 2    ; a row of blocks' middle, less the eyes' y, in floor pixels
light_nametable_row: .res 1
light_floor_y:  .res 1
lit_count_same: .res 1    ; 0: the light is as last frame's
light_key:      .res 7    ; what the light depends on, this frame...
last_light_key: .res 7    ; ...and last
lit_count:      .res 1    ; the attribute bytes the light changed this frame...
was_lit_count:  .res 1    ; ...and last frame
lightning_off:  .res 1    ; the left difficulty switch on A: no lightning (a setting, for now always B)
drawn_monster:  .res 1
drawn_item:     .res 1
animation_clock: .res 1
blink_clock:    .res 1
hand_side:      .res 1    ; the side the match is held: STICK_LEFT or STICK_RIGHT

.segment "CODE"
