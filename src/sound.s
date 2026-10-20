; The sound's state (spec, "Sound"; the remaster's game/sounds.py is the exact rule): which effect plays
; and for how long, the monster noise's wandering pitch, and the thunder while dying. The NES's own
; sounds will follow these bytes; here they're kept exactly as the 2600 keeps them.

; In: A = an effect. The same one isn't restarted, and a bump never cuts another short.
start_effect:
    cmp sound
    beq @done
    cmp #SOUND_BUMP
    bne @start
    ldx sound
    bne @done
@start:
    sta sound
    tax
    lda sound_lengths, x
    sta sound_time
@done:
    rts

sound_frame:
    jsr mood
    lda game_state        ; the effects run only in play
    bne @done
    lda sound_time
    bne @playing
    sta sound             ; over: footsteps from now on
    rts
@playing:
    dec sound_time
@done:
    rts

; Channel 0: a monster in the room makes a noise that wanders; dying, thunder.
mood:
    lda game_state
    beq @in_play
    and #GAME_DYING
    beq @done             ; won: the tune keeps nothing in RAM
    lda thunder
    bne @rumbling
    lda random_low        ; a new rumble of 16-44 frames
    and #$70
    lsr
    lsr
    clc
    adc #$10
    sta thunder
    rts
@rumbling:
    dec thunder
@done:
    rts
@in_play:
    lda monsters_here
    bne wander_mood
    lda mood_pitch
    cmp #MOOD_SILENT
    beq @done
    lda #0                ; nobody here: drift back up to silence
    sta mood_direction
    ; falls through

; The pitch walks a step a frame; at every multiple of 16 it may turn, at random.
wander_mood:
    lda mood_pitch
    cmp #MOOD_SILENT
    beq @set_direction
    and #$0F
    bne @step
    lda mood_pitch
    beq @set_direction
    bmi @set_direction
    jsr random_bit        ; a multiple of 16, between: turn at random
    sta mood_direction
    jmp @step
@set_direction:
    lda mood_pitch
    sta mood_direction
@step:
    lda mood_direction
    beq @rise
    dec mood_pitch
    rts
@rise:
    inc mood_pitch
    rts

; Out: A = a random bit, 0 or 1: bit 0 of the 2600's byte at $F000 + random_low.
random_bit:
    lda random_low
    and #7
    tax
    lda random_low
    lsr
    lsr
    lsr
    tay
    lda random_bits, y
    and bits, x
    beq @zero
    lda #1
@zero:
    rts
