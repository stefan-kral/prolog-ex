defmodule PrologEx.ExpansionHooksTest do
  # Bibliotheksmodule melden ihre Expansions-Hooks an ('$expansion_hooks'/0);
  # prolog_load_context/2
  use ExUnit.Case, async: false
  alias PrologEx.{Consult, Reader}

  setup do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    PrologEx.put_db(%{})
    dir = Path.join(System.tmp_dir!(), "px_exph_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, reader: r, dir: dir}
  end

  defp write(c, name, text), do: File.write!(Path.join(c.dir, name), text)
  defp load(c, name), do: {:ok, _} = Consult.load_file(Path.join(c.dir, name))

  defp ask(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(5)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  test "zwei Bibliotheken mit term_expansion/goal_expansion nebeneinander", c do
    write(c, "m1.pl", """
    :- module(m1, []).
    :- '$expansion_hooks'.
    term_expansion(aa(X), bb(X)).
    goal_expansion(g1, true).
    """)

    write(c, "m2.pl", """
    :- module(m2, []).
    :- '$expansion_hooks'.
    term_expansion(cc(X), [dd(X), ee(X)]).
    goal_expansion(g2, true).
    """)

    write(c, "main.pl", """
    :- use_module(m1).
    :- use_module(m2).
    aa(1).
    cc(2).
    t :- g1, g2.
    """)

    load(c, "main.pl")
    assert ask(c, "bb(X), dd(Y), ee(Z), t.") == ["X = 1, Y = 2, Z = 2"]
    # erneutes Laden einer Bibliothek: keine doppelte Anmeldung, Hooks wie vorher
    load(c, "m1.pl")

    assert Map.get(PrologEx.current_db(), :expansion_hooks) == [
             {"term_expansion", "m1", "term_expansion"},
             {"goal_expansion", "m1", "goal_expansion"},
             {"term_expansion", "m2", "term_expansion"},
             {"goal_expansion", "m2", "goal_expansion"}
           ]
  end

  test "Quellmodul und user gehen vor; der erste Hook, der gelingt, zählt", c do
    write(c, "m1.pl", """
    :- module(m1, []).
    :- '$expansion_hooks'.
    term_expansion(aa(_), lib).
    """)

    write(c, "main.pl", """
    :- use_module(m1).
    term_expansion(aa(_), own).
    aa(1).
    aa(2) :- true.
    """)

    load(c, "main.pl")
    assert ask(c, "own.") == ["true"]
    assert ask(c, "catch(lib, error(E, _), true).") == ["E = existence_error(procedure,lib/0)"]
  end

  test "prolog_load_context/2: module, source, file (include), directory, dialect", c do
    write(c, "lib.pl", """
    :- module(lib, []).
    :- '$expansion_hooks'.
    term_expansion(here, ctx(M, S)) :- prolog_load_context(module, M), prolog_load_context(source, S).
    """)

    write(c, "inc.pl", """
    :- prolog_load_context(file, F), assertz(incf(F)).
    :- prolog_load_context(source, F), assertz(incs(F)).
    """)

    write(c, "main.pl", """
    :- use_module(lib).
    here.
    :- include(inc).
    :- prolog_load_context(directory, D), assertz(dir(D)).
    :- prolog_load_context(dialect, D), assertz(dia(D)).
    :- findall(K, prolog_load_context(K, _), Ks), assertz(keys(Ks)).
    :- module(other, []).
    :- prolog_load_context(module, M), assertz(user:mod(M)).
    """)

    load(c, "main.pl")
    main = Path.join(c.dir, "main.pl")
    assert ask(c, "ctx(M, S).") == ["M = user, S = '#{main}'"]
    assert ask(c, "incf(F).") == ["F = '#{Path.join(c.dir, "inc.pl")}'"]
    assert ask(c, "incs(F).") == ["F = '#{main}'"]
    assert ask(c, "dir(D).") == ["D = '#{c.dir}'"]
    assert ask(c, "dia(D).") == ["D = prolog_ex"]
    assert ask(c, "keys(Ks).") == ["Ks = [module,dialect,source,file,directory]"]
    assert ask(c, "mod(M).") == ["M = other"]
    # außerhalb des Ladens: scheitert
    assert ask(c, "prolog_load_context(module, _).") == []
  end

  test "einzeln angemeldet: nur diese Art, unter eigenem Namen; das Programm behält seine", c do
    write(c, "lib.pl", """
    :- module(lib, []).
    :- '$expansion_hooks'(goal_expansion, my_goal_hook).
    my_goal_hook(g1, true).
    my_goal_hook(cc(X), dd(X)).
    % nicht angemeldet: gilt nur für lib selbst
    term_expansion(aa(_), bb).
    goal_expansion(g2, true).
    """)

    write(c, "main.pl", """
    :- use_module(lib).
    goal_expansion(g3, true).
    aa(1).
    cc(5).
    t1 :- g1.
    t3 :- g3.
    t2 :- g2.
    """)

    load(c, "main.pl")
    assert ask(c, "t1, t3.") == ["true"]
    assert ask(c, "aa(X).") == ["X = 1"]
    # nur als goal_expansion angemeldet: Klauseln bleiben
    assert ask(c, "cc(X).") == ["X = 5"]
    assert ask(c, "catch(t2, error(E, _), true).") == ["E = existence_error(procedure,g2/0)"]
  end

  test "clpz-Expansion bleibt neben einem eigenen goal_expansion/2", c do
    write(c, "main.pl", """
    :- use_module(library(clpz)).
    goal_expansion(foo, true).
    t(X) :- X #= 1 + 2, foo.
    """)

    load(c, "main.pl")
    assert ask(c, "t(X).") == ["X = 3"]
    # die Klausel ist von clpz übersetzt (kein #=/2-Aufruf mehr im Rumpf;
    # vorher ersetzte das eigene goal_expansion/2 den Hook von clpz)
    assert ask(c, "clause(t(_), (G, true)), G \\= (_ #= _).") |> length() == 1
  end
end
