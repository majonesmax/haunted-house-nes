; The mansion's tables, floor by floor (docs/plan.md, step 7): each table in mansion.inc that can differ
; from floor to floor holds one part per floor, one after another, and a read adds that floor's start.
; The faithful build's four parts are all the original's one plan; the new mansion's six are its own.
; (The rooms are a 2 x 3 grid on every floor, so room_step and the waypoints' kinds are shared.)

.if FLOOR_COUNT <= 4
    FLOOR_MASK = 3        ; a random floor: the random bits kept, tried again if past the last floor
.else
    FLOOR_MASK = 7
.endif

.macro floor_starts part_size
    .repeat FLOOR_COUNT, floor_number
        .byte floor_number * (part_size)
    .endrepeat
.endmacro

; Y = Y in the player's floor's part of a table, from that table's starts (walls_from, ...). Uses A.
.macro on_this_floor starts
    stx kept_x
    tya
    ldx floor
    clc
    adc starts, x
    tay
    ldx kept_x
.endmacro

.segment "RODATA"
walls_from:       floor_starts MANSION_WALLS_SIZE
doors_from:       floor_starts DOOR_IDS_SIZE
rooms_from:       floor_starts STAIRS_X_SIZE        ; per room: stairs_edge, stairs_x
edges_from:       floor_starts STAIRS_Y_SIZE
bounds_from:      floor_starts ROOM_BOUNDS_SIZE
crossings_from:   floor_starts DOORWAY_LINES_SIZE
waypoints_from:   floor_starts WAYPOINT_X_SIZE
.segment "CODE"

; In: A = a room, Y = a direction, X = a floor. Out: A = that way out of the room: its door_ids entry.
; Uses Y.
door_way_out:
    asl
    asl
    sty door_direction
    clc
    adc door_direction
    adc doors_from, x
    tay
    lda door_ids, y
    rts
