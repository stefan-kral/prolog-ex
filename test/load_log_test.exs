defmodule PrologEx.LoadLogTest do
  # Flag verbose_load: was beim Laden wohin importiert wird
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.put_db(%{})
    on_exit(fn -> PrologEx.Flags.set("verbose_load", {:atom, "silent"}) end)
    :ok
  end

  defp run(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text <> ".")

    capture_io(:stderr, fn ->
      assert PrologEx.current_db() |> PrologEx.query(g) |> Enum.take(1) != []
    end)
  end

  test "silent (Vorgabe): nichts", c do
    assert run(c, "use_module(library(pairs))") == ""
  end

  test "normal: Laden und Zahl der Importe, geschachtelt eingerückt", c do
    out = run(c, "set_prolog_flag(verbose_load, normal), use_module(library(dcgs))")
    assert out =~ "% lade library(dcgs) ...\n"
    assert out =~ "%   dcgs ← lists: 1 Prädikat\n"
    assert out =~ "% library(dcgs) geladen (Modul dcgs, "
    assert out =~ "% user ← dcgs: 8 Prädikate\n"
    refute out =~ "phrase/2"
  end

  test "full: die Prädikate einzeln, auch bei Bibliotheken in Elixir", c do
    out = run(c, "set_prolog_flag(verbose_load, full), use_module(library(pairs))")
    assert out =~ "% user ← pairs: 6 Prädikate\n"
    assert out =~ "pairs_keys/2"

    out = run(c, "use_module(library(lists), [append/3])")
    assert out == "% user ← lists: 1 Prädikat\n%     append/3\n"

    assert run(c, "use_module(library(lists), [append/3])") == "% user ← lists: nichts Neues\n"
  end

  test "full: Operatoren", c do
    out = run(c, "set_prolog_flag(verbose_load, full), use_module(library(clpz))")
    assert out =~ ~r/% user ← clpz: \d+ Prädikate, \d+ Operatoren/
    assert out =~ "op(700, xfx, #=)"
  end

  test "ungültiger Wert", c do
    assert run(
             c,
             "catch(set_prolog_flag(verbose_load, laut), error(domain_error(flag_value, _), _), true)"
           ) == ""
  end
end
