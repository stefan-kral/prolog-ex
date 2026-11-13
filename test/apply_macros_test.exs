defmodule PrologEx.ApplyMacrosTest do
  # maplist/foldl/include/exclude/partition mit beim Laden bekannter
  # Closure werden Hilfsprädikate (PrologEx.ApplyMacros): dieselben
  # Antworten und Fehler wie ohne (Flag apply_macros beim Laden aus), auch
  # mit Lambdas, offenen Listen, verschieden langen Listen, Closure-
  # Variablen; eine eigene Definition von maplist bleibt unberührt
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @program """
  :- use_module(library(apply)).
  :- use_module(library(lists)).
  :- use_module(library(lambda)).
  :- use_module(library(iso_ext)).
  inc(X, Y) :- Y is X + 1.
  add(K, X, Y) :- Y is X + K.
  pos(X) :- X > 0.
  m1(L, M) :- maplist(inc, L, M).
  m2(K, L, M) :- maplist(add(K), L, M).
  m3(L) :- maplist(pos, L).
  m4(A, B, C) :- maplist(\\X^Y^Z^(Z is X * Y), A, B, C).
  m5(L, M) :- maplist(user:inc, L, M).
  m6(L) :- maplist(=(a), L).
  m7(L, M) :- maplist(\\X^Y^(Y = f(X, _)), L, M).
  m8(L, M) :- X = 5, maplist(\\Y^Z^(Z is Y + X), L, M).
  m9(N, L, M) :- maplist(N+\\X^Y^(Y is X + N), L, M).
  m10(L, M) :- maplist(\\(A-B)^(B-A)^true, L, M).
  m11(L, M) :- maplist(\\X^add(X), L, M).
  m12(L) :- maplist(\\X^Y^(Y is X), L).
  m13(L, M) :- maplist(undefined_pred, L, M).
  m14(L, M) :- ( maplist(inc, L, M) -> true ; M = none ).
  m15(L) :- \\+ maplist(pos, L).
  f1(L, S) :- foldl(\\X^A0^A^(A is A0 + X), L, 0, S).
  f2(L1, L2, S) :- foldl(\\X^Y^A0^A^(A is A0 + X * Y), L1, L2, 0, S).
  f3(L, S) :- foldl(add, L, 0, S).
  f4(A, B, C, S) :- foldl(\\X^Y^Z^S0^S1^(S1 is S0 + X + Y + Z), A, B, C, 0, S).
  i1(L, E) :- include(\\X^(X mod 2 =:= 0), L, E).
  i2(L, E) :- exclude(pos, L, E).
  i3(L, I, X) :- partition(\\X0^(X0 > 2), L, I, X).
  i4(L, E) :- include(\\(A-_)^(A > 1), L, E).
  i5(K, L, E) :- include(K+\\X^(X > K), L, E).
  % nichtdeterministisch: alle Lösungen, in derselben Reihenfolge
  in01(0).
  in01(1).
  n1(Xs) :- maplist(\\X^(X = 0 ; X = 1), Xs).
  n2(Xs) :- maplist(in01, Xs).
  n3(Xs, Ys) :- maplist(\\X^Y^(member(X-Y, [a-1, b-2, a-3])), Xs, Ys).
  """

  # eine eigene Definition, auch erst nach dem Aufruf: der Aufruf bleibt
  @own """
  :- use_module(library(apply)).
  inc(X, Y) :- Y is X + 1.
  o1(L, M) :- maplist(inc, L, M).
  o2(L) :- maplist(inc, L).
  maplist(_, _, own).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    terms = Reader.read_terms(r, @program)
    own = Reader.read_terms(r, @own)
    PrologEx.Flags.set("apply_macros", {:atom, "true"})
    {on, _} = PrologEx.Consult.load(%{}, terms)
    {own_db, _} = PrologEx.Consult.load(%{}, own)
    PrologEx.Flags.set("apply_macros", {:atom, "false"})
    {off, _} = PrologEx.Consult.load(%{}, terms)
    PrologEx.Flags.set("apply_macros", {:atom, "true"})
    {:ok, reader: r, on: on, off: off, own: own_db}
  end

  test "Hilfsprädikate entstehen, wo die Closure bekannt ist", c do
    aux = for {{"user", "$apply_" <> _ = n, a}, _} <- c.on, do: {n, a}
    assert length(aux) >= 15

    assert aux
           |> Enum.filter(fn {n, _} -> String.starts_with?(n, "$apply_maplist_3") end)
           |> length() >= 6

    assert [] == for({{"user", "$apply_" <> _, _}, _} <- c.off, do: 1)
  end

  for q <- [
        "m1([1,2,3], M)",
        "m1([], M)",
        "m1(L, [2,3])",
        "m1([1|T], M)",
        "m2(10, [1,2], M)",
        "m3([1,2])",
        "m3([1,-2])",
        "m4([1,2], [3,4], C)",
        "m4([1,2], [3], C)",
        "m5([1,2], M)",
        "m6(L)",
        "findall(L, (m6(L), length(L, N), (N >= 3 -> ! ; true)), Ls)",
        "m6([a,a,b])",
        "m7([1,2], M)",
        "m8([1,2], M)",
        "m9(7, [1,2], M)",
        "m10([1-a, 2-b], M)",
        "m11([1,2], M)",
        "catch(m12([1,2]), error(E, _), true)",
        "catch(m13([1], M), error(E, _), true)",
        "m14([1,2], M)",
        "m14([1,a], M)",
        "catch(m14([1,a], M), error(E, _), true)",
        "m15([1,-1])",
        "m15([1])",
        "f1([1,2,3], S)",
        "f1([], S)",
        "f2([1,2], [3,4], S)",
        "f2([1,2], [3], S)",
        "f3([1,2,3], S)",
        "f4([1], [2], [3], S)",
        "i1([1,2,3,4], E)",
        "i2([1,-2,3,-4], E)",
        "i3([1,2,3,4], I, X)",
        "i4([1-a, 2-b, 3-c], E)",
        "i5(2, [1,2,3,4], E)",
        "call_with_inference_limit(m1([1,2], _), 1000, R)",
        "length(Xs, 4), findall(Xs, n1(Xs), L)",
        "length(Xs, 4), findall(Xs, n2(Xs), L)",
        "length(Xs, 12), countall(n1(Xs), N)",
        "length(Xs, 12), countall(n2(Xs), N)",
        "n1(Xs)",
        "findall(Xs-Ys, n3([a, b], Ys), L)",
        "findall(Xs-Ys, (length(Xs, 2), n3(Xs, Ys)), L)"
      ] do
    test q, c do
      Reader.put_current(c.reader)
      on = TableCase.run(c.reader, c.on, unquote(q))
      off = TableCase.run(c.reader, c.off, unquote(q))
      assert on == off, "mit: #{inspect(on)}\nohne: #{inspect(off)}"
    end
  end

  test "eigenes maplist/3 (auch nach dem Aufruf definiert): keine Hilfsprädikate dafür", c do
    Reader.put_current(c.reader)
    assert {_, {:answers, ["M = own"]}} = TableCase.run(c.reader, c.own, "o1([1,2], M)")
    # maplist/2 definiert der Text nicht selbst – aber derselbe Name: auch
    # nicht (die Prüfung geht nach dem Namen)
    assert [] == for({{"user", "$apply_" <> _, _}, _} <- c.own, do: 1)
  end

  test "Lambda mit fremder Variable: kein Inline, aber dasselbe Ergebnis", c do
    # m8: X kommt auch außerhalb des Lambdas vor – das Hilfsprädikat ruft
    # das Lambda (\/3), statt seinen Rumpf einzusetzen
    [{_, {:pred, _, _, _, _} = p}] =
      for {{"user", "$apply_maplist_3_" <> _, 5}, _} = e <- c.on, do: e

    src = PrologEx.pred_source(p) |> inspect()
    assert src =~ "\"\\\\\""
  end
end
