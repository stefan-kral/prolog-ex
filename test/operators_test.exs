defmodule PrologEx.OperatorsTest do
  # op/3 und current_op/3; jeder Test mit eigenem Reader (Operatoren sind
  # global im Reader)
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.Reader

  @moduletag :gprolog

  setup do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    PrologEx.put_db(%{})
    on_exit(fn -> Process.exit(r, :kill) end)
    {:ok, reader: r}
  end

  defp ask(c, text) do
    case Reader.read_terms(c.reader, text) do
      [{:term, g, _}] ->
        PrologEx.current_db()
        |> PrologEx.query(g)
        |> Enum.take(10)
        |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))

      [{:error, msg}] ->
        {:syntax_error, msg}
    end
  end

  defp err(c, text), do: Exception.message(assert_raise(PrologEx.Error, fn -> ask(c, text) end))

  test "op/3 wirkt ab dem nächsten gelesenen Term", c do
    assert {:syntax_error, _} = ask(c, "X = (a ===> b).")
    assert ask(c, "op(700, xfx, ===>).") == ["true"]
    assert ask(c, "X = (a ===> b), X =.. L.") == ["L = [===>, a, b], X = (a===>b)"]
    # Liste von Operatoren, Assoziativität
    assert ask(c, "op(200, xfy, [aa, bb]).") == ["true"]
    assert ask(c, "X = (1 aa 2 bb 3).") == ["X = 1 aa 2 bb 3"]
    assert ask(c, "op(200, yfx, cc).") == ["true"]
    assert ask(c, "Y = (1 cc 2 cc 3), Y =.. L.") == ["L = [cc, 1 cc 2, 3], Y = 1 cc 2 cc 3"]
    # Präfix, Postfix
    assert ask(c, "op(900, fy, nicht), op(100, xf, fakultaet).") == ["true"]

    assert ask(c, "X = (nicht nicht a), Y = (3 fakultaet).") ==
             ["X = (nicht nicht a), Y = 3 fakultaet"]
  end

  test "Priorität 0 entfernt einen Operator", c do
    assert ask(c, "op(700, xfx, ===>), op(0, xfx, ===>).") == ["true"]
    assert {:syntax_error, _} = ask(c, "X = (a ===> b).")
    assert ask(c, "current_op(P, T, ===>).") == []
  end

  test "Fehler wie ISO", c do
    assert err(c, "op(_, xfx, foo).") =~ "instantiation_error"
    assert err(c, "op(700, _, foo).") =~ "instantiation_error"
    assert err(c, "op(700, xfx, _).") =~ "instantiation_error"
    assert err(c, "op(700, xfx, [a|_]).") =~ "instantiation_error"
    assert err(c, "op(700, xfx, [a, _]).") =~ "instantiation_error"
    assert err(c, "op(a, xfx, foo).") =~ "type_error(integer, a)"
    assert err(c, "op(1201, xfx, foo).") =~ "domain_error(operator_priority, 1201)"
    assert err(c, "op(-1, xfx, foo).") =~ "domain_error(operator_priority, -1)"
    assert err(c, "op(700, 1, foo).") =~ "type_error(atom, 1)"
    assert err(c, "op(700, yfy, foo).") =~ "domain_error(operator_specifier, yfy)"
    assert err(c, "op(700, xfx, f(x)).") =~ "type_error(list, f(x))"
    assert err(c, "op(700, xfx, [a, 1]).") =~ "type_error(atom, 1)"
    assert err(c, "op(1000, xfy, ',').") =~ "permission_error(modify, operator, ',')"
    assert err(c, "op(700, xfx, '|').") =~ "permission_error(create, operator, '|')"
    assert ask(c, "op(1100, xfy, '|').") == ["true"]
    assert err(c, "op(700, xfx, []).") =~ "permission_error(create, operator, [])"
    assert err(c, "op(700, xfx, {}).") =~ "permission_error(create, operator, {})"
    # Infix und Postfix mit demselben Namen
    assert ask(c, "op(200, xf, yy).") == ["true"]
    assert err(c, "op(200, xfx, yy).") =~ "permission_error(create, operator, yy)"
    # Zahlen jenseits von gprologs Bereich
    assert err(c, "op(100000000000000000000, xfx, foo).") =~ "domain_error(operator_priority"
    assert err(c, "op(700, xfx, [a, 100000000000000000000]).") =~ "type_error(atom, 1000"
    # fangbar als error(Formal, _)
    assert ask(c, "catch(op(1201, xfx, foo), error(E, _), true).") ==
             ["E = domain_error(operator_priority, 1201)"]
  end

  test "current_op/3", c do
    assert ask(c, "current_op(P, T, mod).") == ["P = 400, T = yfx"]
    assert ask(c, "current_op(1200, xfx, O).") |> Enum.sort() == ["O = (-->)", "O = (:-)"]

    assert ask(c, "current_op(P, T, ':-').") |> Enum.sort() == [
             "P = 1200, T = fx",
             "P = 1200, T = xfx"
           ]

    assert ask(c, "current_op(700, xfx, =).") == ["true"]
    assert ask(c, "current_op(701, xfx, =).") == []

    assert ask(c, "op(200, xfy, [aa, bb]).") == ["true"]

    assert ask(c, "findall(O, current_op(200, xfy, O), L), msort(L, S), S == [^, aa, bb].")
           |> length() == 1
  end

  test "current_op/3: Fehler", c do
    assert err(c, "current_op(1201, T, O).") =~ "domain_error(operator_priority, 1201)"
    assert err(c, "current_op(a, T, O).") =~ "domain_error(operator_priority, a)"
    assert err(c, "current_op(P, foo, O).") =~ "domain_error(operator_specifier, foo)"
    assert err(c, "current_op(P, 1, O).") =~ "domain_error(operator_specifier, 1)"
    assert err(c, "current_op(P, T, 1).") =~ "type_error(atom, 1)"
  end

  @tag :tmp_dir
  test "op-Direktive in einer Datei: wirkt beim Lesen, Fehler werden gemeldet", c do
    file = Path.join(c.tmp_dir, "ops.pl")

    File.write!(file, """
    :- op(700, xfx, ===>).
    :- op(1201, xfx, kaputt).
    regel(a ===> b).
    """)

    out = capture_io(:stderr, fn -> assert ask(c, "consult('#{file}').") == ["true"] end)
    assert out =~ "domain_error(operator_priority, 1201)"
    assert ask(c, "regel(X).") == ["X = (a===>b)"]
  end
end
