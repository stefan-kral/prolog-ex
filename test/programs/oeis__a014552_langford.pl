% Langford-Folgen (OEIS A014552) mit clpz: 1,1,2,2,..,N,N so angeordnet,
% dass zwischen den beiden K genau K andere stehen. Ps sind die ersten
% Stellen; die zweiten liegen K+1 dahinter. Die OEIS zaehlt eine Folge
% und ihre Umkehrung einmal: die Umkehrung bringt die erste 1 von P nach
% 2N-1-P, genau eine der beiden Stellen ist =< N-1.
:- use_module(library(clpz)).
:- use_module(library(lists)).

langford(N, Ps) :-
    length(Ps, N),
    M is 2 * N,
    Ps ins 1..M,
    seconds(Ps, 1, Ss),
    Ss ins 1..M,
    append(Ps, Ss, All),
    all_different(All),
    Ps = [P1|_],
    P1 #=< N - 1,
    label(Ps).

seconds([], _, []).
seconds([P|Ps], K, [S|Ss]) :- S #= P + K + 1, K1 is K + 1, seconds(Ps, K1, Ss).
