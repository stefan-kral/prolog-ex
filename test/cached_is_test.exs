defmodule PrologEx.CachedIsTest do
  # cached_is/2 (library(iso_ext)): wie is/2, geteilte Teilausdrücke nur
  # einmal ausgewertet
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  @src """
  :- use_module(library(iso_ext)).
  % X+X über N Stufen: im Aufruf geteilt (gstruct), über eine Variable,
  % mit einer Variablen ganz unten
  d(0, X, X) :- !.
  d(N, X, Y) :- N1 is N-1, d(N1, X+X, Y).
  dv(0, X, X) :- !.
  dv(N, X, Y) :- N1 is N-1, Z = X+X, dv(N1, Z, Y).
  same(E) :-
      catch(X is E, B1, true),
      catch(cached_is(Y, E), B2, true),
      (   nonvar(B1) -> nonvar(B2), B1 = error(F, _), B2 = error(F, _)
      ;   var(B2), X == Y
      ).
  """

  defp ask(c, q, src \\ @src) do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))
    PrologEx.put_db(db)
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    db
    |> PrologEx.query(g)
    |> Enum.take(2)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  test "rechnet wie is/2: Werte und Fehler", c do
    for e <- [
          "1 + 2 * 3",
          "7 // 2",
          "-7 mod 3",
          "2 ** 10",
          "2 ^ 100",
          "2.0 ** 0.5",
          "max(3, 4.0)",
          "abs(-3) - sign(-2.5)",
          "sqrt(16)",
          "pi * e",
          "1 << 70",
          "\\ 5 /\\ 255",
          "truncate(3.7) + round(2.5)",
          "\"a\" + 1",
          "[0'b] + 0",
          "cot(1.0)",
          "gcd(12, 18)",
          "1 / 0",
          "1 // 0",
          "0 ^ -1",
          "foo + 1",
          "a",
          "1 + [a,b]",
          "_ + 1",
          "1 + f(_)",
          "sqrt(-1)",
          "log(0)",
          "2 ^ -1",
          "max_tagged_integer + 1"
        ] do
      assert ask(c, "same(#{e})") == ["true"], e
    end
  end

  test "geteilte Teilausdrücke: Tiefe 60 statt 2^60 Schritte", c do
    for d <- ["d", "dv"] do
      {us, res} = :timer.tc(fn -> ask(c, "#{d}(60, 1, _T), cached_is(V, _T)") end)
      assert res |> hd() =~ "V = 1152921504606846976", d
      assert us < 2_000_000, "#{d}: #{us} µs"
    end

    assert ask(c, "d(20, 1, _T), X is _T, cached_is(Y, _T), X == Y") != []
    assert ask(c, "d(10, 0.5, _T), cached_is(V, _T), V =:= 512") != []
    # tief: keine Rekursionsgrenze
    assert ask(c, "d(100000, 0, _T), cached_is(V, _T)") |> hd() =~ "V = 0"
  end

  test "Fehler in einem geteilten Teil: wie is/2", c do
    assert ask(c, "d(40, 1/0, _T), catch(cached_is(_, _T), error(E, _), true)") |> hd() =~
             "E = evaluation_error(zero_divisor)"

    assert ask(c, "d(40, _, _T), catch(cached_is(_, _T), error(E, _), true)") |> hd() =~
             "E = instantiation_error"
  end

  test "unrein (random, ...): je Vorkommen neu, wie is/2", c do
    # R - R mit R = random(10^9): fast sicher ungleich 0, bei is/2 wie hier
    assert ask(
             c,
             "R = random(1000000000), findall(S, (between(1, 5, _), cached_is(S, R - R)), Ss), " <>
               "\\+ maplist(==(0), Ss)",
             @src <> ":- use_module(library(between)).\n:- use_module(library(lists)).\n"
           ) != []

    # auch als Konstante (random/0) und tiefer im Ausdruck
    for r <- ["random", "random(1000000000) + 0", "1 + random_float * 2"] do
      assert ask(c, "R = (#{r}), cached_is(S, R - R), S =\\= 0") != [], r
    end

    # rein bleibt rein: ein unreiner Teil verhindert nur sein eigenes Merken
    assert ask(c, "d(50, 1, _T), cached_is(V, _T + random(1) - random(1)), V =:= 2^50") != []
  end

  test "Ergebnis unifiziert", c do
    assert ask(c, "cached_is(4, 2 + 2)") == ["true"]
    assert ask(c, "cached_is(5, 2 + 2)") == []
    assert ask(c, "cached_is(4.0, 2 + 2)") == []
  end

  test "nur nach use_module(library(iso_ext))", c do
    assert ask(c, "catch(cached_is(_, 1), error(E, _), true)", "") ==
             ["E = existence_error(procedure,cached_is/2)"]
  end
end
