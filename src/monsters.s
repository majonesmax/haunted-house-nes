; The monsters (spec, "Monsters"; the remaster's game/monsters.py is the exact rule): they walk between
; waypoints, chase the player in their room, follow the player out of it (games 6-9), and are scattered
; on a new game and after a death.

KIND_CENTRE = 0
KIND_DOOR = 1
KIND_STAIRS_DOWN = 2
KIND_STAIRS_UP = 3

monster = work_0
phase = work_1            ; the clock's low 3 bits: which frame of 8
step_now = work_2         ; not 0: this monster steps this frame
target_x = work_3
target_y = work_4
wander_step = work_5

; One frame of monster movement.
move_monsters:
    lda clock
    and #7
    sta phase
    tax
    lda #WANDER_FRAMES
    and bits, x
    sta wander_step
    lda #0
    sta monsters_here
    lda last_monster
    sta monster
@each:
    jsr choose_target     ; carry set: step towards target_x, target_y
    bcc @next
    jsr step_towards
@next:
    dec monster
    bpl @each
    jmp handle_one_arrival

; Where the monster steps this frame. Out: carry set and target_x/y, or carry clear to stand still.
choose_target:
    jsr in_players_room
    bcc @not_here
    inc monsters_here
    lda death_timer       ; the player dying: it wanders
    bne @wander
    jsr scepter_keeps_away
    bcs @wander
    jsr chases_this_frame
    bcc @still
    jmp chase_point
@not_here:
    ldx monster
    lda following
    and bits, x
    beq @wander
    jsr chases_this_frame ; sent after the player: chasing speed, along its plan
    bcc @still
    jmp route_point
@wander:
    lda wander_step
    beq @still
    jmp route_point
@still:
    clc
    rts

; Out: carry set if the monster is on the player's floor in the player's room (or the room beyond).
in_players_room:
    ldx monster
    lda monster_floor, x
    cmp floor
    bne @no
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

; Out: carry set if the player's scepter keeps this monster from chasing (the ghost ignores it in 8-9).
scepter_keeps_away:
    lda carried
    cmp #SCEPTER
    bne @no
    lda monster
    bne @yes
    lda game_number
    cmp #FIRST_FAST_GAME
    bcs @no
@yes:
    sec
    rts
@no:
    clc
    rts

; Out: carry set if a chasing monster steps on this frame (its speed, faster in games 8-9).
chases_this_frame:
    ldx monster
    ldy phase
    lda game_number
    cmp #FIRST_FAST_GAME
    bcs @fast
    lda monster_speed, x
    jmp @test
@fast:
    lda monster_speed_fast, x
@test:
    and bits, y
    beq @no
    sec
    rts
@no:
    clc
    rts

; The point near the player it heads for: the player's x and y less an offset each; an offset that would
; go below 0 isn't taken at all (spec: the quirk worth keeping).
chase_point:
    ldx monster
    lda player_x
    sec
    sbc chase_offset_x, x
    bcs @x_found
    lda player_x
@x_found:
    sta target_x
    lda player_y
    sec
    sbc chase_offset_y, x
    bcs @y_found
    lda player_y
@y_found:
    sta target_y
    sec
    rts

; Its plan's waypoint; if it's already there, it's arrived and stands still.
route_point:
    ldx monster
    lda monster_route, x
    jsr waypoint_of
    ldx monster
    lda monster_x, x
    cmp target_x
    bne @go
    lda monster_y, x
    cmp target_y
    bne @go
    lda arrived
    ora bits, x
    sta arrived
    clc
    rts
@go:
    sec
    rts

; In: A = a plan. Out: target_x, target_y = its waypoint. Uses Y.
waypoint_of:
    pha
    and #$3F
    lsr
    lsr
    lsr
    lsr
    tay                   ; the kind
    pla
    and #$0F              ; the target
    clc
    adc waypoint_start, y
    ldx monster           ; on the monster's floor
    ldy monster_floor, x
    clc
    adc waypoints_from, y
    tay
    lda waypoint_x, y
    sta target_x
    lda waypoint_y, y
    sta target_y
    rts

; One unit towards the target in x and in y at once. A step left that would reach x = 0 is undone.
step_towards:
    ldx monster
    lda monster_x, x
    cmp target_x
    beq @y
    bcc @right
    dec monster_x, x
    bne @y
    inc monster_x, x
    jmp @y
@right:
    inc monster_x, x
@y:
    lda monster_y, x
    cmp target_y
    beq @done
    bcc @up
    dec monster_y, x
    rts
@up:
    inc monster_y, x
@done:
    rts

; --- arriving ------------------------------------------------------------------------------------------
; Only the lowest-numbered arrived monster gets a new plan this frame; the others wait their turn.
handle_one_arrival:
    ldx #0
@each:
    lda arrived
    and bits, x
    bne @found
    inx
    cpx last_monster
    beq @each
    bcc @each
    rts
@found:
    lda arrived
    eor bits, x
    sta arrived
    stx monster
    jmp new_plan

came_from = work_6
first_try = work_7
tried = work_8
plan_room = work_9

new_plan:
    ldx monster
    lda monster_route, x
    and #$30
    beq pick_direction    ; at a room centre
    cmp #(KIND_DOOR << 4)
    bne @stairs
    lda monster_route, x  ; through a door: into the next room, heading for its centre
    rol                   ; the direction (bits 7-6) down to bits 1-0
    rol
    rol
    and #3
    tay
    lda monster_room, x
    clc
    adc room_step, y
    sta monster_room, x
    lda monster_route, x
    and #$C0
    ora monster_room, x
    sta monster_route, x
    rts
@stairs:
    cmp #(KIND_STAIRS_UP << 4)
    beq @up
    dec monster_floor, x
    jmp @new_floor
@up:
    inc monster_floor, x
@new_floor:               ; the centre of the same room; the stairs now count as the way it came
    lda monster_route, x
    and #$C0
    eor #$40
    ora monster_room, x
    sta monster_route, x
    rts

; At a room centre: try the directions in turn from a random one, skipping the way it came; if none will
; do, go back the way it came.
pick_direction:
    lda monster_route, x
    rol
    rol
    rol
    and #3
    eor #1
    sta came_from
    lda random_low
    and #3
    sta first_try
    sta tried
@try:
    lda tried
    cmp came_from
    beq @next
    jsr try_direction
    bcs @done
@next:
    lda tried
    clc
    adc #1
    and #3
    sta tried
    cmp first_try
    bne @try
    lda came_from
    sta tried
    jmp try_direction
@done:
    rts

; In: tried = a direction. Sets a plan to leave the room that way, if the monster may. Out: carry set if so.
try_direction:
    ldx monster
    lda monster_room, x
    sta plan_room
    ldy tried
    lda monster_floor, x
    tax
    lda plan_room
    jsr door_way_out      ; (on the monster's floor)
    ldx monster
    cmp #$FF
    beq @no
    cmp #$80
    bcc @door
    lda monster_floor, x  ; the room's outer edge: only if it has stairs on this floor
    jsr floor_index
    tay
    ldx plan_room
    lda stairs_here, y
    and bits, x
    beq @no
    lda stairs_go_up, y
    and bits, x
    beq @down
    lda #(KIND_STAIRS_UP << 4)
    jmp @set
@down:
    lda #(KIND_STAIRS_DOWN << 4)
@set:
    ora plan_room
    jmp @plan
@door:
    pha
    ldx monster
    ldy monster_floor, x
    jsr door_locked
    bcc @may_pass
    jsr may_pass_locks
    bcs @may_pass
    pla
    jmp @no
@may_pass:
    pla
    ora #(KIND_DOOR << 4)
@plan:
    sta target_x          ; (a spare byte here)
    lda tried
    lsr
    ror
    ror                   ; the direction up to bits 7-6
    ora target_x
    ldx monster
    sta monster_route, x
    sec
    rts
@no:
    clc
    rts

; Out: carry set if this monster may use locked doors: the ghost, or any in game 9.
may_pass_locks:
    lda monster
    beq @yes
    lda game_number
    cmp #GAME_9
    beq @yes
    clc
    rts
@yes:
    sec
    rts

; --- following the player (games 6-9) -----------------------------------------------------------------
plan = work_6
only_ghost = work_7

; In: A = the direction the player left the room by (room = the room left). Through a locked door only
; the ghost follows.
follow_through_door:
    tay
    lda game_number
    cmp #FIRST_FOLLOW_GAME
    bcc @done
    tya
    sta work_8
    lsr
    ror
    ror
    ora #(KIND_DOOR << 4)
    sta plan
    lda room              ; (the player's room and floor, as the original has it)
    ldy work_8
    ldx floor
    jsr door_way_out
    pha
    ora plan
    sta plan
    pla
    ldy floor
    jsr door_locked
    lda #0
    rol                   ; carry: locked
    sta only_ghost
    jmp send_followers
@done:
    rts

; The player is taking this room's stairs: the monsters here follow.
follow_up_stairs:
    lda game_number
    cmp #FIRST_FOLLOW_GAME
    bcc @done
    lda stairs
    and #3                ; the edge
    lsr
    ror
    ror
    sta plan
    lda stairs
    and #GOES_UP
    beq @down
    lda #(KIND_STAIRS_UP << 4)
    jmp @kind_found
@down:
    lda #(KIND_STAIRS_DOWN << 4)
@kind_found:
    ora plan
    ora room
    sta plan
    lda #0
    sta only_ghost
    jmp send_followers
@done:
    rts

; Give every monster on the player's floor in this room the plan, and mark them following.
send_followers:
    lda #0
    sta following
    ldx last_monster
    lda only_ghost
    beq @each
    ldx #GHOST
@each:
    lda monster_floor, x
    cmp floor
    bne @next
    lda monster_room, x
    cmp room
    bne @next
    lda plan
    sta monster_route, x
    lda following
    ora bits, x
    sta following
@next:
    lda only_ghost
    bne @done
    dex
    bpl @each
@done:
    rts

; --- scattering ----------------------------------------------------------------------------------------
base_room = work_6

; All five to random room centres on random floors - never the player's room on the player's floor.
scatter:
@pick_base:
    jsr next_random
    and #7
    cmp #ROOM_COUNT
    bcs @pick_base
    sta base_room
    ldx #4
@each:
    stx monster
@pick_floor:
    jsr next_random
    and #FLOOR_MASK
    cmp #FLOOR_COUNT
    bcs @pick_floor       ; (never with four floors: as the original)
    ldx monster
    sta monster_floor, x
    txa
    clc
    adc base_room
    jsr modulo_rooms
    cmp room
    bne @placed
    ldy monster_floor, x
    cpy floor
    bne @placed
    lda base_room         ; in the player's room: the room before the run instead
    clc
    adc #(ROOM_COUNT - 1)
    jsr modulo_rooms
@placed:
    sta monster_room, x
    sta monster_route, x
    ldy monster_floor, x  ; the room's centre: waypoints 0-5 on its floor
    clc
    adc waypoints_from, y
    tay
    lda waypoint_x, y
    sta monster_x, x
    lda waypoint_y, y
    sta monster_y, x
    dex
    bpl @each
    rts

; In: A = a room number up to twice the count. Out: A mod ROOM_COUNT.
modulo_rooms:
    cmp #ROOM_COUNT
    bcc @done
    sec
    sbc #ROOM_COUNT
@done:
    rts
