; The sound (docs/plan.md, step 5): the remaster's NES-look soundtrack and effects on the NES's sound chip.
; tools/make_music.py makes the data (build/sound/sound.inc).
;
; Four voices: pulse 1 (the melody), pulse 2 (the harmony), the triangle (the bass), the noise (the drums).
; Each frame each voice's song stream moves on; an effect playing on a voice takes it over until it's done,
; while the song carries on underneath, unheard. Which song plays follows the moment (the remaster's
; music/player.py); which effects play follows what just happened (its music/events.py).

VOICES = 4
PULSE_1 = 0
PULSE_2 = 1
TRIANGLE = 2
NOISE = 3
APU_PULSE_1 = $4000
APU_SWEEP_1 = $4001
APU_TRIANGLE = $4008
APU_TRIANGLE_LOW = $400A
APU_TRIANGLE_HIGH = $400B
APU_NOISE = $400C
APU_NOISE_PERIOD = $400E
APU_NOISE_LENGTH = $400F
APU_CHANNELS = $4015
CONSTANT_VOLUME = $30     ; no length counter, no hardware envelope: the volume as written
SWEEP_OFF = $08
TRIANGLE_ON = $FF
TRIANGLE_OFF = $80
NO_SONG = $FF
NO_EFFECT = $FF
STREAM_TIE = $70
STREAM_ARPEGGIO = $E0
STREAM_INSTRUMENT = $F0
STREAM_END = $FF
VOLUMES_END = $FF
CALM_FRAMES = 120         ; the tension music keeps on this long after the last monster has gone
STEP_EVERY = 14           ; frames of walking between footsteps
THUNDER_GAP = 90          ; one roll of thunder per strike, though lightning flickers
TITLE_THUNDER_DELAY = 60  ; frames from the title's lightning to its thunder: the storm is some way off

; --- the voices --------------------------------------------------------------------------------------
set_up_sound:
    lda #$0F
    sta APU_CHANNELS
    lda #SWEEP_OFF
    sta APU_SWEEP_1
    sta APU_SWEEP_1 + 4
    lda #$F8
    sta APU_NOISE_LENGTH
    sta APU_TRIANGLE_HIGH
    lda #NO_SONG
    sta song_playing
    sta song_paused
    lda #$FF
    ldx #(VOICES - 1)
@voice:
    sta last_high, x
    lda #0
    sta voice_playing, x
    sta effect_left, x
    lda #$FF
    dex
    bpl @voice
    rts

; Each frame, after the game's and the picture's work.
audio_frame:
    jsr choose_song
    jsr hear_events
    jsr hear_title_storm
    ldx #0
@voice:
    jsr use_song_bank     ; the song's streams may be in the second music bank...
    jsr song_step
    jsr use_music_bank    ; ...the effects are in the first
    lda effect_left, x
    beq @write
    jsr effect_step
@write:
    jsr write_voice
    inx
    cpx #VOICES
    bne @voice
    rts

; The program bank at $A000: the playing song's (song_banks), or the first music bank. Both banks start with
; the same tables (tools/make_music.py), so either reads them. The bank register is written as use_extras
; writes it (screens.s), so an NMI between the two writes does no harm. Keeps X.
use_song_bank:
    ldy song_playing
    cpy #NO_SONG
    beq use_music_bank
    lda song_banks, y
    jmp set_music_bank
use_music_bank:
    lda #MUSIC_BANK
set_music_bank:
    pha
    lda #PROGRAM_BANK_A000
    sta bank_select
    sta BANK_SELECT
    pla
    sta BANK_DATA
    rts

