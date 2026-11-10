defmodule PrologEx.VarNamesTest do
  # Variablen in der Ausgabe: _ und VM-weit eindeutige Kennung
  # (PrologEx.Vars) – dieselbe Variable überall gleich, verschiedene
  # verschieden, nie der Name aus dem Quelltext; Namen nur in den
  # Toplevel-Antworten, mit variable_names/1 und in listing/1
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Flags.reset()
    :ok
  end

  defp db(c, src) do
    libs = Enum.reduce(["lists", "swi"], %{}, &PrologEx.use_library(&2, &1))
    {db, []} = PrologEx.Consult.load(libs, Reader.read_terms(c.reader, src))
    PrologEx.put_db(db)
    db
  end

  defp goal(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")
    g
  end

  defp ask(c, q, src \\ "") do
    db = db(c, src)
    g = goal(c, q)

    db
    |> PrologEx.query(g)
    |> Enum.take(5)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp out(c, q, src \\ "") do
    db = db(c, src)
    g = goal(c, q)
    ExUnit.CaptureIO.capture_io(fn -> db |> PrologEx.query(g) |> Enum.take(1) end)
  end

  @v ~r/^_\d+$/

  test "write & Co.: _Kennung, gleich für dieselbe, verschieden für verschiedene", c do
    assert out(c, "write(f(X, Y, X))") =~ ~r/^f\((_\d+),(_\d+),\1\)$/
    refute out(c, "write(f(X, Y))") =~ ~r/^f\((_\d+),\1\)$/
    assert out(c, "write_canonical(_+_)") =~ ~r/^\+\((_\d+),(_\d+)\)$/
    refute out(c, "write_canonical(_+_)") =~ ~r/^\+\((_\d+),\1\)$/
    assert out(c, "write_canonical(B+B)") =~ ~r/^\+\((_\d+),\1\)$/
    assert out(c, "writeq([X|T])") =~ ~r/^\[(_\d+)\|(_\d+)\]$/
    assert out(c, "print(g(X))") =~ ~r/^g\(_\d+\)$/
    assert out(c, "write_term(f(X, Y), [variable_names(['Foo'=Y])])") =~ ~r/^f\(_\d+,Foo\)$/
  end

  test "über getrennte Aufrufe hinweg: dieselbe Variable derselbe Name", c do
    [a, b, a2] = out(c, "write(X), nl, write(Y), nl, write(X)") |> String.split("\n")
    assert a == a2 and a != b and a =~ @v and b =~ @v
    assert [a, b] = out(c, "format(\"~w ~w\", [X, Y])") |> String.split(" ")
    assert a != b
    assert [a, a] = out(c, "format(\"~w ~w\", [X, X])") |> String.split(" ")
    assert [a, b] = out(c, "write(X), write(' '), copy_term(X, Y), write(Y)") |> String.split(" ")
    assert a != b
  end

  test "kein Name aus dem Quelltext, auch nicht aus read/1", c do
    refute out(c, "write(f(Hallo, _Welt))") =~ "Hallo"
    refute out(c, "write(f(Hallo, _Welt))") =~ "Welt"
    assert out(c, "write(f(Hallo, _Welt))") =~ ~r/^f\(_\d+,_\d+\)$/
    assert out(c, "term_to_atom(T, 'foo(Abc, Abc, _D)'), write(T)") =~ ~r/^foo\((_\d+),\1,_\d+\)$/
    assert ask(c, "term_to_atom(T, 'foo(Abc, Abc, _D)')") == ["T = foo(_A,_A,_B)"]

    assert ask(c, "term_to_atom(T, 'foo(Abc, Abc, _D)'), term_variables(T, Vs)") ==
             ["T = foo(_A,_A,_B), Vs = [_A,_B]"]
  end

  test "attributierte und kopierte Variablen ebenso", c do
    assert out(c, "freeze(X, true), write(g(X, X))") =~ ~r/^g\((_\d+),\1\)$/
    assert out(c, "copy_term(f(X, Y, X), C), write(C)") =~ ~r/^f\((_\d+),(_\d+),\1\)$/
    assert out(c, "length(L, 2), write(L)") =~ ~r/^\[(_\d+),(_\d+)\]$/
    assert out(c, "findall(X-Y, member(X, [1, 2]), L), write(L)") =~ ~r/^\[1-(_\d+),2-(_\d+)\]$/
  end

  test "Kennungen sind eindeutig: Anfragen, Lesen, Kopien, Maschine", c do
    # dieselbe Anfrage zweimal gelesen: andere Variablen
    a = out(c, "write(X)")
    b = out(c, "write(X)")
    assert a != b
    # 5000 frische Variablen aus Klauseln (über den Block von 4096 hinaus),
    # dazu Kopien und gelesene: alle verschieden
    src = "mk(0, []) :- !.\nmk(N, [_|T]) :- N1 is N - 1, mk(N1, T)."

    text =
      out(c, "mk(5000, L), copy_term(L, L2), term_to_atom(T, 'f(A, B)'), write(x(L, L2, T))", src)

    names = Regex.scan(~r/_\d+/, text) |> List.flatten()
    assert length(names) == 10_002
    assert length(Enum.uniq(names)) == 10_002
  end

  test "PrologEx.Vars: Blöcke und Einzelkennungen überschneiden sich nie" do
    start = PrologEx.Vars.block(10)
    assert PrologEx.Vars.next() == start + 10
    assert PrologEx.Vars.block(3) == start + 11
    assert PrologEx.Vars.next() == start + 14
  end

  test "Klausel mit mehr Variablen als ein Block: keine Überschneidung", c do
    # 5000 frische Rumpfvariablen (Block: 4096); die nächste Einzelkennung
    # (copy_term) darf keine davon sein
    vars = Enum.map_join(1..5000, ",", fn _ -> "_" end)
    src = "big([#{vars}])."

    assert ask(
             c,
             "big(_L), copy_term(f(_), f(V)), \\+ (member(W, _L), W == V), length(_L, N)",
             src
           ) ==
             ["N = 5000"]

    assert ask(c, "big(_L), big(_M), append(_L, _M, _LM), sort(_LM, _S), length(_S, N)", src) ==
             ["N = 10000"]

    # Kopf (anonyme, Slots) und Rumpf zählen zum Bedarf
    args = Enum.map_join(1..3000, ",", &"X#{&1}")
    anon = Enum.map_join(1..3000, ",", fn _ -> "_" end)
    # (in Listen: max_arity ist 255)
    src = "big([#{vars}]).\nslots([#{args}], [#{args}]).\nbody(L) :- L = [#{anon}].\n"
    db = db(c, src)

    for q <- ["big(_)", "slots(_, _)", "body(_)", "big(_), slots(_, _), body(_)"] do
      assert {:ok, %{vars_in_block: true}} = PrologEx.first_with_stats(db, goal(c, q)), q
    end
  end

  test "Antworten: Namen der Anfrage, frische _A, _B, anonyme _ frisch", c do
    assert ask(c, "X = f(Y, _)") == ["X = f(Y,_A)"]
    assert ask(c, "X = f(_Y, Z), Z = g(_Y)") == ["X = f(_Y,g(_Y)), Z = g(_Y)"]
    assert ask(c, "length(L, 2), L = [A|_]") == ["L = [A,_A]"]
    assert ask(c, "X = Y, Y = Z") == ["X = Y, Y = Z"]
    assert ask(c, "X = f(_), Y = X") == ["X = f(_A), Y = f(_A)"]
    assert ask(c, "copy_term(f(X, Y, X), C)") == ["C = f(_A,_B,_A)"]
    assert ask(c, "freeze(X, true), Y = f(X)") == ["Y = f(X), freeze(X,true)"]

    assert ask(c, "catch(atom_length(f(X, X), _), error(E, _), true)") ==
             ["E = type_error(atom,f(_A,_A))"]
  end

  test "listing/1: Namen des Quelltexts, anonyme als _", c do
    src = "p(X, Y, [X|Z]) :- q(Y, Z), r(_, Y).\nq(_, _).\nr(_, _)."
    assert out(c, "listing(p/3)", src) == "p(X,Y,[X|Z]) :-\n    q(Y,Z),\n    r(_,Y).\n"
    assert out(c, "assertz(dyn(A, B, A)), listing(dyn/3)") =~ "dyn(A,B,A)."
  end

  test "read_term/2: variable_names, variables, singletons", c do
    db(c, "")
    g = goal(c, "read_term(user_input, T, [variable_names(V), variables(Vs), singletons(S)])")

    out =
      ExUnit.CaptureIO.capture_io([input: "foo(X, _Y, X, _).\n"], fn ->
        [a] = PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1)
        IO.write(PrologEx.format_answer(a, ["T", "V", "Vs", "S"]))
      end)

    # (Bindungen alphabetisch sortiert: S zuerst, daher _A für _Y)
    assert out == "S = ['_Y'=_A], T = foo(_B,_A,_B,_C), V = ['X'=_B,'_Y'=_A], Vs = [_B,_A,_C]"
  end

  test "Reader: Kennung {Name, Zahl}, Namen → Variable", c do
    [{:term, t, names}] = PrologEx.Reader.read_terms(c.reader, "f(X, _, X, _Y).")

    assert {:struct, "f", [{:var, {"X", x}} = vx, {:var, {"_", a}}, vx, {:var, {"_Y", y}} = vy]} =
             t

    assert names == %{"X" => vx, "_Y" => vy}
    assert x != a and a != y and x != y
  end
end
