DEPTH 4096
START:  mv    sp, =0x0100   // sp = 0x1000 = 4096
        mv    r4, =0x0F0F
        push  r4
        bl    SUBR
        pop   r4
END:    b     END

SUBR:   sub   r4, r4
        mv    pc, lr
