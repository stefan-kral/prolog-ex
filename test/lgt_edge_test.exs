defmodule PrologEx.LgtEdgeTest do
  # Grenzfälle aus Logtalks Testsammlung (tests/prolog), in denen PrologEx
  # abwich – meist auch von Scryer: call_nth/2 mit 0 und negativ, setof/3
  # mit gebundener Ergebnisvariablen, keysort/2 mit Nicht-Paaren im
  # Ergebnis, findall/4 mit falschem Rest, atom_concat(A, A, Z)
  # deterministisch, open/4 mit wiederholter Option, set_stream_position/2
  # auf Schreibströmen, popcount/1 negativ, Flag version_data; dazu
  # zyklische Antworten ohne Occurs-Check (der Toplevel hing)
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
    :ok
  end

  @src ":- use_module(library(iso_ext)).\n:- use_module(library(lists)).\na(1). a(2).\n"

  defp ask(c, q, src \\ @src) do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))
    PrologEx.put_db(db)
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    db
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, goal), do: ask(c, "catch((#{goal}), error(E, _), true)")

  test "call_nth/2: die 0-te Lösung gibt es nicht, negativ ist ein Fehler", c do
    assert ask(c, "call_nth(a(_), 0)") == []
    assert err(c, "call_nth(a(_), -1)") == ["E = domain_error(not_less_than_zero,-1)"]
    assert ask(c, "call_nth(a(X), 2)") == ["X = 2"]
  end

  test "setof/3: Ergebnisvariable über eine freie Variable gebunden – scheitert", c do
    assert ask(c, "setof(t, (L = 2 ; L = 1), L)") == []
    assert ask(c, "setof(X, member(X, [2, 1, 2]), S)") == ["S = [1,2]"]
  end

  test "keysort/2: Elemente des Ergebnisses sind Variablen oder Paare", c do
    assert err(c, "keysort([], [1/a])") == ["E = type_error(pair,1/a)"]
    assert err(c, "keysort([a-1], [_, x])") == ["E = type_error(pair,x)"]
    assert ask(c, "keysort([b-1, a-2], [_|_])") == ["true"]
  end

  test "findall/4: der Rest ist eine (Teil-)Liste", c do
    assert err(c, "findall(X, X = 1, _, [_|1])") == ["E = type_error(list,[_A|1])"]
    assert err(c, "findall(X, X = 1, _, 12)") == ["E = type_error(list,12)"]
    assert ask(c, "findall(X, member(X, [1, 2]), L, [z])") == ["L = [1,2,z]"]
  end

  test "atom_concat(A, A, Z): nur die Mitte, ohne Choice Point", c do
    assert ask(c, "atom_concat(A, A, aaaa)") == ["A = aa"]
    assert ask(c, "atom_concat(A, A, aaa)") == []
    assert ask(c, "atom_concat(A, A, abab)") == ["A = ab"]
    assert ask(c, "atom_concat(A, A, abba)") == []
    assert ask(c, "atom_concat(A, A, '')") == ["A = ''"]
    assert ask(c, "atom_concat(A, A, 'äöäö')") == ["A = 'äö'"]
    # deterministisch: keine weitere Lösung, kein Choice Point
    assert ask(c, "call_cleanup(atom_concat(A, A, aaaa), Det = true)") == ["A = aa, Det = true"]
    # verschiedene Variablen: alle Zerlegungen
    assert ask(c, "findall(A-B, atom_concat(A, B, ab), L)") == ["L = [''-ab,a-b,ab-'']"]
  end

  test "open/4: eine wiederholte Option – die letzte gilt", c do
    f = Path.join(System.tmp_dir!(), "pex_lgt_#{System.unique_integer([:positive])}.txt")

    assert ask(
             c,
             "open('#{f}', write, S, [type(binary), type(text)]), stream_property(S, type(T)), close(S)"
           )
           |> hd() =~ "T = text"

    assert ask(
             c,
             "open('#{f}', write, S, [type(text), type(binary)]), stream_property(S, type(T)), close(S)"
           )
           |> hd() =~ "T = binary"

    File.rm(f)
  end

  test "set_stream_position/2 auf einem Schreibstrom mit reposition(true)", c do
    f = Path.join(System.tmp_dir!(), "pex_lgt_#{System.unique_integer([:positive])}.txt")

    assert ask(
             c,
             "open('#{f}', write, S, [reposition(true)]), stream_property(S, position(P)), " <>
               "write(S, 't1.\\n'), write(S, 't2.\\n'), set_stream_position(S, P), " <>
               "write(S, 't4.\\n'), close(S)"
           ) != []

    assert File.read!(f) == "t4.\nt2.\n"

    # append: nicht positionierbar
    assert err(
             c,
             "open('#{f}', append, S, [reposition(true)]), stream_property(S, position(P)), " <>
               "set_stream_position(S, P)"
           )
           |> hd() =~ "permission_error(reposition,stream,"

    File.rm(f)
  end

  test "popcount/1 negativ: domain_error", c do
    assert err(c, "X is popcount(-1)") == ["E = domain_error(not_less_than_zero,-1)"]
    assert ask(c, "X is popcount(7)") == ["X = 3"]
  end

  test "Flag version_data", c do
    assert ask(c, "current_prolog_flag(version_data, V)") == [
             "V = prolog_ex(0,1,0,[])"
           ]
  end

  test "atomic_concat/3 (library(iso_ext))", c do
    assert ask(c, "atomic_concat(a, 42, A)") == ["A = a42"]
    assert ask(c, "atomic_concat(42, a, A)") == ["A = '42a'"]
    assert ask(c, "atomic_concat('', '', A)") == ["A = ''"]
    assert ask(c, "atomic_concat(a, 1.5, A)") == ["A = 'a1.5'"]
    assert ask(c, "atomic_concat([], b, A)") == ["A = '[]b'"]
    assert ask(c, "atomic_concat(a, b, ab)") == ["true"]
    assert ask(c, "atomic_concat(a, b, ba)") == []
    assert err(c, "atomic_concat(_, bar, _)") == ["E = instantiation_error"]
    assert err(c, "atomic_concat(foo, _, _)") == ["E = instantiation_error"]
    assert err(c, "atomic_concat(a(1), bar, _)") == ["E = type_error(atomic,a(1))"]
    assert err(c, "atomic_concat(foo, a(1), _)") == ["E = type_error(atomic,a(1))"]
    assert err(c, "atomic_concat(foo, bar, a(1))") == ["E = type_error(atom,a(1))"]
    # deterministisch
    assert ask(c, "call_cleanup(atomic_concat(a, b, X), Det = true)") == ["Det = true, X = ab"]
    # nur mit library(iso_ext)
    assert ask(c, "catch(atomic_concat(a, b, _), error(E, _), true)", "") ==
             ["E = existence_error(procedure,atomic_concat/3)"]
  end

  test "evaluable_property/2 (library(iso_ext))", c do
    assert ask(c, "findall(P, evaluable_property(abs(_), P), Ps)") ==
             ["Ps = [built_in,static,template(abs(number),number)]"]

    assert ask(c, "findall(P, evaluable_property(pi, P), Ps)") ==
             ["Ps = [built_in,static,template(pi,float)]"]

    for {e, t} <- [
          {"_ // _", "template(integer//integer,integer)"},
          {"\\ _", "template(\\integer,integer)"},
          {"sin(_)", "template(sin(number),float)"},
          {"round(_)", "template(round(float),integer)"},
          {"float(_)", "template(float(number),float)"},
          {"_ / _", "template(number/number,number)"},
          {"atan2(_, _)", "template(atan2(number,number),float)"},
          {"max_tagged_integer", "template(max_tagged_integer,integer)"}
        ] do
      assert ask(c, "evaluable_property(#{e}, template(T, R)), Tp = template(T, R)")
             |> hd() =~ "Tp = #{t}",
             e
    end

    assert ask(c, "evaluable_property(abs(_), dynamic)") == []
    assert ask(c, "evaluable_property(abs(_), foreign)") == []
    assert ask(c, "evaluable_property(foo(_), built_in)") == []
    assert ask(c, "evaluable_property(abs(_, _), built_in)") == []
    assert err(c, "evaluable_property(_, _)") == ["E = instantiation_error"]
    assert err(c, "evaluable_property(1, _)") == ["E = type_error(callable,1)"]
    assert err(c, "evaluable_property(abs(_), 1)") == ["E = domain_error(evaluable_property,1)"]

    assert err(c, "evaluable_property(foo(_), foobar)") ==
             ["E = domain_error(evaluable_property,foobar)"]
  end

  test "evaluable_property/2: jede auswertbare Funktion hat eine Signatur, die zutrifft", c do
    # Stichprobe über is/2: Ergebnistyp passt zum Template
    for e <- [
          "abs(-3)",
          "abs(-3.0)",
          "sqrt(4)",
          "7 // 2",
          "pi",
          "truncate(2.5)"
        ] do
      assert ask(
               c,
               "X is #{e}, evaluable_property(#{e}, template(_, R)), " <>
                 "( R == number -> number(X) ; R == integer -> integer(X) ; float(X) )"
             ) != [],
             e
    end
  end

  test "upcase_atom/2, downcase_atom/2 (library(swi), wie SWI)", c do
    src = ":- use_module(library(swi)).\n"
    assert ask(c, "upcase_atom(abc, X)", src) == ["X = 'ABC'"]
    assert ask(c, "downcase_atom('ÄBC', X)", src) == ["X = 'äbc'"]
    # Zeichen für Zeichen: ß bleibt (wie SWI)
    assert ask(c, "upcase_atom('Grüße', X)", src) == ["X = 'GRÜßE'"]
    assert ask(c, "upcase_atom(12, X)", src) == ["X = '12'"]
    assert ask(c, "upcase_atom(a, 'A')", src) == ["true"]

    assert ask(c, "catch(upcase_atom(_, _), error(E, _), true)", src) == [
             "E = instantiation_error"
           ]

    assert ask(c, "catch(upcase_atom(f(x), _), error(E, _), true)", src) == [
             "E = type_error(atomic,f(x))"
           ]

    assert ask(c, "catch(downcase_atom(a, f(x)), error(E, _), true)", src) == [
             "E = type_error(atom,f(x))"
           ]

    # ohne Import nicht sichtbar
    assert ask(c, "catch(upcase_atom(a, _), error(E, _), true)", "") ==
             ["E = existence_error(procedure,upcase_atom/2)"]
  end

  test "phrase//2, phrase//3 (library(dcgs), wie Scryer)", c do
    src = ":- use_module(library(dcgs)).\nab(X) --> [X], [b].\nxy(X, Y) --> [X, Y].\n"
    assert ask(c, "phrase(phrase(seq, Xs), [1, 2])", src) == ["Xs = [1,2]"]
    assert ask(c, "phrase(([x], phrase(ab, Y)), [x, 1, b])", src) == ["Y = 1"]
    assert ask(c, "phrase(phrase(xy, A, B), [1, 2])", src) == ["A = 1, B = 2"]
    assert ask(c, "phrase(phrase(seq, [1]), S0, S)", src) == ["S0 = [1|S]"]

    assert ask(c, "catch(phrase(phrase(_, x), [], []), error(E, _), true)", src) ==
             ["E = instantiation_error"]

    assert ask(c, "catch(phrase(phrase(1, x), [], []), error(E, _), true)", src) ==
             ["E = type_error(callable,1)"]

    # ohne library(dcgs): wie die Norm
    assert ask(c, "catch(phrase(phrase(phrase, []), L), error(E, _), true)", "") ==
             ["E = existence_error(procedure,phrase/4)"]
  end

  test "zyklische Antworten (ohne Occurs-Check): wie SWI, keine Endlosschleife", c do
    assert ask(c, "X = f(X)") == ["X = f(X)"]
    assert ask(c, "X = f(Y), Y = g(X)") == ["X = f(g(X)), Y = g(X)"]
    assert ask(c, "X = f(Y, Y), Y = h(Y)") == ["X = f(Y,Y), Y = h(Y)"]
    # über eine Kette auf eine Zyklusvariable: eine Stufe ausgeschrieben
    assert ask(c, "X = Y, Y = f(Y)") == ["X = f(X), Y = f(X)"]
    # Zyklus über eine nicht gezeigte Variable: als Gleichung
    assert ask(c, "X = [a|_T], _T = [b|_T]") == ["X = [a|_T], _T=[b|_T]"]
    assert ask(c, "X = [a|T], T = [b|T]") == ["T = [b|T], X = [a|T]"]
    # Occurs-Check an: gar kein Zyklus
    assert ask(c, "set_prolog_flag(occurs_check, true), X = f(X)") == []
    # gewöhnliche Antworten unverändert, Restziele bleiben
    assert ask(c, "X = f(A), freeze(A, true)") == ["X = f(A), freeze(A,true)"]
  end
end
