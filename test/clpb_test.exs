defmodule PrologEx.ClpbTest do
  # library(clpb) (Markus Triska, aus Scryer Prolog): Beispiele aus der
  # Dokumentation, Beispielprogramme aus github.com/triska/clpb und dessen
  # Prüfprogramme (clpb:validation: interne Konsistenzprüfungen)
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @program """
  :- use_module(library(clpb)).
  :- use_module(library(lists)).
  :- use_module(library(dcgs)).
  :- use_module(library(between)).
  :- use_module(library(random)).
  :- use_module(library(swi), [(=@=)/2]).

  % Tauben (aus der Dokumentation)
  pigeon(I, J, Rows, Cs) :-
          length(Rows, I), length(Row, J),
          maplist(same_length(Row), Rows),
          transpose(Rows, TRows),
          phrase((all_cards(Rows,[1]),all_cards(TRows,[0,1])), Cs).

  all_cards([], _) --> [].
  all_cards([Ls|Lss], Cs) --> [card(Cs,Ls)], all_cards(Lss, Cs).

  transpose([], []).
  transpose([F|Fs], Ts) :- transpose_(F, [F|Fs], Ts).
  transpose_([], _, []).
  transpose_([_|Rs], Ms, [Ts|Tss]) :-
          lists_firsts_rests(Ms, Ts, Ms1),
          transpose_(Rs, Ms1, Tss).
  lists_firsts_rests([], [], []).
  lists_firsts_rests([[F|Os]|Rest], [F|Fs], [Os|Oss]) :-
          lists_firsts_rests(Rest, Fs, Oss).

  % XOR aus vier NAND-Gattern (aus der Dokumentation)
  nand_gate(X, Y, Z) :- sat(Z =:= ~(X*Y)).
  xor(X, Y, Z) :-
          nand_gate(X, Y, T1),
          nand_gate(X, T1, T2),
          nand_gate(Y, T1, T3),
          nand_gate(T2, T3, Z).

  % Vergleich der Propagation: '$clpb_propagate'/2 (Elixir) gegen
  % Triskas Prolog-Code, auf demselben BDD vor jeder Unifikation
  ref_propagate(BDD, P) :-
          (   clpb:bdd_nodes(clpb:var_unbound, BDD, Nodes) ->
              clpb:bdd_variables_classification(BDD, Nodes, Classes),
              clpb:partition(clpb:var_class, Classes, Eqs, Bs, Ds),
              clpb:domain_consistency(Eqs, Vs=Values),
              clpb:aliasing_consistency(Bs, Ds, Goals),
              P = prop(Vs, Values, Goals)
          ;   P = skip
          ).

  % zufällige Formel der Tiefe D über Vs
  rf(0, Vs, V) :- !, random_member(V, Vs).
  rf(D, Vs, F) :-
          random_integer(0, 9, K), D1 is D - 1,
          (   K =:= 0 -> rf(0, Vs, F)
          ;   K =:= 1 -> rf(D1, Vs, A), F = ~(A)
          ;   K =:= 2 -> rf(D1, Vs, A), rf(D1, Vs, B), F = A+B
          ;   K =:= 3 -> rf(D1, Vs, A), rf(D1, Vs, B), F = A*B
          ;   K =:= 4 -> rf(D1, Vs, A), rf(D1, Vs, B), F = #(A, B)
          ;   K =:= 5 -> rf(D1, Vs, A), rf(D1, Vs, B), F = (A=:=B)
          ;   K =:= 6 -> rf(D1, Vs, A), rf(D1, Vs, B), F = (A=<B)
          ;   K =:= 7 -> F = card([1], Vs)
          ;   rf(D1, Vs, A), rf(D1, Vs, B), F = (A*B =:= ~(B))
          ).

  % ein Fall: gleiches Ergebnis? Art des Ergebnisses für die Statistik
  compare_propagation(Seed, Kind) :-
          set_random(seed(Seed)),
          length(Vs, 6),
          rf(4, Vs, F),
          clpb:parse_sat(F, Sat),
          clpb:sat_bdd(Sat, BDD),
          clpb:'$clpb_propagate'(BDD, P1),
          ref_propagate(BDD, P2),
          (   P1 == P2 -> true ; throw(verschieden(F, P1, P2)) ),
          (   BDD == 0 -> Kind = falsch
          ;   BDD == 1 -> Kind = wahr
          ;   P1 = prop(_, [], []) -> Kind = nichts
          ;   P1 = prop(_, _, []) -> Kind = fest
          ;   Kind = gleich
          ).

  % mit Atomen (allquantifizierten Variablen): Elixir prüft wie
  % bdd_variables_classification/3, ob der BDD nach Herausrechnen der
  % anderen Variablen 1 ist; scheitern beide, ist das gleich
  compare_propagation_atoms(Seed, Kind) :-
          set_random(seed(Seed)),
          length(Vs0, 4), append(Vs0, [a,b], Vs),
          rf(3, Vs, F),
          catch(clpb:parse_sat(F, Sat), _, fail),
          clpb:sat_bdd(Sat, BDD),
          (   clpb:'$clpb_propagate'(BDD, P1) -> true ; P1 = scheitert ),
          (   ref_propagate(BDD, P2) -> true ; P2 = scheitert ),
          (   P1 == P2 -> true ; throw(verschieden(F, P1, P2)) ),
          (   P1 == scheitert -> Kind = scheitert ; Kind = prop ).

  % existential/3 (Elixir) gegen existential_ref/3 (Triska)
  compare_existential(Seed, Size) :-
          set_random(seed(Seed)),
          length(Vs, 6),
          rf2(5, Vs, F),
          clpb:parse_sat(F, Sat),
          clpb:sat_bdd(Sat, B),
          random_member(V, Vs),
          clpb:existential(V, B, N1),
          clpb:existential_ref(V, B, N2),
          canon(N1, C1), canon(N2, C2),
          (   C1 == C2, N1 == N2 -> true ; throw(verschieden(F, V, C1, C2)) ),
          clpb:bdd_nodes(N1, Ns), length(Ns, Size).

  % parse_sat/2 (Elixir) gegen parse_sat_ref/2 (Triska): Ergebnis samt
  % Indizes der Variablen, oder derselbe Fehler; je in findall/3, damit
  % beide vom selben Zustand ausgehen
  rp(0, Vs, F) :- !,
          random_integer(0, 14, K),
          (   K < 5 -> random_member(F, Vs)
          ;   K < 12 -> random_member(F, [a, b, 0, 1, v(_), v(1), [], v(0)])
          ;   random_member(F, [2, v(a), 1.0, f(x), -1, v(2), "s"])
          ).
  rp(D, Vs, F) :-
          random_integer(0, 30, K), D1 is D - 1,
          (   K < 3 -> rp(0, Vs, F)
          ;   K < 5 -> rp(D1, Vs, A), F = ~(A)
          ;   K < 15 ->
              rp(D1, Vs, A), rp(D1, Vs, B),
              random_member(Op, [*, +, #, =:=, =\=, =<, >=, <, >]),
              F =.. [Op, A, B]
          ;   K < 18 ->
              rp(D1, Vs, A), rp(D1, Vs, B), random_member(Op, [+, *]),
              random_member(L, [[A,B], [A], [], [A|_], [A|x]]),
              F =.. [Op, L]
          ;   K < 20 -> random_member(X, Vs), rp(D1, Vs, A), F = (X^A)
          ;   K < 21 -> rp(D1, Vs, A), F = (a^A)
          ;   K < 24 ->
              rp(D1, Vs, A), rp(D1, Vs, B),
              random_member(Is, [[1], [0,2], [_], [1|_], x, [f(_)]]),
              random_member(Fs, [[A,B], [A], [A|_], y]),
              F = card(Is, Fs)
          ;   rp(D1, Vs, F)
          ).

  parse_result(P, F, R) :-
          findall(R0,
                  catch(( call(P, F, S),
                          term_variables(S, Vs),
                          maplist(clpb:var_index, Vs, Is),
                          R0 = ok(F, S, Is)
                        ), E, R0 = fehler(F, E)),
                  [R]).

  compare_parse(Seed, Kind) :-
          set_random(seed(Seed)),
          length(Vs, 3),
          rp(4, Vs, F),
          parse_result(clpb:parse_sat, F, R1),
          parse_result(clpb:parse_sat_ref, F, R2),
          (   R1 =@= R2 -> true ; throw(verschieden(R1, R2)) ),
          functor(R1, Kind, _).

  % sat_bdd/2 (Elixir) gegen sat_bdd_ref/2 (Triska): derselbe BDD samt
  % Knoten-IDs und Zählerständen, oder derselbe Fehler
  rs(0, Vs, F) :- !, random_member(F, [0, 1, a, b|Vs]).
  rs(D, Vs, F) :-
          random_integer(0, 12, K), D1 is D - 1,
          (   K < 2 -> rs(0, Vs, F)
          ;   K < 3 -> rs(D1, Vs, A), F = ~(A)
          ;   K < 7 ->
              rs(D1, Vs, A), rs(D1, Vs, B),
              random_member(Op, [*, +, #, =:=, =<, <]),
              F =.. [Op, A, B]
          ;   K < 9 -> random_member(X, Vs), rs(D1, Vs, A), F = (X^A)
          ;   rs(D1, Vs, A), random_member(B, Vs), random_member(C, Vs),
              random_member(Is, [[1], [0,2], [1-2], [0-inf], [2,0-1], [3]]),
              random_member(Fs, [[A,B,C], [B,C], [B,B,C], [A], [C,B,A,B]]),
              F = card(Is, Fs)
          ).

  bdd_result(P, F, R) :-
          findall(R0,
                  catch(( clpb:parse_sat(F, Sat),
                          call(P, Sat, B),
                          canon(B, C),
                          b_getval_(N1, N2),
                          R0 = ok(F, B, C, N1, N2)
                        ), E, R0 = fehler(F, E)),
                  [R]).

  b_getval_(N1, N2) :-
          clpb:b_getval('$clpb_next_var', N1),
          clpb:b_getval('$clpb_next_node', N2).

  compare_sat_bdd(Seed, Kind) :-
          set_random(seed(Seed)),
          length(Vs, 4),
          rs(4, Vs, F),
          bdd_result(clpb:sat_bdd, F, R1),
          bdd_result(clpb:sat_bdd_ref, F, R2),
          (   R1 =@= R2 -> true ; throw(verschieden(R1, R2)) ),
          (   R1 = ok(_, B, _, _, _), integer(B) -> Kind = blatt
          ;   functor(R1, Kind, _)
          ).

  % sat/1 (Elixir) gegen sat_ref/1 (Triska): mehrere Bedingungen
  % nacheinander, dann Bindungen, Restziele und Zählerstände
  sat_result(P, Vs, Fs, R) :-
          findall(R0,
                  catch(( maplist(P, Fs) ->
                          copy_term(Vs, Ws, Gs),
                          b_getval_(N1, N2),
                          R0 = ok(Vs, Ws, Gs, N1, N2)
                        ; R0 = scheitert
                        ), E, R0 = fehler(E)),
                  [R]).

  compare_sat(Seed, Kind) :-
          set_random(seed(Seed)),
          length(Vs, 5),
          random_integer(1, 4, K),
          length(Fs, K),
          maplist(rs(3, Vs), Fs),
          sat_result(clpb:sat, Vs, Fs, R1),
          sat_result(clpb:sat_ref, Vs, Fs, R2),
          (   R1 =@= R2 -> true ; throw(verschieden(Fs, R1, R2)) ),
          functor(R1, Kind, _).

  % ganze Abläufe: sat/1, taut/2 und Bindungen (Hook beim Binden), einmal
  % mit Elixir, einmal mit ref_mode (Triskas Code)
  random_op(Vs, Op) :-
          random_integer(0, 11, K),
          random_member(X, Vs), random_member(Y, Vs),
          (   K < 4 -> rs(3, Vs, F), Op = sat(F)
          ;   K < 6 -> rs(2, Vs, F), Op = taut(F, _)
          ;   K < 7, random_integer(0, 2, 0) ->
              rs(3, Vs, F), Op = sat_count(F, _)
          ;   K < 7 -> random_member(B, [0, 1]), Op = (X = B)
          ;   K < 8 -> Op = (X = Y)
          ;   K < 9 ->
              random_member(A, [a, b]), Op = (X = A)
          ;   K < 10, random_integer(0, 2, 0) ->
              % zwei Bindungen in einer Unifikation
              random_member(Z, Vs), random_member(W, Vs),
              Op = (f(X, Y) = f(Z, W))
          ;   % über neue Variablen (sonst entstehen über Ketten wie
              % B = ~D, D = B^a zyklische Terme)
              rs(1, [_, _], F), Op = (X = F)
          ).

  run_ops([]).
  run_ops([Op|Ops]) :- call(Op), run_ops(Ops).

  ops_result(Vs, Ops, R) :-
          findall(R0,
                  catch(( run_ops(Ops) ->
                          copy_term(Vs-Ops, Ws, Gs),
                          b_getval_(N1, N2),
                          R0 = ok(Vs-Ops, Ws, Gs, N1, N2)
                        ; R0 = scheitert
                        ), E, R0 = fehler(E)),
                  [R]).

  compare_ops(Seed, Kind) :-
          set_random(seed(Seed)),
          length(Vs, 4),
          random_integer(1, 6, K),
          length(Ops, K),
          maplist(random_op(Vs), Ops),
          ops_result(Vs, Ops, R1),
          assertz(clpb:ref_mode),
          ops_result(Vs, Ops, R2),
          retractall(clpb:ref_mode),
          (   R1 =@= R2 -> true ; throw(verschieden(Ops, R1, R2)) ),
          functor(R1, Kind, _).

  % ein Ziel einmal mit Elixir, einmal mit ref_mode
  goal_result(G, R) :-
          term_variables(G, Vs),
          findall(R0,
                  catch(( call(G) -> copy_term(Vs, Ws, Gs), R0 = ok(Vs, Ws, Gs)
                        ; R0 = scheitert
                        ), E, R0 = fehler(E)),
                  [R]).

  compare_goal(G, R1) :-
          goal_result(G, R1),
          assertz(clpb:ref_mode),
          goal_result(G, R2),
          retractall(clpb:ref_mode),
          (   R1 =@= R2 -> true ; throw(verschieden(G, R1, R2)) ).

  % sat_count/2 nach einigen Bedingungen, mit Elixir und mit ref_mode
  compare_count(Seed, N) :-
          set_random(seed(Seed)),
          length(Vs, 5),
          random_integer(0, 3, K),
          length(Fs, K),
          maplist(rs(3, Vs), Fs),
          random_integer(0, 3, J),
          (   J =:= 0 -> rs(3, Vs, C)
          ;   J =:= 1 -> C = +[1|Vs]
          ;   Vs = [A, B|_], C = +[1, A, B]
          ),
          G = (maplist(sat, Fs), sat_count(C, N)),
          goal_result(G, R1),
          assertz(clpb:ref_mode),
          goal_result(G, R2),
          retractall(clpb:ref_mode),
          (   R1 =@= R2 -> true ; throw(verschieden(G, R1, R2)) ),
          findall(N, catch(G, _, fail), Ns),
          (   Ns = [N0] -> N = N0 ; N = keine ).

  % sat_ands//1 mit offenen Listen: dieselben Bindungen wie das Original
  compare_sat_ands(G, P) :-
          copy_term(G, G1), copy_term(G, G2),
          G1 = [V1, F1], G2 = [V2, F2],
          sat_result(clpb:sat, V1, [F1], R1),
          sat_result(clpb:sat_ref, V2, [F2], R2),
          (   R1 =@= R2 -> P = R1 ; throw(verschieden(G, R1, R2)) ).

  % Vergleich des BDD-Kerns: apply/4 (Elixir) gegen apply_ref/4 (Triska)
  ref_bdd(V, N) :- var(V), !, clpb:make_node_ref(V, 0, 1, N).
  ref_bdd(I, I) :- integer(I), !.
  ref_bdd(S, N) :-
          S =.. [F,A,B], ref_bdd(A, NA), ref_bdd(B, NB),
          clpb:apply_ref(F, NA, NB, N).

  % BDD als ite(Index, Low, High) – unabhängig von den Knoten-IDs
  canon(I, I) :- integer(I), !.
  canon(Node, ite(I, L, H)) :-
          clpb:node_var_low_high(Node, V, Low, High),
          clpb:var_index(V, I),
          canon(Low, L), canon(High, H).

  % ohne card und ^ (apply/4 und make_node/4 allein)
  rf2(0, Vs, V) :- !, random_member(V, Vs).
  rf2(D, Vs, F) :-
          random_integer(0, 7, K), D1 is D - 1,
          (   K =:= 0 -> rf2(0, Vs, F)
          ;   K =:= 1 -> rf2(D1, Vs, A), F = ~(A)
          ;   K =:= 2 -> rf2(D1, Vs, A), rf2(D1, Vs, B), F = A+B
          ;   K =:= 3 -> rf2(D1, Vs, A), rf2(D1, Vs, B), F = A*B
          ;   K =:= 4 -> rf2(D1, Vs, A), rf2(D1, Vs, B), F = #(A, B)
          ;   K =:= 5 -> rf2(D1, Vs, A), rf2(D1, Vs, B), F = (A=:=B)
          ;   rf2(D1, Vs, A), rf2(D1, Vs, B), F = (A=<B)
          ).

  compare_apply(Seed, Size) :-
          set_random(seed(Seed)),
          length(Vs, 6),
          rf2(5, Vs, F),
          clpb:parse_sat(F, Sat),
          clpb:sat_bdd(Sat, B1),
          ref_bdd(Sat, B2),
          canon(B1, C1), canon(B2, C2),
          (   C1 == C2, B1 == B2 -> true ; throw(verschieden(F, C1, C2)) ),
          clpb:bdd_nodes(B1, Ns), length(Ns, Size).

  % Hilfsvariablen (Y, Z): project_attributes/2 blendet sie aus
  hidden(X) :- sat(X =:= _Y*_Z).
  hidden2(X, Y) :- sat(X =:= Y*Z), sat(Z =< Y).

  % N Damen: je Zeile genau eine, je Spalte und Diagonale höchstens eine
  queens(N, Qss) :-
          length(Qss, N),
          maplist(row(N), Qss),
          maplist(exactly_one, Qss),
          transpose(Qss, Cols),
          maplist(at_most_one, Cols),
          cells(Qss, 0, Cs),
          no_diagonal(Cs).
  row(N, Qs) :- length(Qs, N).
  exactly_one(Ls) :- sat(card([1], Ls)).
  at_most_one(Ls) :- sat(card([0,1], Ls)).
  cells([], _, []).
  cells([R|Rs], I, Cs) :- row_cells(R, I, 0, Cs, Cs1), I1 is I+1, cells(Rs, I1, Cs1).
  row_cells([], _, _, Cs, Cs).
  row_cells([Q|Qs], I, J, [I-J-Q|Cs0], Cs) :- J1 is J+1, row_cells(Qs, I, J1, Cs0, Cs).
  no_diagonal([]).
  no_diagonal([C|Cs]) :- maplist(no_attack(C), Cs), no_diagonal(Cs).
  no_attack(I1-J1-Q1, I2-J2-Q2) :-
          (   abs(I1-I2) =:= abs(J1-J2) -> sat(~(Q1*Q2)) ; true ).
  """

  @rows [
    # aus der Dokumentation
    {"sat(X*Y)", ["X = 1, Y = 1"]},
    {"sat(X * ~X)", :fails},
    {"taut(X * ~X, T)", ["T = 0, sat(X=:=X)"]},
    {"sat(X^Y^(X+Y))", ["sat(X=:=X), sat(Y=:=Y)"]},
    {"sat(X*Y + X*Z), labeling([X,Y,Z])",
     ["X = 1, Y = 0, Z = 1", "X = 1, Y = 1, Z = 0", "X = 1, Y = 1, Z = 1"]},
    {"sat(X =< Y), sat(Y =< Z), taut(X =< Z, T)", ["T = 1, sat(X=:=X*Y), sat(Y=:=Y*Z)"]},
    {"sat(1#X#a#b)", ["sat(X=:=a#b)"]},
    {"sat(X=:=1), X = 1+0", :fails},
    {"X = 1+0, sat(X=:=1), X = 1+0", ["X = 1+0"]},
    {"xor(x, y, Z)", ["sat(Z=:=x#y)"]},
    {"pigeon(5, 4, _Rows, Cs), sat(*(Cs))", :fails},
    {"pigeon(2, 3, Rows, Cs), sat(*(Cs)), append(Rows, Vs), labeling(Vs)",
     {:first,
      [
        "Cs = [card([1],[0,0,1]),card([1],[0,1,0]),card([0,1],[0,0]),card([0,1],[0,1])," <>
          "card([0,1],[1,0])], Rows = [[0,0,1],[0,1,0]], Vs = [0,0,1,0,1,0]"
      ]}},
    # weitere Fälle
    {"sat(X+Y)", ["sat(X=\\=X*Y#Y)"]},
    {"sat(X#Y)", ["sat(X=\\=Y)"]},
    {"sat(X+Y), sat(~X)", ["X = 0, Y = 1"]},
    {"sat(X), sat(~X)", :fails},
    {"taut(X*Y, T)", :fails},
    {"taut(X+ ~X, T)", ["T = 1, sat(X=:=X)"]},
    {"taut(a + ~a, T)", ["T = 1"]},
    {"sat(a)", :fails},
    {"sat(a+b), sat(~a)", :fails},
    {"sat(X =:= Y), X = 1", ["X = 1, Y = 1"]},
    {"sat(A*B =:= C), A = 1, B = 0", ["A = 1, B = 0, C = 0"]},
    {"sat(+[X,Y,Z]), X = 0", ["X = 0, sat(Y=\\=Y*Z#Z)"]},
    {"sat(X # Y # Z), labeling([X,Y,Z])",
     {:first, ["X = 0, Y = 0, Z = 1", "X = 0, Y = 1, Z = 0", "X = 1, Y = 0, Z = 0"]}},
    {"sat(card([2],[X,Y,Z])), labeling([X,Y,Z])",
     ["X = 0, Y = 1, Z = 1", "X = 1, Y = 0, Z = 1", "X = 1, Y = 1, Z = 0"]},
    {"sat(card([1],[X,Y,Z]))", ["sat(X=\\=X*Y*Z#Y#Z)"]},
    {"sat(X+Y+Z), sat_count(X+Y+Z, N)", ["N = 7, sat(X=\\=X*Y#X*Y*Z#X*Z#Y#Y*Z#Z)"]},
    {"sat_count(+[1,X,Y,Z], C)", ["C = 8"]},
    {"length(Vs, 40), sat_count(+[1|Vs], C)", :succeeds},
    {"length(Vs, 40), sat_count(+[1|Vs], C), C =:= 2^40", :succeeds},
    {"weighted_maximum([1,2,1], [X,Y,Z], M)", ["M = 4, X = 1, Y = 1, Z = 1"]},
    {"sat(X # Y), weighted_maximum([3,2], [X,Y], M)", ["M = 3, X = 1, Y = 0"]},
    {"sat(card([2],[X,Y,Z])), weighted_maximum([-1,2,4], [X,Y,Z], M)",
     ["M = 6, X = 0, Y = 1, Z = 1"]},
    {"sat(X+Y), random_labeling(7, [X,Y]), sat(X+Y)", :succeeds},
    {"sat(card([1],[A,B,C,D])), sat_count(+[1,A,B,C,D], N)",
     ["N = 4, sat(A=\\=A*B*C#A*B*D#A*C*D#B#B*C*D#C#D)"]},
    {"queens(5, Qss), append(Qss, Vs), sat_count(+[1|Vs], 10)", :succeeds},
    {"queens(5, Qss), append(Qss, Vs), sat_count(+[1|Vs], 9)", :fails},
    {"queens(4, Qss), append(Qss, Vs), sat_count(+[1|Vs], 2)", :succeeds},
    {"queens(4, Qss), append(Qss, Vs), labeling(Vs)",
     [
       "Qss = [[0,0,1,0],[1,0,0,0],[0,0,0,1],[0,1,0,0]], Vs = [0,0,1,0,1,0,0,0,0,0,0,1,0,1,0,0]",
       "Qss = [[0,1,0,0],[0,0,0,1],[1,0,0,0],[0,0,1,0]], Vs = [0,1,0,0,0,0,0,1,1,0,0,0,0,0,1,0]"
     ]},
    {"queens(3, _)", :fails},
    # Restziele: project_attributes/2 (Toplevel) und copy_term/3
    {"hidden(X)", ["sat(X=:=X)"]},
    {"hidden2(X, Y)", ["sat(X=:=X*Y)"]},
    {"sat(X =:= Y*Z)", ["sat(X=:=Y*Z)"]},
    {"sat(X+Y), copy_term([X,Y], C, Gs)",
     ["C = [_A,_B], Gs = clpb:sat(_A=\\=_A*_B#_B), sat(X=\\=X*Y#Y)"]},
    # copy_term/3 lässt das Original unberührt
    {"sat(X+Y), copy_term([X,Y], _, _), sat(~X)", ["X = 0, Y = 1"]},
    {"sat(X+Y), copy_term(X, C, Gs)", ["Gs = clpb:sat(C=\\=C*_A#_A), sat(X=\\=X*Y#Y)"]},
    # random_integer/3 (library(random), wie Scryer)
    {"random_integer(1, 3, X), integer(X), X >= 1, X < 3", :succeeds},
    {"random_integer(1, 1, X)", :fails},
    {"random_integer(1, 3, 2)", :fails},
    # gebundenes X: scheitert immer (auch wenn es passen würde)
    {"random_integer(1, 2, 1)", :fails},
    # obere Grenze ausgeschlossen
    {"findall(X, (between(1, 50, _), random_integer(1, 2, X)), L), sort(L, [1])", :succeeds},
    {"random_integer(_, 3, X)", {:error, "instantiation_error"}},
    {"random_integer(a, 3, X)", {:error, "type_error(integer,a)"}},
    # Fehler
    {"sat(X)", ["X = 1"]},
    {"sat(f(x))", {:error, "domain_error(clpb_expr,f(x))"}},
    {"sat(X+2)", {:error, "domain_error(clpb_expr,"}},
    {"labeling([a])", {:error, "domain_error(clpb_variable,a)"}},
    {"labeling(x)", {:error, "type_error(list,x)"}}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @program, lines: true))
    # Operatoren der Bibliothek (#, ~) auch beim Schreiben in den Tests
    {:ok, reader: r, db: db, ops: Process.get(:prolog_ex_ops)}
  end

  setup c do
    Reader.put_current(c.reader)
    Process.put(:prolog_ex_ops, c.ops)
    :ok
  end

  for {q, expect} <- @rows do
    test q, c do
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end

  test "Propagation in Elixir gleich Triskas Prolog-Code (2000 Zufallsformeln)", c do
    q = "findall(K, (between(1, 2000, S), compare_propagation(S, K)), Ks)"
    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    counts = ~r/\b(falsch|wahr|nichts|fest|gleich)\b/ |> Regex.scan(a) |> Enum.frequencies()
    # genug Fälle mit Festlegungen und Gleichsetzungen, nicht nur Triviales
    assert Map.get(counts, ["fest", "fest"], 0) >= 50, inspect(counts)
    assert Map.get(counts, ["gleich", "gleich"], 0) >= 50, inspect(counts)
  end

  test "apply/4 und make_node/4 in Elixir gleich Triskas Prolog-Code (2000 Zufallsformeln)", c do
    q =
      "findall(N, (between(1, 2000, S), compare_apply(S, N)), Ns), sum_list(Ns, T), max_list(Ns, M)"

    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    # genug große BDDs dabei
    [_, total, max] =
      Regex.run(~r/M = (\d+), .*T = (\d+)/, a) |> then(fn [w, m, t] -> [w, t, m] end)

    assert String.to_integer(total) > 5000 and String.to_integer(max) >= 15, a
  end

  test "Propagation mit Atomen gleich Triskas Prolog-Code (2000 Zufallsformeln)", c do
    q = "findall(K, (between(1, 2000, S), compare_propagation_atoms(S, K)), Ks)"
    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    counts = ~r/\b(scheitert|prop)\b/ |> Regex.scan(a) |> Enum.frequencies()
    assert Map.get(counts, ["scheitert", "scheitert"], 0) >= 100, inspect(counts)
    assert Map.get(counts, ["prop", "prop"], 0) >= 100, inspect(counts)
  end

  test "parse_sat/2 in Elixir gleich Triskas Prolog-Code (3000 Zufallsterme)", c do
    q = "findall(K, (between(1, 3000, S), compare_parse(S, K)), Ks)"
    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    counts = ~r/\b(ok|fehler)\b/ |> Regex.scan(a) |> Enum.frequencies()
    assert Map.get(counts, ["ok", "ok"], 0) >= 300, inspect(counts)
    assert Map.get(counts, ["fehler", "fehler"], 0) >= 300, inspect(counts)
  end

  test "sat_bdd/2 in Elixir gleich Triskas Prolog-Code (2000 Zufallsformeln)", c do
    q = "findall(K, (between(1, 2000, S), compare_sat_bdd(S, K)), Ks)"
    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    counts = ~r/\b(ok|blatt|fehler)\b/ |> Regex.scan(a) |> Enum.frequencies()
    assert Map.get(counts, ["ok", "ok"], 0) >= 1000, inspect(counts)
    assert Map.get(counts, ["blatt", "blatt"], 0) >= 50, inspect(counts)
  end

  test "card/2: Fehler der Bereiche wie between/3", c do
    for {q, e} <- [
          {"sat(card([a-2], [X]))", "type_error(integer,a)"},
          {"sat(card([1-a], [X]))", "type_error(integer,a)"},
          {"sat(card([_-2], [X]))", "instantiation_error"},
          {"sat(card([f(_), 1], [X])), X == 1", nil},
          # memberchk/2: 1.0 ist nicht 1
          {"sat(card([1.0, 0], [X])), X == 0", nil},
          {"sat(card([2-infinite], [X, Y])), X == 1, Y == 1", nil},
          {"sat(card([2-inf], [X, Y])), X == 1, Y == 1", nil}
        ] do
      r = TableCase.run(c.reader, c.db, q)

      if e,
        do: assert({_, {:error, ^e}} = r),
        else: assert({_, {:answers, [_]}} = r)
    end
  end

  test "sat/1 in Elixir gleich Triskas Prolog-Code (1500 Folgen von Bedingungen)", c do
    q = "findall(K, (between(1, 1500, S), compare_sat(S, K)), Ks)"
    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    counts = ~r/\b(ok|scheitert|fehler)\b/ |> Regex.scan(a) |> Enum.frequencies()
    assert Map.get(counts, ["ok", "ok"], 0) >= 500, inspect(counts)
    assert Map.get(counts, ["scheitert", "scheitert"], 0) >= 200, inspect(counts)
  end

  test "taut/2 und Bindungen in Elixir gleich Triskas Prolog-Code (2000 Abläufe)", c do
    q = "findall(K, (between(1, 2000, S), compare_ops(S, K)), Ks)"
    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    counts = ~r/\b(ok|scheitert|fehler)\b/ |> Regex.scan(a) |> Enum.frequencies()
    assert Map.get(counts, ["ok", "ok"], 0) >= 500, inspect(counts)
    assert Map.get(counts, ["scheitert", "scheitert"], 0) >= 300, inspect(counts)
  end

  test "sat_count/2 in Elixir gleich Triskas Prolog-Code (1500 Fälle)", c do
    q =
      "findall(N, (between(1, 1500, S), compare_count(S, N)), Ns), " <>
        "include(integer, Ns, Is), length(Is, L), max_list(Is, M), sum_list(Is, T)"

    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    [_, l] = Regex.run(~r/L = (\d+)/, a)
    [_, m] = Regex.run(~r/M = (\d+)/, a)
    assert String.to_integer(l) >= 800, a
    assert String.to_integer(m) >= 16, a
  end

  test "sat_count/2: Sonderfälle wie das Original", c do
    for g <- [
          # Index-Reihenfolge weicht von der Reihenfolge in der Formel ab
          "sat(Y+Z), sat(X =< Y), sat_count(X + ~Y, N)",
          "sat(Z # Y), sat(X =< Z), sat_count(+[1, X, Y, Z], N)",
          "sat(C * ~B), sat(A + B), sat_count(A # C # B, N)",
          # monotonic: neue Variablen sind ein instantiation_error
          "assertz(clpb:monotonic), catch(sat_count(X+Y, N), E, true), " <>
            "retractall(clpb:monotonic)",
          "sat(X+Y), assertz(clpb:monotonic), sat_count(X*Y, N), retractall(clpb:monotonic)"
        ] do
      q = "compare_goal((#{g}), P)"
      assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q), g
      assert a =~ "ok(", a
    end
  end

  test "labeling/1, random_labeling/2, weighted_maximum/3: Sonderfälle wie das Original", c do
    for g <- [
          "catch(labeling([A|_]), E, true)",
          "catch(labeling([a]), E, true)",
          "catch(labeling(x), E, true)",
          "catch(labeling([1.0]), E, true)",
          "catch(labeling([A, 2]), E, true)",
          "sat(A+B), findall(A-B, labeling([B, 1, A, 0]), L)",
          "sat(A#B), sat(C =< A), findall(A-B-C, labeling([C, B, A, B]), L)",
          # Variablen ohne Bedingung: maybe_zero/1
          "sat(A+B), random_labeling(7, [A, B, C, D])",
          "random_labeling(3, [A, B])",
          "random_labeling(3, [1, 0])",
          "sat(card([2], [A, B, C, D])), findall(A-B-C-D, (between(1, 8, S), random_labeling(S, [A, B, C, D])), L)",
          # wiederholte Variablen, Gewicht 0, negative Gewichte
          "sat(A+B), findall(M-A-B, weighted_maximum([1, -2, 3], [A, B, A], M), L)",
          "sat(A#B), findall(M-A-B-C, weighted_maximum([0, 0, 1], [A, B, C], M), L)",
          "sat(card([1], [A, B, C])), findall(M-A-B-C, weighted_maximum([-1, -2, -3], [A, B, C], M), L)",
          "catch(weighted_maximum([a], [A], M), E, true)",
          "catch(weighted_maximum([1], [0], M), E, true)",
          "weighted_maximum([1, 2], [A], M)",
          # Index-Reihenfolge anders als die Reihenfolge der Variablen
          "sat(C =< B), sat(B =< A), findall(M-A-B-C, weighted_maximum([1, 2, 3], [A, B, C], M), L)",
          "sat(C # B), sat(B + A), findall(M-A-B-C, weighted_maximum([3, -1, 2], [A, B, C], M), L)",
          # Standardordnung anders als Index-Reihenfolge (früher attributiert)
          "freeze(C, true), freeze(B, true), sat(A + B * C), " <>
            "findall(M-A-B-C, weighted_maximum([1, -2, 3], [A, B, C], M), L)",
          # übersprungene Variable mit positivem Gewicht zwischen zwei Knoten
          "sat(A + ~A), sat(B + ~B), sat(C + ~C), sat(A =:= C), " <>
            "findall(M-A-B-C, weighted_maximum([1, 5, 1], [A, B, C], M), L)",
          "sat(A + ~A), sat(B + ~B), sat(C + ~C), sat(D + ~D), sat(A # D), " <>
            "findall(M-A-B-C-D, weighted_maximum([-1, 2, 0, 3], [A, B, C, D], M), L)"
        ] do
      q = "compare_goal((#{g}), P)"
      assert {_, {:answers, [_]}} = TableCase.run(c.reader, c.db, q), g
    end
  end

  test "Hook beim Binden: Sonderfälle wie das Original", c do
    for g <- [
          # keine Wahrheitswerte
          "sat(X+Y), catch(X = 2, E, true)",
          # [] ist ein Atom (allquantifiziert)
          "sat(X+Y), X = []",
          # Wurzel ohne Formel (nur über taut/2 angemeldet): scheitert,
          # bevor Other übersetzt wird
          "taut(X + ~X, _), catch(X = f(y), E, true)",
          # monotonic: Other ohne Index ist ein instantiation_error
          "sat(X+Y), freeze(Z, true), assertz(clpb:monotonic), " <>
            "catch(X = Z, E, true), retractall(clpb:monotonic)",
          # mehrere Bindungen in einer Unifikation
          "sat(X =\\= Y), sat(A =\\= B), f(X, Y) = f(A, B)",
          "sat(X =\\= Y), sat(A =:= B), f(X, Y) = f(A, B)",
          "sat(X + Y), sat(A * B), sat(C # D), f(X, Y, C) = f(A, D, B)"
        ] do
      q = "compare_goal((#{g}), P)"
      assert {_, {:answers, [_]}} = TableCase.run(c.reader, c.db, q), g
    end
  end

  # zufällige Anfragen: Antworten des Toplevels (project_attributes/2 und
  # attribute_goals//1) mit Elixir und mit Triskas Code (ref_mode)
  defp rand_formula(0) do
    Enum.random(~w(A B C D _H _H a b 0 1 A B C D))
  end

  defp rand_formula(d) do
    case :rand.uniform(10) do
      1 ->
        rand_formula(0)

      2 ->
        "~(#{rand_formula(d - 1)})"

      3 ->
        "#{Enum.random(["X#{d}", "_E#{d}"])}^(#{rand_formula(d - 1)})"

      4 ->
        "card([#{Enum.random(~w(0 1 2 1-2 0-1))}],[#{rand_formula(d - 1)},#{rand_formula(0)},#{rand_formula(0)}])"

      5 ->
        "+[#{rand_formula(d - 1)},#{rand_formula(d - 1)}]"

      _ ->
        op = Enum.random(~w(* + # =:= =\\= =< >= < >))
        "(#{rand_formula(d - 1)}) #{op} (#{rand_formula(d - 1)})"
    end
  end

  defp wrap_v(op) do
    if op =~ ~r/^(sat|taut|sat_count)\(/,
      do: Regex.replace(~r/\b([A-D]|_H)\b/, op, "v(\\1)"),
      else: op
  end

  defp rand_op do
    x = Enum.random(~w(A B C D))
    y = Enum.random(~w(A B C D))

    case :rand.uniform(16) do
      n when n <= 6 ->
        "sat(#{rand_formula(3)})"

      7 ->
        "taut(#{rand_formula(2)}, _)"

      8 ->
        "#{x} = #{Enum.random(~w(0 1))}"

      9 ->
        "#{x} = #{y}"

      10 ->
        "#{x} = #{Enum.random(~w(a b))}"

      11 ->
        "sat_count(#{rand_formula(2)}, _)"

      12 ->
        "f(#{x}, #{y}) = f(#{y}, #{x})"

      13 ->
        "weighted_maximum([#{Enum.random(~w(1 -1 2 0))},#{Enum.random(~w(1 -2 3))}], [#{x},#{y}], _)"

      14 ->
        "weighted_maximum([#{Enum.random(~w(1 -1 2 0))},#{Enum.random(~w(1 -2 3 0))},2], [A,B,C], M)"

      15 ->
        "labeling([#{Enum.join(Enum.take_random(~w(A B C D), Enum.random(1..4)), ",")}])"

      16 ->
        "random_labeling(#{:rand.uniform(100)}, [A,B,C,D])"
    end
  end

  test "Restziele des Toplevels in Elixir gleich Triskas Prolog-Code (600 Anfragen)", c do
    :rand.seed(:exsss, {17, 4, 2026})

    results =
      for _ <- 1..600 do
        ops = for _ <- 1..Enum.random(1..4), do: rand_op()

        prefix =
          case :rand.uniform(8) do
            1 -> "assertz(clpb:clpb_residuals(bdd)), "
            2 -> "assertz(clpb:monotonic), "
            _ -> ""
          end

        # unter monotonic: Variablen in Formeln als v(X)
        ops =
          if prefix =~ "monotonic",
            do: Enum.map(ops, &wrap_v/1),
            else: ops

        q = prefix <> Enum.join(ops, ", ")
        r1 = TableCase.run(c.reader, c.db, q)
        r2 = TableCase.run(c.reader, c.db, "assertz(clpb:ref_mode), " <> q)
        # interne Variablennummern (in Fehlern) normalisieren
        norm = fn r -> r |> inspect() |> String.replace(~r/_\d+/, "_") end
        assert norm.(r1) == norm.(r2), q
        r1
      end

    kinds = Enum.frequencies_by(results, fn {_, r} -> elem(r, 0) end)

    with_goals =
      Enum.count(results, fn {_, r} ->
        match?({:answers, [a | _]} when is_binary(a), r) and
          r |> elem(1) |> hd() |> String.contains?("sat(")
      end)

    assert with_goals >= 150, inspect({kinds, with_goals})

    # auch unter monotonic Antworten mit Restzielen (v(X) in der ANF)
    assert Enum.any?(results, fn {_, r} ->
             match?({:answers, [_ | _]}, r) and r |> elem(1) |> hd() |> String.contains?("v(")
           end)
  end

  test "sat/1: Zerlegung mit offenen Listen wie das Original", c do
    for g <- [
          "[L, *(L)]",
          "[L-X, *([X|L])]",
          "[L, ~(+(L))]",
          "[L-X, *(L)*X]",
          "[L-M, *(L) * *(M)]",
          "[L-X-Y, *([X,Y|L])]",
          "[L-X, ~(X + +(L))]",
          "[x, *([a|b])]",
          "[X, *([X|b]) * X]",
          "[L-X, *(L) * ~(X)]"
        ] do
      q = "compare_sat_ands(#{g}, P)"
      assert {_, {:answers, [_]}} = TableCase.run(c.reader, c.db, q), g
    end
  end

  test "parse_sat/2: Fehler mit monotonic", c do
    q =
      "assertz(clpb:monotonic), catch(sat(X+Y), E, true), retract(clpb:monotonic), " <>
        "catch(sat(v(X)), E2, true)"

    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    assert a =~ "E = error(instantiation_error,instantiation_error(unknown(_A),1))"
    assert a =~ "X = 1"

    # schon eingeschränkte Variablen sind auch mit monotonic erlaubt
    q =
      "sat(X+Y), assertz(clpb:monotonic), catch(sat(X=:=Y), E, true), retract(clpb:monotonic)"

    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    refute a =~ "E = "
    assert a =~ "X = 1, Y = 1"
  end

  test "existential/3 in Elixir gleich Triskas Prolog-Code (2000 Zufallsformeln)", c do
    q = "findall(N, (between(1, 2000, S), compare_existential(S, N)), Ns), sum_list(Ns, T)"
    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    [_, total] = Regex.run(~r/T = (\d+)/, a)
    assert String.to_integer(total) > 3000, a
  end

  test "Propagation: skip bei gebundener Variable; Atome", c do
    # eine gebundene Knotenvariable (sonst prüft der Hook beim Binden)
    q = "clpb:'$clpb_propagate'(node(7, x, 0, 1, _), P)"
    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    assert a =~ "P = skip"

    # a+X: nach Herausrechnen von X ist der BDD 1 – nichts zu tun
    q = "clpb:parse_sat(a+X, S), clpb:sat_bdd(S, B), clpb:'$clpb_propagate'(B, P)"
    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    assert a =~ "P = prop([],[],[])"

    # a*X: bleibt a – scheitert
    q = "clpb:parse_sat(a*X, S), clpb:sat_bdd(S, B), clpb:'$clpb_propagate'(B, P)"
    assert {_, {:answers, []}} = TableCase.run(c.reader, c.db, q)

    # a=:=X: Gleichsetzung mit dem Atom selbst
    q = "sat(a =:= X)"
    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    assert a =~ "X = a"

    # handgebaute Knoten: Variable ohne Index scheitert überall
    for q <- [
          "clpb:'$clpb_propagate'(node(0, V, 0, 1, _), P)",
          "clpb:'$clpb_existential'(V, 1, N)",
          "clpb:'$clpb_restriction'(node(7, V, 0, 1, _), 0, 1, R)"
        ] do
      assert {_, {:answers, []}} = TableCase.run(c.reader, c.db, q), q
    end

    # gebundene Knotenvariable: 0 nimmt Low, 1 nimmt High
    q =
      "clpb:'$clpb_restriction'(node(7, 0, 0, 1, _), 0, 1, R0), " <>
        "clpb:'$clpb_restriction'(node(7, 1, 0, 1, _), 0, 1, R1)"

    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    assert a =~ "R0 = 0, R1 = 1"

    # Fehler im BDD: eine an eine Zahl ungleich 0/1 gebundene Knotenvariable
    q = "clpb:'$clpb_restriction'(node(7, 2, 0, 1, _), 0, 1, R)"
    assert {_, {:error, e}} = TableCase.run(c.reader, c.db, q)
    assert e =~ "domain_error(clpb_expr,2)"
  end

  # Triskas Prüfprogramme (mit clpb:validation): run(N) scheitert, wenn
  # alle Formeln der Größe N übereinstimmen, und wirft sonst
  defp fixture(c, name) do
    PrologEx.put_db(%{})

    ExUnit.CaptureIO.capture_io(fn ->
      PrologEx.Consult.load_file("test/fixtures/clpb/#{name}")
    end)

    _ = c
    PrologEx.current_db()
  end

  defp holds?(c, db, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    ExUnit.CaptureIO.capture_io(fn ->
      send(self(), {:res, db |> PrologEx.query(g) |> Enum.take(1)})
    end)

    receive do
      {:res, r} -> r != []
    end
  end

  test "Triskas test_restrict.pl: labeling in jeder Reihenfolge (Größe 0 bis 2)", c do
    db = fixture(c, "test_restrict.pl")
    for n <- 0..2, do: assert(holds?(c, db, "\\+ run(#{n})"), "run(#{n})")
  end

  test "Triskas testing.pl: sat/1 und labeling/1 gegen Ausprobieren (Größe 0)", c do
    db = fixture(c, "testing.pl")
    assert holds?(c, db, "\\+ run(0)")
  end

  @tag :slow
  @tag timeout: :infinity
  test "Triskas testing.pl, Größe 1 (gut eine Minute)", c do
    db = fixture(c, "testing.pl")
    assert holds?(c, db, "\\+ run(1)")
  end
end