; --- the songs -----------------------------------------------------------------------------------------
; In: A = a song (or NO_SONG). Starts it from the top (a floor's song paused for a while carries on).
start_song:
    cmp song_playing
    beq @done
    pha
    lda song_playing      ; a floor's song interrupted (by danger): keep its place
    jsr is_floor_song
    bcc @not_kept
    lda song_playing
    sta song_paused
    jsr keep_places
@not_kept:
    pla
    sta song_playing
    cmp #NO_SONG
    beq @silence
    cmp song_paused
    bne @from_the_top
    jsr restore_places
    lda #NO_SONG
    sta song_paused
    rts
@from_the_top:
    asl                   ; the song's four streams: song_voices + song * 8
    asl
    asl
    tay
    ldx #0
@voice:
    lda song_voices, y
    sta voice_start_low, x
    sta voice_pointer_low, x
    lda song_voices + 1, y
    sta voice_start_high, x
    sta voice_pointer_high, x
    lda #0
    sta voice_wait, x
    sta voice_note, x
    sta voice_arpeggio_1, x
    sta voice_arpeggio_2, x
    lda #1
    sta voice_playing, x
    iny
    iny
    inx
    cpx #VOICES
    bne @voice
@done:
    rts
@silence:
    ldx #(VOICES - 1)
    lda #0
@quiet:
    sta voice_playing, x
    dex
    bpl @quiet
    rts

; In: A = a song. Out: carry set if it's one of the floors' songs.
is_floor_song:
    cmp #NO_SONG
    beq @no
    ldy #(FLOOR_COUNT - 1)
@floor:
    cmp floor_songs, y
    beq @yes
    dey
    bpl @floor
@no:
    clc
    rts
@yes:
    sec
    rts

; Every voice's place in the song, kept while another plays, and back again.
keep_places:
    ldx #(VOICES - 1)
@voice:
    lda voice_pointer_low, x
    sta kept_pointer_low, x
    lda voice_pointer_high, x
    sta kept_pointer_high, x
    lda voice_start_low, x
    sta kept_start_low, x
    lda voice_start_high, x
    sta kept_start_high, x
    lda voice_wait, x
    sta kept_wait, x
    lda voice_instrument, x
    sta kept_instrument, x
    dex
    bpl @voice
    rts

restore_places:
    ldx #(VOICES - 1)
@voice:
    lda kept_pointer_low, x
    sta voice_pointer_low, x
    lda kept_pointer_high, x
    sta voice_pointer_high, x
    lda kept_start_low, x
    sta voice_start_low, x
    lda kept_start_high, x
    sta voice_start_high, x
    lda kept_wait, x
    sta voice_wait, x
    lda kept_instrument, x
    sta voice_instrument, x
    lda #0
    sta voice_note, x     ; the note it was in is not picked up again: silent until the next
    lda #1
    sta voice_playing, x
    dex
    bpl @voice
    rts

; In: X = a voice. Its stream moves on a frame; out: voice_volume, voice_period (and duty) for this frame.
song_step:
    lda #0
    sta voice_volume, x
    lda voice_playing, x
    beq @done
    lda voice_wait, x
    bne @sounding
    jsr next_note
    lda voice_playing, x
    beq @done
@sounding:
    dec voice_wait, x
    lda voice_note, x
    beq @done             ; a rest
    jsr note_volume
    jsr note_period
@done:
    rts

stream_pointer = work_0   ; (2 bytes)
; In: X = a voice. Reads its stream to its next note (or rest): instruments, arpeggios, the end.
next_note:
    lda voice_pointer_low, x
    sta stream_pointer
    lda voice_pointer_high, x
    sta stream_pointer + 1
    ldy #0
@read:
    lda (stream_pointer), y
    cmp #STREAM_END
    beq @end
    cmp #STREAM_INSTRUMENT
    bcc @not_instrument
    and #$0F
    sta voice_instrument, x
    iny
    jmp @read
@not_instrument:
    cmp #STREAM_ARPEGGIO
    bne @note
    iny
    lda (stream_pointer), y
    sta voice_arpeggio_1, x
    iny
    lda (stream_pointer), y
    sta voice_arpeggio_2, x
    iny
    jmp @read
@note:
    cmp #STREAM_TIE
    beq @tied             ; carry on the note before
    sta voice_note, x
    lda #0
    sta voice_envelope, x
@tied:
    iny
    lda (stream_pointer), y
    sta voice_wait, x
    iny
    tya                   ; move the pointer on past what was read
    clc
    adc stream_pointer
    sta voice_pointer_low, x
    lda stream_pointer + 1
    adc #0
    sta voice_pointer_high, x
    rts
@end:
    lda song_playing
    tay
    lda song_loops, y
    beq @stop
    lda voice_start_low, x   ; a song that loops: from the top
    sta voice_pointer_low, x
    lda voice_start_high, x
    sta voice_pointer_high, x
    jmp next_note
@stop:
    lda #0
    sta voice_playing, x
    rts

; In: X = a voice. Its instrument's volume this frame (held at the last), and its duty.
volumes_pointer = work_2  ; (2 bytes)
note_volume:
    lda voice_instrument, x
    tay
    lda instrument_duty, y
    sta voice_duty, x
    tya
    asl
    tay
    lda instrument_volumes, y
    sta volumes_pointer
    lda instrument_volumes + 1, y
    sta volumes_pointer + 1
    ldy voice_envelope, x
    lda (volumes_pointer), y
    sta voice_volume, x
    iny
    lda (volumes_pointer), y
    cmp #VOLUMES_END
    beq @held
    inc voice_envelope, x
@held:
    rts

; In: X = a voice. Its period this frame: the note (through the arpeggio, a step a frame), from the pulse
; or the triangle table; the noise's note is its period.
note_period:
    lda voice_note, x
    ldy voice_arpeggio_1, x
    beq @plain
    ldy voice_arpeggio_step, x
    beq @step_counted
    cpy #1
    bne @third
    clc
    adc voice_arpeggio_1, x
    jmp @step_counted
@third:
    clc
    adc voice_arpeggio_2, x
@step_counted:
    pha
    inc voice_arpeggio_step, x
    lda voice_arpeggio_step, x
    cmp #3
    bcc @stepped
    lda #0
    sta voice_arpeggio_step, x
@stepped:
    pla
@plain:
    tay
    cpx #NOISE
    beq @noise
    cpx #TRIANGLE
    beq @triangle
    lda pulse_low, y
    sta voice_period_low, x
    lda pulse_high, y
    sta voice_period_high, x
    rts
@triangle:
    lda triangle_low, y
    sta voice_period_low, x
    lda triangle_high, y
    sta voice_period_high, x
    rts
@noise:
    tya
    sta voice_period_low, x
    rts

; --- the effects ---------------------------------------------------------------------------------------
; In: A = an effect. Each voice it uses plays its frames from now (the footsteps never cut in).
effect_pointer = work_4   ; (2 bytes)
start_effect_sound:
    sta effect_playing
    asl
    tay
    lda effects, y
    sta effect_pointer
    lda effects + 1, y
    sta effect_pointer + 1
    ldy #0
@part:
    lda (effect_pointer), y
    cmp #STREAM_END
    beq @done
    tax                   ; the voice
    iny
    lda (effect_pointer), y
    sta work_6            ; its frames
    iny
    lda effect_playing
    cmp #QUIET_EFFECT
    bne @take_voice
    lda effect_left, x
    bne @skip             ; a quiet effect waits for no one, and cuts no one off
@take_voice:
    lda work_6
    sta effect_left, x
    tya
    clc
    adc effect_pointer
    sta effect_pointer_low, x
    lda effect_pointer + 1
    adc #0
    sta effect_pointer_high, x
@skip:
    lda work_6            ; past this part's frames: 3 bytes each
    asl
    clc
    adc work_6
    sta work_7
    tya
    clc
    adc work_7
    tay
    bcc @part
    inc effect_pointer + 1   ; (a part longer than the rest of the page)
    jmp @part
@done:
    rts

; In: X = a voice with an effect. Its frame: volume and duty, period.
effect_step:
    lda effect_pointer_low, x
    sta effect_pointer
    lda effect_pointer_high, x
    sta effect_pointer + 1
    ldy #0
    lda (effect_pointer), y
    pha
    and #$0F
    sta voice_volume, x
    pla
    and #$C0
    sta voice_duty, x
    iny
    lda (effect_pointer), y
    sta voice_period_low, x
    iny
    lda (effect_pointer), y
    sta voice_period_high, x
    lda effect_pointer_low, x
    clc
    adc #3
    sta effect_pointer_low, x
    bcc @moved
    inc effect_pointer_high, x
@moved:
    dec effect_left, x
    rts

; --- the chip ------------------------------------------------------------------------------------------
; In: X = a voice. Its registers for this frame.
write_voice:
    cpx #TRIANGLE
    beq @triangle
    cpx #NOISE
    beq @noise
    txa                   ; a pulse: registers at $4000 + voice * 4
    asl
    asl
    tay
    lda voice_duty, x
    ora #CONSTANT_VOLUME
    ora voice_volume, x
    sta APU_PULSE_1, y
    lda voice_period_low, x
    sta APU_PULSE_1 + 2, y
    lda voice_period_high, x
    cmp last_high, x      ; written only when it changes: writing it restarts the wave, a click
    beq @done
    sta last_high, x
    sta APU_PULSE_1 + 3, y
@done:
    rts
@triangle:
    lda voice_volume, x
    beq @triangle_off
    lda #TRIANGLE_ON
    sta APU_TRIANGLE
    lda voice_period_low, x
    sta APU_TRIANGLE_LOW
    lda voice_period_high, x
    cmp last_high, x
    beq @done
    sta last_high, x
    sta APU_TRIANGLE_HIGH
    rts
@triangle_off:
    lda #TRIANGLE_OFF
    sta APU_TRIANGLE
    rts
@noise:
    lda voice_volume, x
    ora #CONSTANT_VOLUME
    sta APU_NOISE
    lda voice_period_low, x
    sta APU_NOISE_PERIOD
    rts

; --- which song ----------------------------------------------------------------------------------------
; The moment's song (the remaster's music.player.moment): the win, the title or game over, dying, danger
; (on for a while after the last monster leaves), or the floor's own (none in the ambient ROM).
choose_song:
    lda screen_wanted
    cmp #SCREEN_STORY
    bne @not_story
    lda #SONG_STORY
    jmp start_song
