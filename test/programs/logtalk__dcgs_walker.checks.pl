% dcgs_12 (Gleitkommazahlen mit Toleranz)
expect((walk([n(5), e(4), s(2), nw(8), s(5), se(1), n(4)], (A, B)),
        abs(A - -0.94974746830583223) < 1.0e-9, abs(B - 6.9497474683058318) < 1.0e-9),
       ok, [ok]).
