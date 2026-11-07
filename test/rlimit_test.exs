defmodule PrologEx.RlimitTest do
  # library(rlimit) wie SWI über prlimit (Linux, util-linux). Nur harmlose
  # Änderungen: nofile weit über dem Bedarf und gleich zurück, core.
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag skip: System.find_executable("prlimit") == nil and "ohne prlimit"

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  @src ":- use_module(library(rlimit)).\n"

  defp ask(c, q, src \\ @src) do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))
    PrologEx.put_db(db)
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    db
    |> PrologEx.query(g)
    |> Enum.take(2)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, goal), do: ask(c, "catch((#{goal}), error(E, _), true)")

  # weiche Grenze laut prlimit
  defp soft(r) do
    {out, 0} =
      System.cmd("prlimit", [
        "--pid",
        System.pid(),
        "--#{r}",
        "--output",
        "SOFT",
        "--raw",
        "--noheadings"
      ])

    String.trim(out)
  end

  test "lesen: wie prlimit, Zahl oder unlimited", c do
    for r <- ~w(nofile cpu as core stack nproc) do
      v = soft(r)
      assert ask(c, "rlimit(#{r}, L, L)") == ["L = #{v}"], r
      # New ungebunden: nur lesen, New = Old
      assert ask(c, "rlimit(#{r}, L, N), L == N") |> hd() =~ "L = #{v}", r
    end
  end

  test "setzen und zurücksetzen (weiche Grenze, harte bleibt)", c do
    old = soft("nofile")
    new = div(String.to_integer(old), 2)

    assert ask(c, "rlimit(nofile, Old, #{new}), rlimit(nofile, Now, Now)") ==
             ["Now = #{new}, Old = #{old}"]

    assert soft("nofile") == "#{new}"
    assert ask(c, "rlimit(nofile, Old, #{old})") == ["Old = #{new}"]
    assert soft("nofile") == old
    # gleich Old: nichts zu tun
    assert ask(c, "rlimit(nofile, #{old}, #{old})") == ["true"]
    assert ask(c, "rlimit(nofile, 1, _)") == []
  end

  test "Fehler", c do
    assert err(c, "rlimit(nofile, _, 999999999999)") ==
             ["E = permission_error(modify,rlimit,nofile)"]

    assert err(c, "rlimit(foo, _, _)") == ["E = domain_error(rlimit,foo)"]
    assert err(c, "rlimit(_, _, _)") == ["E = instantiation_error"]
    assert err(c, "rlimit(1, _, _)") == ["E = type_error(atom,1)"]
    assert err(c, "rlimit(nofile, _, -1)") == ["E = domain_error(not_less_than_zero,-1)"]
    assert err(c, "rlimit(nofile, _, a)") == ["E = type_error(integer,a)"]
    assert err(c, "rlimit(nofile, _, 1.5)") == ["E = type_error(integer,1.5)"]
  end

  test "core: unlimited und Zahl", c do
    old = soft("core")
    assert ask(c, "rlimit(core, _, 0), rlimit(core, L, L)") == ["L = 0"]
    assert ask(c, "rlimit(core, _, #{old})") != []
  end

  test "nur nach use_module(library(rlimit))", c do
    assert ask(c, "catch(rlimit(nofile, L, L), error(E, _), true)", "") ==
             ["E = existence_error(procedure,rlimit/3)"]
  end
end