@not_story:
    cmp #SCREEN_ENDING
    bne @not_ending
    lda #SONG_WIN
    jmp start_song
@not_ending:
    lda monsters_here
    beq @calm
    lda #CALM_FRAMES
    sta calm_left
    jmp @chosen_calm
@calm:
    lda calm_left
    beq @chosen_calm
    dec calm_left
@chosen_calm:
    lda game_state
    cmp #GAME_WON
    bne @not_won
    lda #SONG_WIN
    jmp start_song
@not_won:
    cmp #GAME_SELECTING
    bne @not_selecting
    lda lives
    bne @title
    lda #SONG_GAME_OVER
    jmp start_song
@title:
    lda #SONG_TITLE
    jmp start_song
@not_selecting:
    cmp #GAME_DYING
    bne @not_dying
    lda #SONG_DYING
    jmp start_song
@not_dying:
    lda calm_left
    beq @floor
    lda #SONG_TENSION
    jmp start_song
@floor:
.ifdef AMBIENT
    lda #NO_SONG          ; the ambient ROM: no floor has a song, as the Attic has none
.else
    ldx floor
    lda floor_songs, x
.endif
    jmp start_song

; --- the title's storm ---------------------------------------------------------------------------------
; On the screens under the stormy sky (the title, game over, the help: screens.s title_lightning), thunder
; rolls a moment after each flash.
hear_title_storm:
    lda screen_shown
    cmp #SCREEN_TITLE
    beq @under_the_sky
    cmp #SCREEN_GAME_OVER
    beq @under_the_sky
    cmp #SCREEN_HELP
    bne @done
