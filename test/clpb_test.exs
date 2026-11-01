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

  test "Propagation: skip bei gebundener Variable, universal bei Atomen", c do
    # eine gebundene Knotenvariable (sonst prüft der Hook beim Binden)
    q = "clpb:'$clpb_propagate'(node(7, x, 0, 1, _), P)"
    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    assert a =~ "P = skip"

    q = "clpb:parse_sat(a+X, S), clpb:sat_bdd(S, B), clpb:'$clpb_propagate'(B, P)"
    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    assert a =~ "P = universal"
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
