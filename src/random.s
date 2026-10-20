; The random numbers (spec, "Random numbers"): a 16-bit shift register in random_low/random_high. The new
; bit is bit 6 of (high XOR low); low shifts left taking it in, and high shifts left taking low's old bit 7.

; Out: A = the new random_low.
next_random:
    lda random_high
    eor random_low
    asl                   ; bit 7 out...
    asl                   ; ...then bit 6 into the carry
    rol random_low
    rol random_high
    lda random_low
    rts