@under_the_sky:
    jsr title_storm_frame
    cmp #TITLE_THUNDER_DELAY
    bne @done
    lda #EFFECT_THUNDER
    jmp start_effect_sound
@done:
    rts

; --- what just happened --------------------------------------------------------------------------------
; Effects for what's changed since last frame (the remaster's music/events.py).
hear_events:
    lda game_state
    cmp #GAME_SELECTING
    beq @remember
    lda was_state
    cmp #GAME_SELECTING
    beq @remember
    jsr hear_match
    jsr hear_moving
    jsr hear_carrying
    jsr hear_urn
    jsr hear_danger
    jsr hear_game_sounds
@remember:
    lda matches_used
    sta was_matches
    lda flags
    sta was_flags
    lda floor
    sta was_floor
    lda room
    sta was_room
    lda room_beyond
    sta was_room_beyond
    lda player_x
    sta was_x
    lda player_y
    sta was_y
    lda game_state
    sta was_state
    lda carried
    sta was_carried
    jsr biggest_group
    sta was_group
    lda monsters_here
    sta was_monsters_here
    lda lightning_flash
    sta was_lightning
    lda sound
    sta was_sound
    inc since_thunder
    bne @counted
    dec since_thunder     ; (held at 255)
@counted:
    rts

hear_match:
    lda matches_used
    cmp was_matches
    beq @not_lit
    lda #EFFECT_MATCH_STRIKE
    jmp start_effect_sound
@not_lit:
    lda was_flags
    and #MATCH_LIT
    beq @done
    lda flags
    and #MATCH_LIT
    bne @done
    lda #EFFECT_MATCH_OUT
    jmp start_effect_sound
@done:
    rts

