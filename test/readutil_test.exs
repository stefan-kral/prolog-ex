defmodule PrologEx.ReadutilTest do
  # library(readutil) (Elixir) und library(readutil_pl) (Prolog) wie
  # SWI-Prologs library(readutil); statt *_to_string: *_to_chars
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag :tmp_dir

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    File.write!(Path.join(c.tmp_dir, "t.txt"), "abc\r\ndéf\n\nlast")
    File.write!(Path.join(c.tmp_dir, "t.pl"), "f(X, Y).\ng(1).\n")
    File.write!(Path.join(c.tmp_dir, "leer.txt"), "")
    File.write!(Path.join(c.tmp_dir, "bad.txt"), <<97, 255, 10>>)
    :ok
  end

  defp db(c, lib) do
    PrologEx.put_db(%{})

    for l <- [lib, "lists", "concurrent", "yall", "iso_ext"] do
      [{:term, g, _}] = Reader.read_terms(c.reader, "use_module(library(#{l})).")
      [_] = PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1)
    end

    PrologEx.current_db()
  end

  defp ask(c, db, q) do
    q = String.replace(q, "DIR", c.tmp_dir)
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    try do
      db
      |> PrologEx.query(g)
      |> Enum.take(2)
      |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
    rescue
      e in PrologEx.Error -> {:error, PrologEx.Writer.format(e.term, quoted: true)}
    end
  end

  @cases [
    {"open('DIR/t.txt', read, S), read_line_to_codes(S, A), read_line_to_codes(S, B), " <>
       "read_line_to_codes(S, C), read_line_to_codes(S, D), read_line_to_codes(S, E), close(S)",
     "A = [97,98,99], B = [100,233,102], C = [], D = [108,97,115,116], E = end_of_file"},
    {"open('DIR/t.txt', read, S), read_line_to_codes(S, A, T1), read_line_to_codes(S, B, []), " <>
       "read_line_to_codes(S, C, x), read_line_to_codes(S, D, Y), read_line_to_codes(S, E, Z), close(S)",
     "A = [97,98,99,13,10|T1], B = [100,233,102,10], C = [10|x], D = [108,97,115,116], E = [], Y = [], Z = []"},
    {"open('DIR/t.txt', read, S), read_line_to_chars(S, A), read_line_to_chars(S, B), " <>
       "read_line_to_chars(S, C), read_line_to_chars(S, D), read_line_to_chars(S, E), close(S)",
     ~S(A = "abc", B = "déf", C = [], D = "last", E = end_of_file)},
    {"open('DIR/t.txt', read, S), read_line_to_codes(S, _), read_stream_to_codes(S, R), " <>
       "read_stream_to_codes(S, R2, t), close(S)",
     "R = [100,233,102,10,10,108,97,115,116], R2 = t"},
    {"open('DIR/leer.txt', read, S), read_line_to_codes(S, A), read_line_to_chars(S, B), " <>
       "read_line_to_codes(S, C, T), close(S)",
     "A = end_of_file, B = end_of_file, C = [], T = []"},
    {"read_file_to_codes('DIR/t.txt', C, [tail(x)])",
     "C = [97,98,99,13,10,100,233,102,10,10,108,97,115,116|x]"},
    {"read_file_to_chars('DIR/t.txt', C, [encoding(utf8)])", ~S(C = "abc\r\ndéf\n\nlast")},
    {"read_file_to_terms('DIR/t.pl', Ts, [])", "Ts = [f(_A,_B),g(1)]"},
    {"read_file_to_terms('DIR/t.pl', Ts, [tail([z])])", "Ts = [f(_A,_B),g(1),z]"},
    # Ausgabeoptionen gelten je Term: bei mehreren Termen scheitert es (SWI)
    {"read_file_to_terms('DIR/t.pl', Ts, [variable_names(V)])", nil},
    {"catch(read_file_to_codes('DIR/nie', C, []), error(E, _), true)",
     "E = existence_error(source_sink,'DIR/nie')"},
    {"catch(read_file_to_codes('DIR/t.txt', C, foo), error(E, _), true)",
     "E = type_error(list,foo)"},
    {"catch(read_file_to_codes('DIR/t.txt', C, _), error(E, _), true)",
     "E = instantiation_error"},
    {"catch(read_line_to_codes(nix, C), error(E, _), true)", "E = existence_error(stream,nix)"},
    # lesen hinter dem Ende: eof_action(error)
    {"open('DIR/leer.txt', read, S, [eof_action(error)]), read_line_to_codes(S, A), " <>
       "catch(read_line_to_codes(S, B), error(E, _), true), close(S)",
     "A = end_of_file, E = permission_error(input,past_end_of_stream,'$stream'(_))"}
  ]

  test "readutil (Elixir) und readutil_pl (Prolog): dieselben Antworten, wie SWI", c do
    ex = db(c, "readutil")
    pl = db(c, "readutil_pl")

    for {q, exp} <- @cases do
      strip = fn as ->
        Enum.map(as, &String.replace(&1, ~r/'\$stream'\(\d+\)/, "'$stream'(_)"))
      end

      a = strip.(ask(c, ex, q))
      b = strip.(ask(c, pl, q))
      assert a == b, "#{q}\n Elixir: #{inspect(a)}\n Prolog: #{inspect(b)}"

      case exp do
        nil ->
          assert a == [], q

        exp ->
          assert [ans] = a, q
          exp = String.replace(exp, "DIR", c.tmp_dir)

          assert String.replace(ans, ", S = '$stream'(_)", "") == exp, q
      end
    end
  end

  test "ungültiges UTF-8: representation_error(character)", c do
    for lib <- ~w(readutil readutil_pl) do
      d = db(c, lib)

      assert [a] =
               ask(c, d, "catch(read_file_to_codes('DIR/bad.txt', C, []), error(E, _), true)")

      assert a =~ "E = representation_error(character)", lib
    end
  end

  # im Kind von library(concurrent): eigene Dateien und Streams
  test "in Arbeitern von library(concurrent)", c do
    for lib <- ~w(readutil readutil_pl) do
      d = db(c, lib)

      assert ask(
               c,
               d,
               "concurrent_maplist([F, N]>>(read_file_to_codes(F, Cs, []), length(Cs, N)), " <>
                 "['DIR/t.txt', 'DIR/t.pl'], Ns)"
             ) == ["Ns = [14,15]"],
             lib

      assert ask(
               c,
               d,
               "concurrent_maplist([F, L]>>setup_call_cleanup(open(F, read, S), " <>
                 "read_line_to_chars(S, L), close(S)), ['DIR/t.txt', 'DIR/t.pl'], Ls)"
             ) == [~S{Ls = ["abc","f(X, Y)."]}],
             lib
    end
  end
end
