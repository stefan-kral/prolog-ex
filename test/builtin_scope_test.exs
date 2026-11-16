defmodule PrologEx.BuiltinScopeTest do
  # Hilfs-Builtins einer Bibliothek ('$clpz_...', '$rb_...'): nur in deren
  # Modul sichtbar (PrologEx.Builtins.scope/2)
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  defp out(c, db, q), do: inspect(elem(TableCase.run(c.reader, db, q), 1))

  test "aus den Quelltexten ermittelt" do
    assert PrologEx.Builtins.scope("$clpz_fd_get", 3) == "clpz"
    assert PrologEx.Builtins.scope("$rb_insert", 4) == "rbtrees"
    # in Prolog geschriebene Prädikate von system bleiben überall sichtbar
    assert PrologEx.Builtins.scope("$nse_call", 1) == nil
  end

  test "aus user: nicht sichtbar, auch nicht nach use_module; qualifiziert schon", c do
    o = out(c, %{}, "catch('$clpz_neq_num'(_, _), error(E, _), true)")
    assert o =~ "existence_error(procedure,'$clpz_neq_num'/2)"

    assert out(c, %{}, "predicate_property('$clpz_fd_get'(_, _, _), built_in)") ==
             "{:answers, []}"

    {db, []} =
      PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, ":- use_module(library(clpz)).\n"))

    o = out(c, db, "catch('$clpz_fd_get'(X, D, Ps), error(E, _), true)")
    assert o =~ "existence_error(procedure,'$clpz_fd_get'/3)"
    assert out(c, db, "X in 1..3, clpz:'$clpz_fd_get'(X, D, _)") =~ "D = [1..3]"
  end
end
