; The remaster's lights-on cheat (its O key), on B and Select together during play: the lights come on, and
; everything on the floor shows where the game has it - walls, items, monsters and stairs, lit or not (the
; remaster's game/visibility.py). The game itself is unchanged: picking things up still needs a match.
;
; While B is held, Select is the cheat's and the game never hears it. B on its own asks for a hint, when
; it's let go (so B and Select together don't give one).

; After screen_buttons has read the buttons, during play.
play_buttons:
    lda #0
    sta hint_asked
    lda screen_shown
    bne @done
    lda pad
    and #PAD_B
    beq @b_up
    lda #1
    sta b_held
    lda #0                ; B held: Select is the cheat's
    sta select_down
    lda pad_pressed
    and #PAD_SELECT
    beq @done
    lda lights_on
    eor #1
    sta lights_on
    lda #1
    sta cheat_used
    sta lights_note_due
@done:
    rts
@b_up:
    lda b_held
    beq @done
    lda #0
    sta b_held
    lda cheat_used
    bne @no_hint
    lda #1
    sta hint_asked
@no_hint:
    lda #0
    sta cheat_used
    rts

; The note that says so, when the cheat has just been turned on or off.
cheat_note:
    lda lights_note_due
    beq @done
    lda #0
    sta lights_note_due
    jsr start_spec
    lda lights_on
    beq @off
    part lights_on_words
    jsr next_line
    part picking_up_words
    jsr next_line
    part turn_off_words
    jmp show_spec
@off:
    jsr next_line
    part lights_off_words
    jmp show_spec
@done:
    rts

.segment "EXTRAS"
lights_on_words:  .byte "LIGHTS ON - A CHEAT.", STRING_END
picking_up_words: .byte "PICKING UP NEEDS A MATCH LIT.", STRING_END
turn_off_words:   .byte "B AND SELECT TURN THEM OFF.", STRING_END
lights_off_words: .byte "LIGHTS OFF.", STRING_END
.segment "CODE"
