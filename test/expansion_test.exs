defmodule PrologEx.ExpansionTest do
  use ExUnit.Case, async: false
  alias PrologEx.{Consult, Reader}

  setup do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    PrologEx.put_db(%{})
    {:ok, reader: r}
  end

  defp load(c, db \\ %{}, src), do: Consult.load(db, Reader.read_terms(c.reader, src))

  defp ask(c, db, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    # expand_goal/2: library(swi)
    db
    |> PrologEx.use_library("swi")
    |> PrologEx.query(g)
    |> Enum.take(10)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  describe "expand_term/2, expand_goal/2" do
    test "ohne Hooks", c do
      {db, []} = load(c, "x.")
      assert ask(c, db, "expand_term(foo(X), T)") == ["T = foo(X)"]

      assert ask(c, db, "expand_term((a --> [x]), T)") == ["T = (a(_A, _B):-_A=[x|_B])"]

      assert ask(c, db, "expand_goal((a, b ; c), G)") == ["G = (a, b;c)"]
      assert ask(c, db, "expand_goal(G0, G)") == ["G0 = G"]
    end

    test "mit Hooks: Steuerkonstrukte, Meta-Argumente, Bindungen", c do
      {db, []} =
        load(c, """
        goal_expansion(alt(X), neu(X)).
        goal_expansion(zweimal(G), (G, G)).
        goal_expansion(setze(X), true) :- X = 42.
        term_expansion(erzeuge(N), [p(N), q(N)]).
        """)

      assert ask(c, db, "expand_goal((a, alt(1) ; \\+ zweimal(alt(2))), G)") ==
               ["G = (a, neu(1);\\+ (neu(2), neu(2)))"]

      assert ask(c, db, "expand_goal(findall(X, alt(X), L), G)") == ["G = findall(X, neu(X), L)"]

      assert ask(c, db, "expand_goal(bagof(X, Y^alt(X-Y), L), G)") == [
               "G = bagof(X, Y^neu(X-Y), L)"
             ]

      # Qualifikation bleibt; der Hook aus user gilt auch für m
      assert ask(c, db, "expand_goal(m:alt(1), G)") == ["G = m:neu(1)"]
      assert ask(c, db, "expand_goal(setze(Z), G)") == ["G = true, Z = 42"]
      assert ask(c, db, "expand_term(erzeuge(3), T)") == ["T = [p(3), q(3)]"]
    end

    test "Schleife: resource_error", c do
      {db, []} = load(c, "goal_expansion(a, b).\ngoal_expansion(b, a).")

      [{:term, g, _}] = Reader.read_terms(c.reader, "expand_goal(a, G).")

      e =
        assert_raise PrologEx.Error, fn ->
          db |> PrologEx.use_library("swi") |> PrologEx.query(g) |> Enum.take(1)
        end

      assert Exception.message(e) =~ "resource_error(goal_expansion)"
    end
  end

  describe "beim Laden" do
    test "term_expansion: Liste, Wegfall, Direktiven, DCG, end_of_file", c do
      {db, []} =
        load(c, """
        term_expansion(erzeuge(N), [p(N), q(N)]).
        term_expansion(weg, []).
        term_expansion((:- sag(X)), (:- assertz(gesagt(X)))).
        term_expansion((A --> alt), (A --> [neu])).
        term_expansion(end_of_file, [ende(ja), end_of_file]).
        erzeuge(1).
        erzeuge(2).
        weg.
        :- sag(hallo).
        satz --> alt.
        """)

      assert ask(c, db, "p(X)") == ["X = 1", "X = 2"]
      assert ask(c, db, "q(2)") == ["true"]
      assert ask(c, db, "catch(weg, _, fail)") == []
      assert ask(c, db, "gesagt(X)") == ["X = hallo"]
      assert ask(c, db, "phrase(satz, [neu])") == ["true"]
      assert ask(c, db, "ende(X)") == ["X = ja"]
    end

    test "goal_expansion im Rumpf; Bindungen gelten auch im Kopf", c do
      {db, []} =
        load(c, """
        goal_expansion(alt(X), neu(X)).
        goal_expansion(setze(X), true) :- X = 42.
        neu(X) :- X > 0.
        r(X) :- alt(X).
        s(X) :- setze(X).
        t(L) :- findall(X, (member(X, [1, -1, 2]), alt(X)), L).
        """)

      assert ask(c, db, "r(5)") == ["true"]
      assert ask(c, db, "r(-5)") == []
      assert ask(c, db, "s(Y)") == ["Y = 42"]
      assert ask(c, db, "clause(r(X), B)") == ["B = neu(X)"]
      assert ask(c, db, "clause(s(X), B)") == ["B = true, X = 42"]
    end

    test "anonyme Variablen bleiben verschieden", c do
      {db, []} =
        load(c, """
        goal_expansion(alt(X), neu(X)).
        neu(_).
        u(_, _) :- alt(_).
        """)

      assert ask(c, db, "u(1, 2)") == ["true"]
    end

    test "ein Hook gilt ab der Klausel nach seiner Definition", c do
      {db, []} =
        load(c, """
        vorher :- alt.
        goal_expansion(alt, neu).
        nachher :- alt.
        alt.
        """)

      assert ask(c, db, "clause(vorher, B)") == ["B = alt"]
      assert ask(c, db, "clause(nachher, B)") == ["B = neu"]
    end

    test "goal_expansion in Direktiven", c do
      {db, []} =
        load(c, """
        goal_expansion(merke(X), assertz(gemerkt(X))).
        :- merke(1).
        """)

      assert ask(c, db, "gemerkt(X)") == ["X = 1"]
    end

    test "Hooks im Modul gelten nur dort", c do
      {db, []} =
        load(c, """
        :- module(m, [m_p/1]).
        goal_expansion(alt(X), neu(X)).
        neu(m).
        m_p(X) :- alt(X).
        """)

      assert ask(c, db, "m_p(X)") == ["X = m"]

      {db, []} = load(c, db, "alt(user).\nu_p(X) :- alt(X).")
      assert ask(c, db, "u_p(X)") == ["X = user"]
    end

    test "Fehler im Hook: Meldung, Term bleibt", c do
      {db, msgs} =
        load(c, """
        term_expansion(boom, _) :- X is foo + 1, X > 0.
        boom.
        """)

      assert [m] = msgs
      assert m =~ "term_expansion"
      assert m =~ "type_error(evaluable, foo/0)"
      assert ask(c, db, "boom") == ["true"]
    end

    test "Schleife in goal_expansion: Meldung", c do
      {_db, msgs} =
        load(c, """
        goal_expansion(a, b).
        goal_expansion(b, a).
        p :- a.
        """)

      assert Enum.any?(msgs, &(&1 =~ "resource_error(goal_expansion)"))
    end
  end

  describe "Toplevel" do
    import ExUnit.CaptureIO

    @tag :tmp_dir
    test "Anfragen werden expandiert, Bindungen erscheinen in der Antwort", c do
      file = Path.join(c.tmp_dir, "hooks.pl")

      File.write!(file, """
      goal_expansion(alt(X), neu(X)).
      goal_expansion(setze(X), true) :- X = 42.
      neu(X) :- X = neu.
      """)

      input = "['#{file}'].\nalt(Y).\nsetze(Z).\nfindall(A, alt(A), L).\n"
      out = capture_io(input, fn -> PrologEx.Toplevel.main(["-q"]) end)

      assert out =~ "Y = neu."
      assert out =~ "Z = 42."
      assert out =~ "L = [neu]"
      refute out =~ "_ExpandedQuery"
    end

    test "ohne Hook unverändert" do
      g = PrologEx.mk("foo", [])
      assert PrologEx.Builtins.Expansion.expand_query(%{}, g) == g
    end
  end
end
