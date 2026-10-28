defmodule PrologEx.FastRWTest do
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
    PrologEx.Flags.reset()

    PrologEx.put_db(
      Enum.reduce(
        ["lists", "fastrw", "iso_ext", "swi"],
        %{},
        &PrologEx.use_library(&2, &1, "user")
      )
    )

    {:ok, f: Path.join(c.tmp_dir, "t.bin")}
  end

  defp ask(c, q, n \\ 3) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    try do
      PrologEx.current_db()
      |> PrologEx.query(g)
      |> Enum.take(n)
      |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
    rescue
      e in PrologEx.Error -> {:error, Exception.message(e)}
    end
  end

  test "forall/2", c do
    assert ask(c, "forall(member(X, [1, 2, 3]), X > 0)") == ["true"]
    assert ask(c, "forall(member(X, [1, 2, 3]), X > 1)") == []
    assert ask(c, "forall(fail, fail)") == ["true"]
    # bindet nichts nach außen
    assert ask(c, "forall(member(X, [1, 2]), Y = X)") == ["true"]
    # im Kontextmodul gerufen
    assert ask(c, "assertz(q(1)), assertz(q(2)), forall(q(X), integer(X))") == ["true"]
    assert ask(c, "forall(_, true)") == {:error, "instantiation_error"}
  end

  test "exists_file/1, exists_directory/1, delete_file/1 (wie SWI)", c do
    assert ask(c, "exists_file('#{c.f}')") == []
    File.write!(c.f, "x")
    assert ask(c, "exists_file('#{c.f}')") == ["true"]
    assert ask(c, "exists_file(\"#{c.f}\")") == ["true"]
    assert ask(c, "exists_directory('#{c.tmp_dir}'), \\+ exists_file('#{c.tmp_dir}')") == ["true"]
    assert ask(c, "delete_file('#{c.f}'), \\+ exists_file('#{c.f}')") == ["true"]
    refute File.exists?(c.f)

    assert ask(c, "catch(delete_file('#{c.f}'), error(E, _), true)") ==
             ["E = existence_error(file, '#{c.f}')"]

    assert ask(c, "catch(exists_file(_), error(E, _), true)") == ["E = instantiation_error"]
    assert ask(c, "catch(exists_file(1), error(E, _), true)") == ["E = type_error(atom, 1)"]
  end

  test "once/1 (ISO), ignore/1", c do
    assert ask(c, "once(member(X, [1, 2]))") == ["X = 1"]
    assert ask(c, "once(fail)") == []
    assert ask(c, "once((X = 1 ; X = 2)), Y = 3") == ["X = 1, Y = 3"]
    # Cut in once/1 ist lokal
    assert ask(c, "(once(!), X = 1 ; X = 2)") == ["X = 1", "X = 2"]
    assert ask(c, "catch(once(_), error(E, _), true)") == ["E = instantiation_error"]
    assert ask(c, "ignore(fail)") == ["true"]
    assert ask(c, "ignore(member(X, [1, 2]))") == ["X = 1"]
    assert ask(c, "ignore(member(X, [1, 2])), X > 1") == []
  end

  test "fast_write/2, fast_read/2: Terme bleiben gleich", c do
    t =
      "f(X, Y, X, [a, \"str\", 1.5, -7, 100000000000000000000000], 'Ä b', g(h([])), {x}, -(1), [_|T], T)"

    assert ask(
             c,
             "T0 = #{t}, open('#{c.f}', write, S, [type(binary)]), fast_write(S, T0), fast_write(S, zwei), close(S), " <>
               "open('#{c.f}', read, R, [type(binary)]), fast_read(R, T1), fast_read(R, T2), fast_read(R, T3), close(R), " <>
               "T0 =@= T1, T2 == zwei, T3 == end_of_file"
           )
           |> length() == 1

    # gleiche Variablen bleiben gleich, verschiedene verschieden, frisch
    assert ask(
             c,
             "fast_term_serialized(g(A, A, B), Bs), fast_term_serialized(T, Bs), T = g(P, Q, R), P == Q, P \\== R, P \\== A"
           )
           |> length() == 1
  end

  test "fast_read am Ende immer wieder end_of_file", c do
    assert ask(
             c,
             "open('#{c.f}', write, S, [type(binary)]), fast_write(S, a), close(S), " <>
               "open('#{c.f}', read, R, [type(binary)]), fast_read(R, A), fast_read(R, B), fast_read(R, C), close(R)"
           )
           |> hd() =~ "A = a, B = end_of_file, C = end_of_file"
  end

  test "SICStus: fast_write/1, fast_read/1 auf den aktuellen Streams; library(fastrw)", c do
    assert ask(
             c,
             "use_module(library(fastrw)), open('#{c.f}', write, S, [type(binary)]), set_output(S), fast_write(p(1)), " <>
               "set_output(user_output), close(S), open('#{c.f}', read, R, [type(binary)]), set_input(R), fast_read(T), " <>
               "set_input(user_input), close(R)"
           )
           |> hd() =~ "T = p(1)"
  end

  test "Fehler", c do
    # Textstreams: wie put_byte/get_byte
    assert ask(
             c,
             "open('#{c.f}', write, S), catch(fast_write(S, x), error(E, _), true), close(S)"
           )
           |> hd() =~ "permission_error(output, text_stream"

    assert ask(c, "catch(fast_term_serialized(T, [1, 2, 3]), error(E, _), true)") ==
             ["E = syntax_error(fast_term)"]

    # andere Formatversion
    assert ask(
             c,
             "catch(fast_term_serialized(T, [80, 88, 84, 9, 0, 0, 0, 0]), error(E, _), true)"
           ) ==
             ["E = syntax_error(fast_term_version)"]

    File.write!(c.f, <<"PXT", 9, 0, 0, 0, 0>>)

    assert ask(
             c,
             "open('#{c.f}', read, R, [type(binary)]), catch(fast_read(R, T), error(E, _), true), close(R)"
           )
           |> hd() =~ "E = syntax_error(fast_term_version)"

    File.write!(c.f, "kaputt..")

    assert ask(
             c,
             "open('#{c.f}', read, R, [type(binary)]), catch(fast_read(R, T), error(E, _), true), close(R)"
           )
           |> hd() =~ "E = syntax_error(fast_term)"

    assert ask(c, "catch(fast_term_serialized(T, [a]), error(E, _), true)") |> hd() =~
             "type_error"

    assert ask(c, "fast_term_serialized(T, B), B = [P|_]") |> hd() =~ "P = 80"
  end

  test "nur Prolog-Terme werden gelesen (keine beliebigen BEAM-Daten)", c do
    # ein gültiger Datensatz, der aber eine Elixir-Map statt eines Terms enthält
    etf = :erlang.term_to_binary(%{bad: 1})
    bytes = :erlang.binary_to_list(<<"PXT", 1, byte_size(etf)::32, etf::binary>>)
    q = "catch(fast_term_serialized(T, #{inspect(bytes)}), error(E, _), true)"
    assert ask(c, q) == ["E = syntax_error(fast_term)"]

    # und mit einem unbekannten Erlang-Atom: :safe lehnt ab
    etf = <<131, 100, 0, 20>> <> "atom_gibt_es_nicht_1"
    bytes = :erlang.binary_to_list(<<"PXT", 1, byte_size(etf)::32, etf::binary>>)
    q = "catch(fast_term_serialized(T, #{inspect(bytes)}), error(E, _), true)"
    assert ask(c, q) == ["E = syntax_error(fast_term)"]
    # das Atom wurde nicht angelegt (Atomtabelle der BEAM bleibt sauber)
    assert_raise ArgumentError, fn -> String.to_existing_atom("atom_gibt_es_nicht_1") end
  end

  test "Dateinamen als Zeichenliste auch fuer open/3,4 (Pfad ohne Umlaut: siehe README)", c do
    assert [_] = ask(c, "open(\"#{c.f}\", write, S), write(S, hallo), close(S)")
    assert File.read!(c.f) == "hallo"
  end

  test "schneller als writeq/read (grob)", c do
    n = 20_000

    {us_fast, _} =
      :timer.tc(fn ->
        ask(
          c,
          "numlist(1, #{n}, L), findall(p(I, f(I, [a, b])), member(I, L), Ts), open('#{c.f}', write, S, [type(binary)]), " <>
            "forall(member(T, Ts), fast_write(S, T)), close(S)"
        )
      end)

    {us_text, _} =
      :timer.tc(fn ->
        ask(
          c,
          "numlist(1, #{n}, L), findall(p(I, f(I, [a, b])), member(I, L), Ts), open('#{c.f}.pl', write, S), " <>
            "forall(member(T, Ts), (writeq(S, T), write(S, '.'), nl(S))), close(S)"
        )
      end)

    assert us_fast < us_text
  end
end
