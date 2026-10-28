defmodule PrologEx.IOTest do
  # Streams und Ein-/Ausgabe (ISO 8.11–8.14)
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.Reader

  @moduletag :tmp_dir

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Stream.reset()
    PrologEx.put_db(Enum.reduce(["lists", "swi"], %{}, &PrologEx.use_library(&2, &1, "user")))
    # im eigenen Verzeichnis arbeiten, danach zurück (sonst laufen alle
    # folgenden Tests in einem anderen Arbeitsverzeichnis)
    old = File.cwd!()
    File.cd!(c.tmp_dir)
    on_exit(fn -> File.cd!(old) end)
    :ok
  end

  defp ask(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp ok(c, text), do: assert(length(ask(c, text)) == 1, text)

  defp err(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)

    e =
      assert_raise(PrologEx.Error, fn ->
        PrologEx.current_db() |> PrologEx.query(g) |> Enum.take(1)
      end)

    Exception.message(e)
  end

  describe "open/close und Streams (8.11)" do
    test "schreiben, lesen, Standardstreams", c do
      ok(c, "open('a.txt', write, S), write(S, hallo), nl(S), close(S).")
      assert File.read!("a.txt") == "hallo\n"
      ok(c, "open('a.txt', append, S), writeq(S, 'x y'), close(S).")
      assert File.read!("a.txt") == "hallo\n'x y'"

      assert ask(c, "current_input(I), current_output(O).") ==
               ["I = '$stream'(0), O = '$stream'(1)"]

      # Aliase
      ok(c, "open('a.txt', read, _, [alias(ein)]), get_char(ein, h), close(ein).")
      assert err(c, "get_char(ein, _).") =~ "existence_error(stream,ein)"
    end

    test "set_output/set_input leiten write/read um", c do
      ok(
        c,
        "open('o.pl', write, S), set_output(S), write(f(x)), write('.'), nl, set_output(user_output), close(S)."
      )

      assert File.read!("o.pl") == "f(x).\n"

      assert ask(
               c,
               "open('o.pl', read, S), set_input(S), read(T), set_input(user_input), close(S)."
             )
             |> hd() =~
               "T = f(x)"

      # nach close des aktuellen Ausgabestroms gilt wieder user_output
      ok(
        c,
        "open('p.txt', write, S), set_output(S), close(S), current_output(O), O == '$stream'(1)."
      )
    end

    test "stream_property/2", c do
      File.write!("a.txt", "ab")

      [answer] =
        ask(
          c,
          "open('a.txt', read, S, [alias(q)]), findall(P, stream_property(S, P), Ps), close(S)."
        )

      for p <- [
            "mode(read)",
            "input",
            "alias(q)",
            "position('$stream_position'(0,1,0,0))",
            "end_of_stream(not)",
            "eof_action(eof_code)",
            "reposition(true)",
            "type(text)"
          ],
          do: assert(answer =~ p, p)

      assert answer =~ "file_name('"
      ok(c, "stream_property(S, alias(user_error)), S == '$stream'(2).")
      # ISO: hier kein Alias, nur ein Stream-Term
      assert err(c, "stream_property(user_output, _).") =~ "domain_error(stream,user_output)"
    end

    test "Fehler", c do
      assert err(c, "open(_, read, _).") =~ "instantiation_error"
      assert err(c, "open(f, _, _).") =~ "instantiation_error"
      assert err(c, "open(f, read, _, [type(text)|_]).") =~ "instantiation_error"
      assert err(c, "open(f(x), read, _).") =~ "domain_error(source_sink,f(x))"
      assert err(c, "open(f, 1, _).") =~ "type_error(atom,1)"
      assert err(c, "open(f, rw, _).") =~ "domain_error(io_mode,rw)"
      assert err(c, "open(f, read, s).") =~ "uninstantiation_error(s)"
      assert err(c, "open(f, read, _, bogus).") =~ "type_error(list,bogus)"
      assert err(c, "open(f, read, _, [bogus]).") =~ "domain_error(stream_option,bogus)"
      assert err(c, "open(nix, read, _).") =~ "existence_error(source_sink,nix)"
      ok(c, "open('a.txt',write,_,[alias(dop)]).")

      assert err(c, "open('b.txt', write, _, [alias(dop)]).") =~
               "permission_error(open,source_sink,alias(dop))"

      assert err(c, "close(_).") =~ "instantiation_error"
      assert err(c, "close(f(x)).") =~ "domain_error(stream_or_alias,f(x))"
      assert err(c, "close(user_input, [bogus]).") =~ "domain_error(close_option,bogus)"
      assert err(c, "close('$stream'(99)).") =~ "existence_error(stream,'$stream'(99))"
      assert err(c, "current_output(foo).") =~ "domain_error(stream,foo)"
      assert err(c, "set_input(user_output).") =~ "permission_error(input,stream,user_output)"
      assert err(c, "set_output(user_input).") =~ "permission_error(output,stream,user_input)"
      assert err(c, "stream_property(foo, _).") =~ "domain_error(stream,foo)"
      assert err(c, "stream_property(_, bogus).") =~ "domain_error(stream_property,bogus)"
    end
  end

  describe "Zeichen und Bytes (8.12, 8.13)" do
    test "get/peek/put_char und _code, Positionen", c do
      File.write!("z.txt", "aä\nb")

      assert ask(
               c,
               "open('z.txt', read, S), get_char(S, A), peek_char(S, B), get_char(S, B2), get_code(S, C), peek_code(S, D), line_count(S, L), line_position(S, LP), character_count(S, N), close(S)."
             ) ==
               [
                 "A = a, B = 'ä', B2 = 'ä', C = 10, D = 98, L = 2, LP = 0, N = 3, S = '$stream'(3)"
               ]

      ok(
        c,
        "open('w.txt', write, S), put_char(S, x), put_code(S, 8364), put_char(S, '\\n'), close(S)."
      )

      assert File.read!("w.txt") == "x€\n"
    end

    test "Dateiende: end_of_file / -1, dann eof_action", c do
      File.write!("e.txt", "")

      assert ask(
               c,
               "open('e.txt', read, S), peek_char(S, A), get_char(S, B), get_char(S, C), stream_property(S, end_of_stream(E)), close(S)."
             ) ==
               ["A = end_of_file, B = end_of_file, C = end_of_file, E = past, S = '$stream'(3)"]

      assert ask(c, "open('e.txt', read, S), get_code(S, A), close(S).") |> hd() =~ "A = -1"

      assert err(
               c,
               "open('e.txt',read,S,[eof_action(error)]), get_char(S,_), get_char(S,_)."
             ) =~
               "permission_error(input,past_end_of_stream"

      ok(c, "open('e.txt', read, S), at_end_of_stream(S), close(S).")

      # peek am Ende setzt den Stream nicht auf past: erst das zweite get
      # scheitert bei eof_action(error)
      assert ask(
               c,
               "open('e.txt', read, S, [eof_action(error)]), peek_char(S, A), peek_code(S, B), get_char(S, C)."
             )
             |> hd() =~
               "A = end_of_file, B = -1, C = end_of_file"
    end

    test "Bytes", c do
      ok(
        c,
        "open('b.bin', write, S, [type(binary)]), put_byte(S, 0), put_byte(S, 255), close(S)."
      )

      assert File.read!("b.bin") == <<0, 255>>

      assert ask(
               c,
               "open('b.bin', read, S, [type(binary)]), get_byte(S, A), peek_byte(S, B), get_byte(S, B2), get_byte(S, C), close(S)."
             ) ==
               ["A = 0, B = 255, B2 = 255, C = -1, S = '$stream'(4)"]
    end

    test "Fehler", c do
      File.write!("z.txt", "a")
      ok(c, "open('b.bin', write, S, [type(binary)]), close(S).")

      assert err(c, "open('b.bin', read, S, [type(binary)]), get_char(S, _).") =~
               "permission_error(input,binary_stream"

      assert err(c, "open('z.txt', read, S), get_byte(S, _).") =~
               "permission_error(input,text_stream"

      assert err(c, "put_byte(user_output, 1).") =~
               "permission_error(output,text_stream,user_output)"

      assert err(c, "get_char(user_output, _).") =~ "permission_error(input,stream,user_output)"
      assert err(c, "put_char(user_input, a).") =~ "permission_error(output,stream,user_input)"
      assert err(c, "open('z.txt', read, S), get_char(S, 1).") =~ "type_error(in_character,1)"
      assert err(c, "open('z.txt', read, S), get_char(S, ab).") =~ "type_error(in_character,ab)"
      assert err(c, "open('z.txt', read, S), get_code(S, a).") =~ "type_error(integer,a)"

      assert err(c, "open('z.txt', read, S), get_code(S, -2).") =~
               "representation_error(in_character_code)"

      assert err(c, "open('b.bin', read, S, [type(binary)]), get_byte(S, 256).") =~
               "type_error(in_byte,256)"

      assert err(c, "put_char(_).") =~ "instantiation_error"
      assert err(c, "put_char(ab).") =~ "type_error(character,ab)"
      assert err(c, "put_code(a).") =~ "type_error(integer,a)"
      assert err(c, "put_code(-1).") =~ "representation_error(character_code)"

      assert err(c, "open('b.bin', write, S, [type(binary)]), put_byte(S, 256).") =~
               "type_error(byte,256)"

      assert err(c, "get_char(_, _).") =~ "instantiation_error"
      assert err(c, "get_char(foo, _).") =~ "existence_error(stream,foo)"
    end

    test "Ausgabe auf user_output landet auf stdout", c do
      assert capture_io(fn ->
               ok(c, "put_char(a), put_code(0'b), nl(user_output), write(user_output, c).")
             end) ==
               "ab\nc"
    end
  end

  describe "Terme (8.14)" do
    test "read/2, read_term/3 mit Optionen, mehrere Terme, Kommentare", c do
      File.write!("t.pl", """
      foo(X, 'a b', [1,2], X, _Y, Z).   % Kommentar.
      /* Block . */ bar(0'., "x.y", 'q.r', 1.5, a=..b).
      :- op(700, xfx, ~~~).
      """)

      assert ask(
               c,
               "open('t.pl', read, S), read_term(S, T, [variable_names(V), singletons(Sg), variables(Vs)]), read(S, T2), read(S, T3), read(S, T4), close(S)."
             ) ==
               [
                 "S = '$stream'(3), Sg = ['_Y'=_A,'Z'=_B], T = foo(_C,'a b',[1,2],_C,_A,_B), " <>
                   "T2 = bar(46,\"x.y\",'q.r',1.5,a=..b), T3 = (:-op(700,xfx,~~~)), " <>
                   "T4 = end_of_file, V = ['X'=_C,'_Y'=_A,'Z'=_B], Vs = [_C,_A,_B]"
               ]

      # gelesene Direktiven werden nicht ausgeführt
      assert {:error, _} = hd(Reader.read_terms(c.reader, "X = (a ~~~ b)."))
    end

    test "Term-Ende: nur ein einzelner Punkt", c do
      File.write!("d.pl", "a = .. .\nb.\n")

      assert ask(c, "open('d.pl', read, S), read(S, X), read(S, Y), close(S).") |> hd() =~
               "X = (a= ..), Y = b"
    end

    test "Syntaxfehler: danach geht es mit dem nächsten Term weiter", c do
      File.write!("s.pl", "x(1). y(]. z.\n")

      [answer] =
        ask(
          c,
          "open('s.pl', read, S), read(S, A), catch(read(S, _), error(E, _), true), read(S, C), close(S)."
        )

      assert answer =~ "A = x(1)"
      assert answer =~ "C = z"
      assert answer =~ "E = syntax_error("

      File.write!("u.pl", "x(1). y(")

      assert err(c, "open('u.pl', read, S), read(S, _), read(S, _).") =~
               "syntax_error(end_of_file_in_term)"
    end

    test "Position merken und zurücksetzen", c do
      File.write!("p.pl", "a.\nb.\nc.\n")

      assert ask(
               c,
               "open('p.pl', read, S), read(S, _), stream_property(S, position(P)), read(S, X), read(S, _), set_stream_position(S, P), read(S, Y), close(S)."
             )
             |> hd() =~
               "X = b, Y = b"

      assert err(c, "set_stream_position(user_input, '$stream_position'(0,1,0,0)).") =~
               "permission_error(reposition,stream,user_input)"

      assert err(c, "open('p.pl', read, S), set_stream_position(S, foo).") =~
               "domain_error(stream_position,foo)"
    end

    test "write/2 & Co. auf Streams", c do
      ok(
        c,
        "open('w.pl', write, S), write(S, 'a b'), nl(S), writeq(S, 'a b'), nl(S), print(S, '$VAR'(1)), nl(S), write_canonical(S, 1+2), nl(S), write_term(S, [1,2,3], [max_depth(2)]), close(S)."
      )

      assert File.read!("w.pl") == "a b\n'a b'\nB\n+(1,2)\n[1,2|...]"
    end

    test "read_term: Fehler", c do
      assert err(c, "read_term(user_input, _, [bogus]).") =~ "domain_error(read_option,bogus)"
      assert err(c, "read_term(user_input, _, foo).") =~ "type_error(list,foo)"
      assert err(c, "read(user_output, _).") =~ "permission_error(input,stream,user_output)"
    end

    test "term_to_atom/2, read_term_from_atom/3", c do
      assert ask(c, "term_to_atom(f(a, 'b c', 1+2), A).") == ["A = 'f(a,\\'b c\\',1+2)'"]
      assert ask(c, "term_to_atom(T, 'foo(X, Y, X)').") == ["T = foo(_A,_B,_A)"]
      assert ask(c, "term_to_atom(T, 'a :- b, c.').") == ["T = (a:-b,c)"]

      assert ask(c, "read_term_from_atom('g(A, _B)', T, [variable_names(V)]).") ==
               ["T = g(_A,_B), V = ['A'=_A,'_B'=_B]"]

      assert err(c, "term_to_atom(_, 'f(').") =~ "syntax_error"
    end
  end

  describe "Termende beim Lesen von Streams (Parser.scan_end/2)" do
    # das Layoutzeichen nach dem Punkt gehört nicht mehr zum Term (ISO 8.14.1.4)
    test "Ende eines Terms" do
      for {text, eof, expected} <- [
            {"foo(a).\nbar.", false, {:end, 7}},
            {"foo(a).", false, :more},
            {"foo(a).", true, {:end, 7}},
            {"X = 'a.b'. y.", true, {:end, 10}},
            {"X =.. L. y.", true, {:end, 8}},
            {"X = 0'. . y.", true, {:end, 9}},
            {"X = 0'''. y.", true, {:end, 9}},
            {"X = 0'\\x41\\. y.", true, {:end, 12}},
            {"X = 1.5e3. y.", true, {:end, 10}},
            {"% c.\n /* x. */ a. ", true, {:end, 17}},
            {"   \n  ", true, :empty},
            {"a :- b", true, {:eof_inside, 6}},
            {"a :- b", false, :more},
            {"\"a. b\". c.", true, {:end, 7}},
            {"f(x).%c\n", true, {:end, 5}},
            {"a = .. .", true, {:end, 8}},
            {"'it''s.'. x.", true, {:end, 9}},
            {"/* offen", false, :more},
            {"/* offen", true, {:eof_inside, 8}},
            {"a =", false, :more},
            # Escapes mit abschließendem Backslash (früher falsch erkannt)
            {"writeq('\\7\\'). x.", true, {:end, 14}},
            {"X is 0'\\\n+'1. y.", true, {:end, 13}},
            # Fehler im Term: Ende wie beim Wiederaufsetzen
            {"x('\\e'). y.", true, {:end, 8}},
            {"x('\\e').", true, {:end, 8}},
            {"x('\\e')", true, {:eof_inside, 7}}
          ] do
        assert PrologEx.Parser.scan_end(text, eof) == expected, inspect(text)
      end
    end
  end

  # ISO 8.14.1.4: read verbraucht das Layoutzeichen nach dem Punkt nicht
  test "read/1: nach dem Term bleibt das Leerzeichen im Stream", c do
    File.write!("rt.txt", "term1. term2. foo 123. term3.")

    assert ask(
             c,
             "open('rt.txt', read, S), read(S, A), get_char(S, C), read(S, B), " <>
               "catch(read(S, _), error(syntax_error(_), _), true), peek_char(S, P), read(S, D), close(S)."
           )
           |> hd() =~ "A = term1, B = term2, C = ' ', D = term3, P = ' '"
  end

  test "read_term/2,3: Optionswerte müssen Variablen oder (Teil-)Listen sein", c do
    File.write!("o.txt", "a. b. c. d.")

    assert ask(
             c,
             "open('o.txt', read, S), read_term(S, T, [variables(V), singletons([])]), close(S)."
           )
           |> hd() =~ "T = a"

    for o <- ["variables(a)", "variable_names([_|a])", "singletons([_|1])", "foo(1)"] do
      assert ask(
               c,
               "open('o.txt', read, S), catch(read_term(S, _, [#{o}]), error(E, _), true), close(S)."
             )
             |> hd() =~ "E = domain_error(read_option,",
             o
    end
  end

  # gefunden mit Logtalks Konformitätstests (ISO 6.3.7.1)
  test "read/2 beachtet double_quotes, das in derselben Anfrage gesetzt wird", c do
    File.write!("dq.txt", ~s("jim". "". ))

    try do
      assert ask(
               c,
               "set_prolog_flag(double_quotes, atom), open('dq.txt', read, S), read(S, A), read(S, B), close(S)."
             )
             |> hd() =~ "A = jim, B = ''"

      assert ask(
               c,
               "set_prolog_flag(double_quotes, codes), open('dq.txt', read, S), read(S, A), close(S)."
             )
             |> hd() =~ "A = [106,105,109]"
    after
      PrologEx.Flags.reset()
    end

    # nach dem Zurücksetzen wieder chars
    assert ask(c, "open('dq.txt', read, S), read(S, A), close(S).") |> hd() =~ ~s(A = "jim")
  end
end
