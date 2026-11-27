defmodule PrologEx.IsDirectivesTest do
  # :- Spec is det. wie SICStus (library(is_directives)): erkannt auch ohne
  # use_module, abgefragt mit current_is_directive/3,6; Aufrufmuster als
  # Hinweise auf die Modi des JIT, Abweichungen in jit_listing
  use ExUnit.Case, async: false
  alias PrologEx.{Reader, TableCase}

  @moduletag :tmp_dir

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.put_db(%{})
    :ok
  end

  defp file(c, name, text) do
    path = Path.join(c.tmp_dir, name)
    File.write!(path, text)
    path
  end

  defp q(c, query) do
    {out, r} = TableCase.run(c.reader, PrologEx.current_db(), query)
    {out, r}
  end

  # (current_is_directive/3,6 aus library(is_directives), wie in SICStus)
  defp load(c, path) do
    {_, {:answers, [_]}} = q(c, "use_module(library(is_directives)), consult('#{path}')")
    :ok
  end

  @a """
  :- foo/2 is det.
  :- bar(+, ?) is semidet.
  :- bar(-, ?) is nondet.
  :- user:parent_of(+Parent, -Child) is nondet.
  :- dolist(+, -, det) is det.
  :- X is 1 + 2, assertz(arith(X)).
  foo(X, hello(X)).
  """

  test "erkannt ohne use_module, in Reihenfolge, Arithmetik bleibt", c do
    load(c, file(c, "a.pl", @a))

    assert {_, {:answers, ["X = 3"]}} = q(c, "arith(X)")

    assert {_, {:answers, [l]}} =
             q(c, "findall(A-S, current_is_directive(_, user, A, S, _, _), L)")

    assert l ==
             "L = [det-foo/2,semidet-bar(+,?),nondet-bar(-,?),nondet-parent_of(+_A,-_B),det-dolist(+,-,det)]"

    # Skel mit anonymen Argumenten, Spec und Direktive teilen Variablen
    assert {_, {:answers, [x]}} =
             q(
               c,
               "current_is_directive(parent_of(P, Q), M, A, S, D, C), var(P), var(Q), S = parent_of(+V, _), D = (_:parent_of(+W, _) is _), V == W"
             )

    assert x =~ "M = user"
    assert x =~ "C = user"

    assert {_, {:answers, ["A = semidet, S = bar(+,?)", "A = nondet, S = bar(-,?)"]}} =
             q(c, "current_is_directive(bar(_, _), A, S)")

    assert {_, {:answers, []}} = q(c, "current_is_directive(other:bar(_, _), _, _)")
    assert {_, {:answers, [_]}} = q(c, "current_is_directive(user:foo(_, _), det, foo/2)")
  end

  test "erneutes Laden ersetzt an derselben Stelle", c do
    a = file(c, "a.pl", ":- p/1 is det.\np(1).\n")
    b = file(c, "b.pl", ":- q/1 is semidet.\nq(1).\n")
    load(c, a)
    load(c, b)
    File.write!(a, ":- p(+) is semidet.\n:- p(-) is nondet.\np(1).\n")
    load(c, a)

    assert {_, {:answers, ["L = [semidet-p(+),nondet-p(-),semidet-q/1]"]}} =
             q(c, "findall(A-S, current_is_directive(_, _, A, S, _, _), L)")
  end

  test "Aufrufmuster als Modi für den JIT; Abweichungen in jit_listing", c do
    load(
      c,
      file(c, "j.pl", """
      :- ex(+, +, -) is det.
      ex(I, p(J, K), t(e(I, J), e(I, K))) :- !.
      ex(I, t(J, K), e(e(I, J), K)).
      ex0(I, p(J, K), t(e(I, J), e(I, K))) :- !.
      ex0(I, t(J, K), e(e(I, J), K)).
      :- cnt/2 is det.
      cnt([X|_], X).
      cnt([_|T], X) :- cnt(T, X).
      :- m3(+, -) is semidet.
      m3(X, Y) :- write(X), Y = 1.
      :- k(-, +) is det.
      k(X, Y) :- Y > 0, X = Y.
      """)
    )

    {out, _} = q(c, "jit_listing")
    # ohne Deklaration die erste übersetzbare Belegung, mit ihr die gemeinte
    assert out =~ ~r"% ex/3 +\S+ +ex\(\+any, \+any, -any\)\n"
    assert out =~ ~r"% ex0/3 +\S+ +ex0\(-any, -any, \+any\)\n"
    # deklariert det, aber nicht nachweislich: nicht übersetzt
    assert out =~
             ~r"% cnt/2 +nein +Klauseln 1 und 2 schließen sich nicht nachweislich aus\n%   ↳ deklariert cnt/2 is det: nicht übersetzt"

    assert out =~ ~r"%   ↳ deklariert m3\(\+,-\) is semidet: nicht übersetzt"
    # passt: kein Vermerk
    refute out =~ "deklariert k("

    assert {_, {:answers, ["R = t(e(a,b),e(a,c))"]}} = q(c, "ex(a, p(b, c), R)")
  end
end
