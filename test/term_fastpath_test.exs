defmodule PrologEx.TermFastpathTest do
  # functor/3 und arg/3 laufen direkt in der Maschine (step/5); dieselben
  # Ergebnisse wie über den allgemeinen Weg – auch über call/N
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Flags.reset()
    on_exit(fn -> PrologEx.Flags.reset() end)
    PrologEx.put_db(%{})
    :ok
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    %{}
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, g), do: ask(c, "catch((#{g}), error(E, _), true)")

  test "functor/3 zerlegen: binden, vergleichen, strikt", c do
    for direct <- [true, false] do
      w = fn g -> if direct, do: g, else: "call(#{g})" end

      assert ask(c, w.("functor(f(a, b), N, A)")) == ["A = 2, N = f"]
      assert ask(c, w.("functor(f(a, b), f, 2)")) == ["true"]
      assert ask(c, w.("functor(f(a, b), g, _)")) == []
      assert ask(c, w.("functor(f(a, b), _, 3)")) == []
      # strikt wie unify/4: 2 und 2.0 sind verschieden
      assert ask(c, w.("functor(f(a, b), _, 2.0)")) == []
      assert ask(c, w.("functor([a], N, A)")) == ["A = 2, N = '.'"]
      assert ask(c, w.("functor(abc, N, A)")) == ["A = 0, N = abc"]
      assert ask(c, w.("functor(3.5, N, A)")) == ["A = 0, N = 3.5"]
      # dieselbe Variable für Name und Stelligkeit
      assert ask(c, w.("functor(f(a), X, X)")) == []
    end
  end

  test "functor/3 und arg/3: attributierte Variablen werden geweckt", c do
    assert ask(c, "freeze(N, W = geweckt), functor(f(a), N, _)") == ["N = f, W = geweckt"]
    assert ask(c, "freeze(A, W = geweckt), functor(f(a), _, A)") == ["A = 1, W = geweckt"]
    assert ask(c, "dif(N, f), functor(f(a), N, _)") == []
    assert ask(c, "dif(A, 1), functor(f(a), _, A)") == []
    assert ask(c, "freeze(X, W = geweckt), arg(1, f(a), X)") == ["W = geweckt, X = a"]
    assert ask(c, "dif(X, a), arg(1, f(a), X)") == []
  end

  test "functor/3 bauen und Fehler", c do
    assert ask(c, "functor(T, f, 2)") == ["T = f(_A,_B)"]
    assert ask(c, "functor(T, abc, 0)") == ["T = abc"]
    assert err(c, "functor(_, _, 1)") == ["E = instantiation_error"]
    assert err(c, "functor(_, f, a)") == ["E = type_error(integer,a)"]
    assert err(c, "functor(_, f, -1)") == ["E = domain_error(not_less_than_zero,-1)"]
    assert err(c, "functor(_, f(x), 1)") == ["E = type_error(atomic,f(x))"]
    assert err(c, "call(functor, _, _, 1)") == ["E = instantiation_error"]
  end

  test "=../2: beide Richtungen, Fehler – direkt und über call/N", c do
    for direct <- [true, false] do
      w = fn g -> if direct, do: g, else: "call(#{g})" end
      assert ask(c, w.("f(a, B) =.. L")) == ["L = [f,a,B]"]
      assert ask(c, w.("T =.. [g, 1, x]")) == ["T = g(1,x)"]
      assert ask(c, w.("T =.. [abc]")) == ["T = abc"]
      assert ask(c, w.("[1] =.. L")) == ["L = ['.',1,[]]"]
      assert ask(c, w.("f(a) =.. [f, b]")) == []
    end

    assert err(c, "_ =.. _") == ["E = instantiation_error"]
    assert err(c, "_ =.. [f|_]") == ["E = instantiation_error"]
    assert err(c, "_ =.. [_, a]") == ["E = instantiation_error"]
    assert err(c, "_ =.. []") == ["E = domain_error(non_empty_list,[])"]
    assert err(c, "_ =.. [f(x), a]") == ["E = type_error(atom,f(x))"]
    assert err(c, "_ =.. [f(x)]") == ["E = type_error(atomic,f(x))"]
    assert err(c, "_ =.. foo") == ["E = type_error(list,foo)"]
    assert err(c, "call(=.., _, foo)") == ["E = type_error(list,foo)"]
  end

  test "copy_term/2: frische Variablen, geteilt bleibt geteilt, ground geteilt", c do
    for direct <- [true, false] do
      w = fn g -> if direct, do: g, else: "call((#{g}))" end
      assert ask(c, w.("copy_term(f(X, Y, X), C)")) == ["C = f(_A,_B,_A)"]
      assert ask(c, w.("copy_term(f(X, Y, X), f(a, B, D))")) == ["D = a"]
      assert ask(c, w.("copy_term(f(a, b), C)")) == ["C = f(a,b)"]
      assert ask(c, w.("copy_term(abc, C)")) == ["C = abc"]
      assert ask(c, w.("copy_term(f(X), g(_))")) == []
      # das Original bleibt unberührt
      assert ask(c, w.("copy_term(X, C), C = 1, var(X)")) == ["C = 1"]
      # C im Original: die Kopie enthält es nicht
      assert ask(c, w.("copy_term(f(C), C)")) == ["C = f(_A)"]
    end
  end

  test "copy_term/2 an attributierte Variable: wecken nur, wenn ein Term kommt", c do
    # Kopie ist eine Variable: sie wird an C gebunden, nicht C an sie – kein Wecken
    assert ask(c, "freeze(C, W = geweckt), copy_term(_, C), var(W)") |> hd() =~ "freeze(C,"
    # Kopie ist ein Term: C wird gebunden und geweckt
    assert ask(c, "freeze(C, W = geweckt), copy_term(f(a), C)") == ["C = f(a), W = geweckt"]
    assert ask(c, "dif(C, f(a)), copy_term(f(a), C)") == []
    assert ask(c, "dif(C, f(a)), copy_term(f(b), C)") == ["C = f(b)"]
  end

  test "kopierte Variablen schreiben sich als gültige Variablennamen", c do
    out = ExUnit.CaptureIO.capture_io(fn -> ask(c, "copy_term(f(X, X), f(Y, _)), write(Y)") end)
    assert out =~ ~r/^_[A-Z]\w*$/

    out =
      ExUnit.CaptureIO.capture_io(fn -> ask(c, "copy_term(X, Y), writeq(f(Y)), nl, print(Y)") end)

    assert out =~ ~r/^f\(_[A-Z]\w*\)\n_[A-Z]\w*$/
  end

  test "arg/3: Lösung, Grenzen, Fehler, Occurs-Check", c do
    assert ask(c, "arg(1, f(a, b, c), X)") == ["X = a"]
    assert ask(c, "arg(3, f(a, b, c), X)") == ["X = c"]
    assert ask(c, "arg(4, f(a, b, c), X)") == []
    assert ask(c, "arg(0, f(a, b, c), X)") == []
    assert ask(c, "arg(2, f(a, B, c), x)") == ["B = x"]
    assert ask(c, "arg(2, [a|T], X)") == ["T = X"]
    # höchstens eine Lösung, kein Choice Point
    assert ask(c, "arg(1, f(a), X), X == a") == ["X = a"]
    assert err(c, "arg(_, f(a), _)") == ["E = instantiation_error"]
    assert err(c, "arg(1, _, _)") == ["E = instantiation_error"]
    assert err(c, "arg(1, abc, _)") == ["E = type_error(compound,abc)"]
    assert err(c, "arg(-1, f(a), _)") == ["E = domain_error(not_less_than_zero,-1)"]
    assert err(c, "arg(a, f(a), _)") == ["E = type_error(integer,a)"]
    assert err(c, "call(arg, 1, abc, _)") == ["E = type_error(compound,abc)"]

    # X mit X selbst: gelingt; X mit einem Term, der X enthält: Occurs-Check
    assert ask(c, "set_prolog_flag(occurs_check, true), arg(1, f(X), X)") == ["true"]
    assert ask(c, "set_prolog_flag(occurs_check, true), arg(1, f(g(X)), X)") == []

    assert err(c, "set_prolog_flag(occurs_check, error), arg(1, f(g(X)), X)") |> hd() =~
             "occurs_check"
  end
end
