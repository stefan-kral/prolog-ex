defmodule PrologEx.StackLimitTest do
  # Flag stack_limit: Speichergrenze je Anfrage (wie SWI), Diagnose im
  # Fehler (offene Ziele, Choice Points, beherrschendes Prädikat), assertz/1
  # mit riesigem Baum
  use ExUnit.Case, async: false
  alias PrologEx.Reader
  import ExUnit.CaptureIO

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Flags.reset()
    on_exit(fn -> PrologEx.Flags.reset() end)
    :ok
  end

  @src """
  :- use_module(library(iso_ext)).
  p1(X) :- p1(X+X).
  p2(X) :- p2(X), p2(X).
  d(0, X, X) :- !.
  d(N, X, Y) :- N1 is N-1, d(N1, X+X, Y).
  dv(0, X, X) :- !.
  dv(N, X, Y) :- N1 is N-1, Z = X+X, dv(N1, Z, Y).
  mk(0, []) :- !.
  mk(N, [f(N, _)|T]) :- N1 is N-1, mk(N1, T).
  :- dynamic(f/1).
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

  defp limit!(bytes), do: PrologEx.Flags.set("stack_limit", bytes)

  test "Flag: Voreinstellung 1 GiB, Zahl oder unlimited", c do
    assert ask(c, "current_prolog_flag(stack_limit, L)") == ["L = 1073741824"]

    assert ask(c, "set_prolog_flag(stack_limit, unlimited), current_prolog_flag(stack_limit, L)") ==
             ["L = unlimited"]

    assert ask(c, "catch(set_prolog_flag(stack_limit, 0), error(E, _), true)") ==
             ["E = domain_error(flag_value,stack_limit+0)"]

    assert ask(c, "catch(set_prolog_flag(stack_limit, foo), error(E, _), true)") ==
             ["E = domain_error(flag_value,stack_limit+foo)"]
  end

  test "endlose Rekursion: resource_error mit Tiefe und Prädikat", c do
    limit!(30_000_000)
    [a] = ask(c, "catch(p2(a), E, true)")

    assert a =~
             ~r/^E = error\(resource_error\(memory\),context\(stack_limit,memory\(30000000,\d+,\d+,\[p2\/1\]\)\)\)$/

    [_, depth] = Regex.run(~r/memory\(30000000,(\d+),/, a)
    assert String.to_integer(depth) > 10_000
  end

  test "wachsende Daten: flacher Stapel, kein Prädikat", c do
    limit!(30_000_000)
    [a] = ask(c, "catch(p1(a), E, true)")

    assert a =~
             ~r/^E = error\(resource_error\(memory\),context\(stack_limit,memory\(30000000,\d,\d,\[\]\)\)\)$/
  end

  test "eingebautes Prädikat: vorab, ohne Maschinenzustand", c do
    limit!(30_000_000)

    assert ask(c, "catch(length(_, 100000000), E, true)") ==
             ["E = error(resource_error(memory),context(stack_limit,memory(30000000)))"]
  end

  test "gemessen ab dem Start der Anfrage; die nächste Anfrage beginnt neu", c do
    limit!(30_000_000)
    assert ask(c, "mk(20000, L), length(L, N)") |> hd() =~ "N = 20000"
    assert ask(c, "mk(20000, L), length(L, N)") |> hd() =~ "N = 20000"
    # Grenze nur, solange die Anfrage läuft: danach keine mehr aktiv
    refute PrologEx.mem_limited?()
  end

  test "gilt auch beim Backtracking (weitere Antworten)", c do
    limit!(30_000_000)
    assert [a1, a2] = ask(c, "catch((X = 1 ; p2(a)), E, true)")
    assert a1 =~ "X = 1"
    assert a2 =~ "context(stack_limit,memory(30000000,"
  end

  test "Zuwachs ab dem Heap beim Start, nicht absolut", c do
    # der Prozess hält schon viel (hier 3 Mio. Listenzellen, ~48 MB)
    big = Enum.to_list(1..3_000_000)
    limit!(20_000_000)
    assert ask(c, "mk(1000, L), length(L, N)") |> hd() =~ "N = 1000"
    assert length(big) == 3_000_000
  end

  test "unlimited: keine Grenze", c do
    limit!(PrologEx.a("unlimited"))
    assert ask(c, "length(L, 2000000), length(L, N)") |> hd() =~ "N = 2000000"
  end

  test "call_with_memory_limit/2 innerhalb: die engere gilt", c do
    [a] = ask(c, "catch(call_with_memory_limit(p2(a), 10000000), E, true)")
    assert a =~ "context(call_with_memory_limit/2,memory(10000000,"
    assert a =~ "[p2/1]"
  end

  test "assertz/1 mit geteiltem Riesenterm: resource_error statt hängen", c do
    # unter der Standardgrenze (1 GiB): vorab abgelehnt
    {us, res} = :timer.tc(fn -> ask(c, "d(40, a, _T), catch(assertz(f(_T)), E, true)") end)
    assert res == ["E = error(resource_error(memory),context(stack_limit,memory(1073741824)))"]
    assert us < 2_000_000
    # geteilt über Variablen (Z = X+X) ebenso schnell
    {us, res} =
      :timer.tc(fn -> ask(c, "dv(40, a, _T), catch(assertz(f(_T)), error(E, _), true)") end)

    assert res == ["E = resource_error(memory)"]
    assert us < 2_000_000
    # mit Variablen ebenso
    assert ask(c, "d(40, _, _T), catch(assertz(f(_T)), error(E, _), true)") ==
             ["E = resource_error(memory)"]

    # ohne Grenze: ab 50 Mio. Knoten
    limit!(PrologEx.a("unlimited"))

    assert ask(c, "d(40, a, _T), catch(assertz(f(_T)), error(E, _), true)") ==
             ["E = resource_error(memory)"]

    # klein genug: geht, und die Klausel ist richtig
    assert ask(c, "d(12, a, _T), assertz(f(_T)), f(X), X == _T") != []
    # gewöhnliche große Fakten gehen weiter
    assert ask(
             c,
             "numlist(1, 50000, L), assertz(f(L)), f(M), length(M, N)",
             @src <> ":- use_module(library(lists)).\n"
           )
           |> hd() =~ "N = 50000"
  end

  test "Toplevel: Hinweis mit Grenze, Tiefe und Prädikat" do
    f = Path.join(System.tmp_dir!(), "pex_sl_#{System.unique_integer([:positive])}.pl")
    File.write!(f, "p1(X) :- p1(X+X).\np2(X) :- p2(X), p2(X).\n")

    out =
      capture_io(
        "consult('#{f}').\nset_prolog_flag(stack_limit, 20000000).\np2(a).\np1(a).\nlength(_, 100000000).\n",
        fn -> PrologEx.Toplevel.main(["-q"]) end
      )

    File.rm(f)
    assert out =~ "Fehler: resource_error(memory)"

    assert out =~
             ~r/% Speichergrenze überschritten: stack_limit = 19\.1 MiB \(ändern: set_prolog_flag\(stack_limit, Bytes\) oder unlimited\)\. Offene Ziele: \d+, Choice Points: \d+\. Wahrscheinlich endlose Rekursion in p2\/1\./

    assert out =~ "Der Stapel ist flach: es wachsen die Daten"
    assert out =~ "Ein eingebautes Prädikat hätte auf einen Schlag mehr Speicher gebraucht."
  after
    PrologEx.Toplevel.reset_session()
  end
end
