defmodule PrologEx.IsoChecksTest do
  # Fehlerprüfungen nach ISO, gefunden mit Logtalks Konformitätstests
  # (conformance/run.exs)
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag :tmp_dir

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Stream.reset()
    PrologEx.put_db(%{})
    {:ok, f: Path.join(c.tmp_dir, "x.txt")}
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, goal), do: ask(c, "catch(#{goal}, error(E, _), true)")

  test "write_term/open: bekannte Option mit offenem Wert gibt instantiation_error", c do
    assert err(c, "write_term(a, [quoted(_)])") == ["E = instantiation_error"]
    assert err(c, "write_term(a, [ignore_ops(_)])") == ["E = instantiation_error"]
    assert err(c, "write_term(a, [numbervars(_)])") == ["E = instantiation_error"]

    assert err(c, "write_term(a, [quoted(maybe)])") == [
             "E = domain_error(write_option, quoted(maybe))"
           ]

    File.write!(c.f, "x")
    assert err(c, "open('#{c.f}', read, _, [type(_)])") == ["E = instantiation_error"]
    assert err(c, "open('#{c.f}', read, _, [eof_action(_)])") == ["E = instantiation_error"]
  end

  test "arg/3: offenes N ist ein Fehler (ISO 8.5.2.3)", c do
    assert err(c, "arg(_, foo(a, b), a)") == ["E = instantiation_error"]
    assert ask(c, "arg(2, foo(a, b), X)") == ["X = b"]
  end

  test "findall/3, term_variables/2: Ergebnis muss eine (Teil-)Liste sein", c do
    assert err(c, "findall(X, X = 1, [_|1])") == ["E = type_error(list, [_A|1])"]
    assert err(c, "findall(X, X = 1, foo)") == ["E = type_error(list, foo)"]
    assert ask(c, "findall(X, (X = 1 ; X = 2), [A|B])") == ["A = 1, B = [2]"]
    assert err(c, "term_variables(t, [_, _|a])") == ["E = type_error(list, [_A,_B|a])"]
  end

  test "current_input/output mit geschlossenem Stream: domain_error(stream, S)", c do
    File.write!(c.f, "x")

    assert ask(c, "open('#{c.f}', read, S), close(S), catch(current_input(S), error(E, _), true)")
           |> hd() =~ "E = domain_error(stream, '$stream'("

    assert ask(
             c,
             "open('#{c.f}', write, S), close(S), catch(current_output(S), error(E, _), true)"
           )
           |> hd() =~ "E = domain_error(stream, '$stream'("
  end

  test "retract/1 auf ein eingebautes Prädikat: permission_error", c do
    assert err(c, "retract((atom(X) :- X == '[]'))") ==
             ["E = permission_error(modify, static_procedure, atom/1)"]

    assert ask(c, "retract(gibts_nicht(1))") == []
  end

  test "clause/2: Variablen an Zielstelle als call(V) (ISO 7.6.1)", c do
    assert ask(c, "assertz((legs(A, 7) :- A, A)), clause(legs(C, 7), B)") ==
             ["B = (call(C), call(C))"]

    assert ask(c, "assertz((p(X) :- (X -> true ; fail))), clause(p(Y), B)") ==
             ["B = (call(Y)->true;fail)"]
  end
end