hear_moving:
    lda floor
    cmp was_floor
    beq @same_floor
    lda #0
    sta walking
    lda #EFFECT_STAIRS_UP
    bcs @up               ; (the compare above: carry set if the floor went up)
    lda #EFFECT_STAIRS_DOWN
@up:
    jmp start_effect_sound
@same_floor:
    lda room_beyond
    cmp #NOTHING
    beq @not_into_doorway
    lda was_room_beyond
    cmp #NOTHING
    bne @not_into_doorway
    lda #EFFECT_DOOR_OPEN
    jsr start_effect_sound
@not_into_doorway:
    lda room
    cmp was_room
    beq @steps
    lda #EFFECT_DOOR_CLOSE
    jsr start_effect_sound
@steps:
    lda game_state
    bne @standing
    lda player_x
    cmp was_x
    bne @walking
    lda player_y
    cmp was_y
    beq @standing
@walking:
    inc walking
    lda walking
    cmp #1
    bne @counted
    lda #EFFECT_FOOTSTEP
    jsr start_effect_sound
@counted:
    lda walking
    cmp #STEP_EVERY
    bcc @done
    lda #0
    sta walking
    rts
@standing:
    lda #0
    sta walking
@done:
    rts

hear_carrying:
    lda carried
    cmp was_carried
    beq @done
    cmp #NOTHING
    beq @put_down
    lda was_carried
    cmp #NOTHING
    bne @done
    lda carried           ; picked up: the key, the scepter, or an urn piece
    cmp #URN
    bcc @item
    lda #EFFECT_PICKUP_URN
    jmp start_effect_sound
@item:
    clc
    adc #EFFECT_PICKUP_KEY
    jmp start_effect_sound
@put_down:
    lda game_state        ; not when it's taken from you
    ora was_state
    bne @done
    lda #EFFECT_DROP
    jmp start_effect_sound
@done:
    rts

hear_urn:
    jsr biggest_group
    cmp was_group
    beq @done
    bcc @done
    cmp #3
    beq @whole
    lda #EFFECT_URN_JOIN
    jmp start_effect_sound
@whole:
    lda #EFFECT_URN_WHOLE
    jmp start_effect_sound
@done:
    rts

; Out: A = how many pieces the biggest group of urn pieces has.
biggest_group:
    lda #0
    sta work_8
    ldx #2
@piece:
    lda urn_shapes, x
    jsr shape_pieces
    tay
    lda pieces_counted, y
    cmp work_8
    bcc @smaller
    sta work_8
@smaller:
    dex
    bpl @piece
    lda work_8
    rts

hear_danger:
    lda game_state
    cmp #GAME_DYING
    bne @not_caught
    lda was_state
    cmp #GAME_DYING
    beq @lightning
    lda #EFFECT_CAUGHT
    jsr start_effect_sound
    jmp @lightning
@not_caught:
    lda monsters_here
    beq @lightning
    lda was_monsters_here
    bne @lightning
    jsr monster_in_room
    clc
    adc #EFFECT_MONSTER_GHOST
    jsr start_effect_sound
@lightning:
    lda lightning_flash
    beq @done
    lda was_lightning
    bne @done
    lda since_thunder
    cmp #THUNDER_GAP
    bcc @done
    lda #0
    sta since_thunder
    lda #EFFECT_THUNDER
    jmp start_effect_sound
@done:
    rts

; Out: A = the kind of the first monster in the room: 0 the ghost, 1 the bat, 2 a tarantula.
monster_in_room:
    ldx #0
@monster:
    lda monster_floor, x
    cmp floor
    bne @next
    lda monster_room, x
    cmp room
    beq @found
    cmp room_beyond
    beq @found
@next:
    inx
    cpx last_monster
    beq @monster
    bcc @monster
    lda #2
    rts
@found:
    txa
    cmp #2
    bcc @kind
    lda #2
@kind:
    rts

; What only the game knows: a bump into a wall, a door that won't open.
hear_game_sounds:
    lda sound
    cmp was_sound
    beq @done
    cmp #SOUND_BUMP
    bne @not_bump
    lda #EFFECT_BUMP
    jmp start_effect_sound
@not_bump:
    cmp #SOUND_BLOCKED
    bne @done
    lda #EFFECT_LOCKED
    jmp start_effect_sound
@done:
    rts

.segment "RODATA"
; (floor_songs, each floor's: tools/make_art.py, in floors.inc)
.segment "CODE"
