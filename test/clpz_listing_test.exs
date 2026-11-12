defmodule PrologEx.ClpzListingTest do
  # clpz_listing/0,1: was von library(clpz) in Elixir läuft
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    {clpz, []} =
      PrologEx.Consult.load(%{}, Reader.read_terms(r, ":- use_module(library(clpz)).\n"))

    {:ok, reader: r, clpz: clpz}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  defp out(c, db, q), do: elem(TableCase.run(c.reader, db, q), 0)

  test "Übersicht: Zahlen, Stufen, Propagatoren", c do
    o = out(c, c.clpz, "clpz_listing")
    assert o =~ ~r"% library\(clpz\): \d+ Prädikate – \d+ in Elixir, \d+ mit Abkürzer"
    assert o =~ ~r"% fd_get/3 +mit Rückfall +→ '\$clpz_fd_get'/3; Original fd_get_ref/3"
    assert o =~ ~r"% select_var/4 +mit Rückfall +'\$clpz_select_var'/4; Original select_var_ref/4"
    assert o =~ ~r"% clpz_neq/2 +mit Rückfall +'\$clpz_neq_kind'/3, '\$clpz_neq_fast'/3"
    assert o =~ ~r"% all_distinct/1 +mit Rückfall +'\$clpz_all_distinct_post'/1"
    assert o =~ ~r"% scalar_product_eq +Elixir +fällt zurück"
    assert o =~ ~r"% pgcc +Prolog +run_propagator//2"
    # Prolog-Logik mit Bausteinen steht nicht in der Übersicht
    refute o =~ ~r"% label/5 "
  end

  test "ein Prädikat, ein Propagator im Einzelnen", c do
    o = out(c, c.clpz, "clpz_listing(label/5)")
    assert o =~ "% label/5: Prolog mit Elixir-Bausteinen"
    assert o =~ "%     ruft '$clpz_fd_get'/3 (Original fd_get_ref/3)"

    o = out(c, c.clpz, "clpz_listing(all_distinct)")
    assert o =~ "% all_distinct/1: Prüfungen in Prolog, der Rest in Elixir"
    assert o =~ "% all_distinct/3: Prolog"

    o = out(c, c.clpz, "clpz_listing(scalar_product_eq)")
    assert o =~ "% Propagator scalar_product_eq: Elixir"

    assert out(c, c.clpz, "clpz_listing(gibts_nicht)") =~ "nichts dergleichen"
    assert out(c, %{}, "clpz_listing") =~ "nicht geladen"
  end

  # jeder Propagator, den ClpzPrims rechnet, ist ein Fall von
  # run_propagator//2 (sonst stimmte @ported nicht mehr mit clpz.pl)
  test "ClpzPrims.ported/0 passt zu run_propagator//2", c do
    o = out(c, c.clpz, "clpz_listing")

    for p <- PrologEx.Builtins.ClpzPrims.ported() do
      assert o =~ ~r"% #{p} +Elixir ", p
    end
  end
end
