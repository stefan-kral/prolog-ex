defmodule PrologEx.MemoryLimitTest do
  # call_with_memory_limit/2 (library(iso_ext)): Prüfpunkte wie bei den
  # Zeitgrenzen, große Einzelanforderungen eingebauter Prädikate vorab
  # (PrologEx.reserve!/1)
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
  :- use_module(library(between)).
  :- use_module(library(lists)).
  mk(0, []) :- !.
  mk(N, [f(N, _)|T]) :- N1 is N-1, mk(N1, T).
  """

  # 10 MB
  @lim 10_000_000
  # error(resource_error(memory), context(call_with_memory_limit/2, memory(...)))
  defp mem!(res, msg \\ "") do
    assert [a] = res, msg
    assert a =~ "E = error(resource_error(memory),context(call_with_memory_limit/2,memory(", msg
  end

  defp ask(c, q, src \\ @src) do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))
    PrologEx.put_db(db)
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    db
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp catching(c, g), do: ask(c, "catch((#{g}), E, true)")

  test "unter der Grenze: wie once/1", c do
    assert ask(c, "call_with_memory_limit((mk(1000, L), length(L, N)), #{@lim})") |> hd() =~
             "N = 1000"

    assert ask(c, "call_with_memory_limit(member(X, [a, b]), #{@lim})") == ["X = a"]
    assert ask(c, "call_with_memory_limit(fail, #{@lim})") == []
  end

  test "über der Grenze: resource_error(memory)", c do
    assert catching(c, "call_with_memory_limit((mk(200000, L), length(L, _)), #{@lim})") |> mem!()

    # findall sammelt in einer Unter-Maschine: auch sie wird geprüft
    assert catching(c, "call_with_memory_limit(findall(L, mk(200000, L), _), #{@lim})") |> mem!()
  end

  test "Müll zählt nicht: unerreichbare Daten räumt die Bereinigung weg", c do
    assert ask(c, "call_with_memory_limit(mk(200000, _), #{@lim})") == ["true"]
  end

  test "nicht verschluckbar: fängt G die Ausnahme selbst, kommt sie wieder", c do
    assert catching(
             c,
             "call_with_memory_limit((mk(200000, L), catch(length(L, _), _, true), " <>
               "between(1, 5000, _), fail ; true), #{@lim})"
           )
           |> mem!()
  end

  test "danach ist die Grenze weg (Ausgang, Fehlschlag, Ausnahme)", c do
    assert ask(c, "call_with_memory_limit(true, 1000), mk(200000, L), length(L, N)") |> hd() =~
             "N = 200000"

    assert ask(c, "(call_with_memory_limit(fail, 1000) ; true), mk(200000, L), length(L, N)")
           |> hd() =~ "N = 200000"

    assert ask(
             c,
             "catch(call_with_memory_limit(throw(x), 1000), x, true), mk(200000, L), length(L, N)"
           )
           |> hd() =~ "N = 200000"
  end

  test "verschachtelt: die engere Grenze gilt", c do
    assert catching(
             c,
             "call_with_memory_limit(call_with_memory_limit((mk(200000, L), length(L, _)), " <>
               "1000000000), #{@lim})"
           )
           |> mem!()

    assert catching(
             c,
             "call_with_memory_limit(call_with_memory_limit((mk(200000, L), length(L, _)), " <>
               "#{@lim}), 1000000000)"
           )
           |> mem!()
  end

  test "große Einzelanforderungen vorab", c do
    for g <- [
          "length(_, 100000000)",
          "numlist(1, 100000000, _)",
          "numlist(1, 1, 100000000, _, _)",
          "_ is 3 ^ 100000000",
          "_ is 3 ** 100000000",
          "_ is 1 << 1000000000"
        ] do
      assert catching(c, "call_with_memory_limit(#{g}, #{@lim})") |> mem!(g)
    end

    # über max_arity (2^16): kein Speicherfehler, die Stelligkeit ist zu groß
    assert catching(c, "call_with_memory_limit(functor(_, f, 50000000), #{@lim})") ==
             ["E = error(representation_error(max_arity),_A)"]

    # klein genug: geht
    for g <- [
          "length(_, 20000)",
          "numlist(1, 20000, _)",
          "functor(_, f, 20000)",
          "_ is 3 ^ 5000",
          "_ is 1 << 100000"
        ] do
      assert ask(c, "call_with_memory_limit(#{g}, #{@lim})") == ["true"], g
    end
  end

  test "ohne Grenze: große Zahlen wie bisher", c do
    assert ask(c, "X is 3 ^ 100000, X > 0") != []
    assert ask(c, "X is 1 << 100000, X > 0") != []
  end

  test "Fehler im Argument", c do
    assert catching(c, "call_with_memory_limit(true, _)") |> hd() =~ "instantiation_error"

    assert catching(c, "call_with_memory_limit(true, 0)") |> hd() =~
             "domain_error(positive_integer,0)"

    assert catching(c, "call_with_memory_limit(true, a)") |> hd() =~ "type_error(integer,a)"
  end

  test "nur nach use_module(library(iso_ext))", c do
    assert ask(c, "catch(call_with_memory_limit(true, 1), error(E, _), true)", "") ==
             ["E = existence_error(procedure,call_with_memory_limit/2)"]
  end
end
