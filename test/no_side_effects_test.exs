defmodule PrologEx.NoSideEffectsTest do
  # call_with_no_side_effects/1 (library(iso_ext)): jede Wirkung ist vorher
  # ein Fehler; super-strikt
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    Process.delete(:prolog_ex_memo)
    Process.delete(:prolog_ex_tabling)
    :ok
  end

  @src """
  :- use_module(library(iso_ext)).
  :- use_module(library(lists)).
  :- use_module(library(between)).
  :- use_module(library(swi)).
  :- use_module(library(random)).
  :- use_module(library(gensym)).
  :- use_module(library(blackboard)).
  :- use_module(library(mutables)).
  :- use_module(library(memo)).
  :- use_module(library(tabling)).
  :- use_module(library(files), [make_directory/1, file_exists/1]).

  :- use_module(library(time), [call_with_time_limit/2]).
  :- dynamic(f/1).
  f(0).
  :- memo m/1.
  m(1).
  :- table tb/1.
  tb(1).
  mk(0, []) :- !.
  mk(N, [N|T]) :- N1 is N - 1, mk(N1, T).
  nse(G) :- call_with_no_side_effects(G).
  % Kategorie der Wirkung, die G im Bereich versucht
  cat(G, K) :- catch((nse(G), K = none), error(permission_error(perform, side_effect, _), context(_, K)), true).
  """

  defp load(src) do
    f = Path.join(System.tmp_dir!(), "px_nse_#{System.unique_integer([:positive])}.pl")
    File.write!(f, src)
    PrologEx.put_db(%{})

    try do
      err =
        ExUnit.CaptureIO.capture_io(:stderr, fn -> {:ok, _} = PrologEx.Consult.load_file(f) end)

      assert err == ""
      PrologEx.current_db()
    after
      File.rm(f)
    end
  end

  defp ask(c, q, src \\ @src) do
    db = load(src)
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    db
    |> PrologEx.query(g)
    |> Enum.take(5)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  test "reine Ziele wie call/1, auch nichtdeterministisch", c do
    assert ask(c, "findall(X, nse(member(X, [a, b])), L)") == [~S|L = "ab"|]
    assert ask(c, "nse(fail)") == []
    assert ask(c, "catch(nse(throw(x)), x, true)") == ["true"]

    assert ask(c, "nse((X is 2 + 3, atom_length(abc, N), msort([b, a], S)))") ==
             [~S|N = 3, S = "ab", X = 5|]
  end

  test "Wirkungen je Kategorie, vorher ein Fehler", c do
    for {g, k} <- [
          {"assertz(f(1))", "database"},
          {"retract(f(0))", "database"},
          {"abolish(f/1)", "database"},
          {"op(700, xfx, ===>)", "state"},
          {"set_prolog_flag(double_quotes, atom)", "state"},
          {"b_setval(k, 1)", "state"},
          {"nb_setval(k, 1)", "state"},
          {"bb_put(k, 1)", "state"},
          {"gensym(a, _)", "state"},
          {"write(x)", "io"},
          {"nl", "io"},
          {"print(x)", "io"},
          {"format(\"~w\", [x])", "io"},
          {"format(atom(_), \"~w\", [x])", "io"},
          {"with_output_to(atom(_), true)", "io"},
          {"get_char(_)", "io"},
          {"peek_char(_)", "io"},
          {"read_term(_, [])", "io"},
          {"open('/tmp/px_nse_x', write, _)", "io"},
          {"open('/etc/hostname', read, _)", "io"},
          {"flush_output", "io"},
          {"time(true)", "io"},
          {"random(_)", "random"},
          {"random_between(1, 6, _)", "random"},
          {"delete_file('/tmp/px_nse_none')", "external"},
          {"make_directory('/tmp/px_nse_dir')", "external"},
          {"halt", "external"},
          # (memo ist hier ein Präfixoperator)
          {"m(_)", "(memo)"},
          {"tb(_)", "tabling"},
          {"abolish_all_tables", "tabling"},
          {"abolish_memo", "(memo)"}
        ] do
      assert ask(c, "cat((#{g}), K)") == ["K = #{k}"], g
    end

    # die Wirkung ist nicht geschehen
    assert ask(c, "catch(nse(assertz(f(1))), _, true), findall(X, f(X), L)") == ["L = [0]"]
    refute File.exists?("/tmp/px_nse_x")
    refute File.exists?("/tmp/px_nse_dir")
  end

  test "der Fehlerterm", c do
    assert ask(c, "catch(nse(assertz(f(1))), E, true)") ==
             [
               "E = error(permission_error(perform,side_effect,assertz(f(1))),context(assertz/1,database))"
             ]
  end

  test "Lesen ohne Änderung ist erlaubt", c do
    for g <- [
          "f(_)",
          "clause(f(X), true)",
          "current_op(_, _, is)",
          "current_prolog_flag(bounded, _)",
          "get_time(_)",
          "statistics(runtime, _)",
          "catch(nb_getval(k, _), _, true)",
          "bb_get(k, _) ; true",
          "file_exists(\"/etc/hostname\")",
          "term_to_atom(f(X), _)",
          "copy_term(f(X), _)",
          "predicate_property(f(_), dynamic)",
          "create_mutable(1, M), update_mutable(2, M), get_mutable(2, M)",
          "freeze(V, true), V = 1",
          "dif(A, b), A = a",
          "call_with_time_limit(5, true)",
          "call_with_inference_limit(true, 100, _)",
          "call_with_depth_limit(true, 10, _)",
          "call_with_memory_limit(true, 1000000)",
          "findall(Y, member(Y, [1]), _)",
          "\\+ fail",
          "forall(member(Y, [1]), Y > 0)",
          "setup_call_cleanup(true, true, true)"
        ] do
      assert ask(c, "cat((#{g}), K)") |> hd() =~ "K = none", g
    end
  end

  test "Unter-Maschinen (findall, \\+, forall, aggregate) teilen den Bereich", c do
    for g <- [
          "findall(_, assertz(f(1)), _)",
          "\\+ assertz(f(1))",
          "forall(true, assertz(f(1)))",
          "findall(X, (member(X, [1, 2]), X > 1, write(X)), _)",
          "once(write(x))",
          "ignore(write(x))",
          "call((true, write(x)))",
          "catch(write(x), foo, true)"
        ] do
      assert ask(c, "cat((#{g}), K)") |> hd() =~ ~r/K = (database|io)/, g
    end
  end

  test "der Bereich endet mit dem Aufruf und gilt beim Wiedereintritt", c do
    # danach ist alles erlaubt, auch nach mehreren Lösungen
    assert ask(c, "nse(member(X, [1, 2])), assertz(f(X)), X == 2, findall(Y, f(Y), L)") ==
             ["L = [0,1,2], X = 2"]

    # Backtracking in den Bereich hinein: dort wieder gesperrt
    assert ask(
             c,
             "catch((nse((member(X, [1, 2]), (X == 2 -> assertz(f(X)) ; true))), X == 2), error(E, _), true)"
           ) == ["E = permission_error(perform,side_effect,assertz(f(2)))"]

    # nach Scheitern und Ausnahme frei
    assert ask(
             c,
             "( nse(fail) ; true ), assertz(f(1)), catch(nse(throw(x)), x, true), assertz(f(2))"
           ) ==
             ["true"]

    # geschachtelt
    assert ask(c, "nse(nse(true)), assertz(f(1))") == ["true"]
    assert ask(c, "cat(nse((nse(true), write(x))), K)") == ["K = io"]
  end

  test "eine gefangene Ausnahme im Bereich: die Wirkung ist trotzdem nicht geschehen", c do
    assert ask(
             c,
             "nse(catch(assertz(f(1)), error(permission_error(perform, side_effect, _), _), true)), findall(X, f(X), L)"
           ) == ["L = [0]"]
  end

  test "im Bereich registrierter Code läuft im Bereich", c do
    # Cleanup, ausgelöst erst durch einen Cut draußen
    assert ask(
             c,
             "catch((nse(setup_call_cleanup(true, member(_, [1, 2]), assertz(f(c)))), !), error(E, _), true)"
           ) == ["E = permission_error(perform,side_effect,assertz(f(c)))"]

    # freeze/when, geweckt erst draußen
    assert ask(c, "catch((nse(freeze(V, assertz(f(z)))), V = 1), error(E, _), true)") ==
             ["E = permission_error(perform,side_effect,assertz(f(z)))"]

    assert ask(c, "catch((nse(when(nonvar(V), write(z))), V = 1), error(E, _), true)") ==
             ["E = permission_error(perform,side_effect,write(z))"]

    # außerhalb registriert, im Bereich geweckt: auch gesperrt
    assert ask(c, "freeze(V, assertz(f(z))), catch(nse(V = 1), error(E, _), true)") ==
             ["E = permission_error(perform,side_effect,assertz(f(z))), freeze(V,assertz(f(z)))"]

    # außerhalb registriert, draußen geweckt: frei
    assert ask(c, "freeze(V, assertz(f(z))), nse(true), V = 1, f(z)") == ["V = 1"]
  end

  test "der Bereich übersteht die Kompaktierung der Substitution", c do
    # viele Bindungen: die Substitution wird unterwegs kompaktiert
    assert ask(c, "cat((mk(300000, _), assertz(f(1))), K)") == ["K = database"]
  end

  test "nur nach use_module(library(iso_ext))", c do
    assert ask(c, "catch(call_with_no_side_effects(true), error(E, _), true)", "") ==
             ["E = existence_error(procedure,call_with_no_side_effects/1)"]
  end
end
