defmodule PrologEx.ScryerCharsioTest do
  # library(charsio), library(dcgs) aus Scryer Prolog; append/2
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag :tmp_dir

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    {db, []} =
      PrologEx.Consult.load(
        %{},
        Reader.read_terms(r, """
        :- use_module(library(charsio)).
        :- use_module(library(dcgs)).
        :- use_module(library(lists)).
        """)
      )

    {:ok, reader: r, db: db}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  defp ask(c, q, n \\ 20) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    c.db
    |> PrologEx.query(g)
    |> Enum.take(n)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, goal), do: ask(c, "catch(#{goal}, error(E, _), true)")

  test "char_type/2: alle Klassen eines Zeichens (Beispiel aus Scryers Doku)", c do
    assert ask(c, "char_type(a, T)") ==
             Enum.map(
               ~w(alnum alpha alphabetic alphanumeric ascii ascii_graphic hexadecimal_digit lower
                  octet prolog symbolic_control),
               &"T = #{&1}"
             ) ++ [~s|T = lower("a")|, ~s|T = upper("A")|]
  end

  test "char_type/2: einzelne Klassen", c do
    yes = [
      {"'_'", "alpha"},
      {"'_'", "alnum"},
      {"'ä'", "alpha"},
      {"'ä'", "alphabetic"},
      {"'ä'", "lower"},
      {"'Ä'", "upper"},
      {"'7'", "decimal_digit"},
      {"'7'", "numeric"},
      {"'٣'", "numeric"},
      {"'½'", "numeric"},
      {"'`'", "prolog"},
      {"'Ⅳ'", "alphabetic"},
      {"'1'", "binary_digit"},
      {"'F'", "hexadecimal_digit"},
      {"'7'", "octal_digit"},
      {"e", "exponent"},
      {"'#'", "graphic"},
      {"'\\\\'", "graphic_token"},
      {"' '", "layout"},
      {"'\\n'", "whitespace"},
      {"'\\x3000\\'", "whitespace"},
      {"'\\x7\\'", "control"},
      {"'`'", "meta"},
      {"'|'", "solo"},
      {"'%'", "solo"},
      {"'-'", "sign"},
      {"x", "symbolic_hexadecimal"},
      {"v", "symbolic_control"},
      {"'ÿ'", "octet"},
      {"'.'", "ascii_punctuation"},
      {"'~'", "ascii_graphic"},
      {"a", "prolog"},
      # wie Scryer: alpha ist, was keiner anderen Klasse angehört
      {"'€'", "alpha"}
    ]

    for {ch, t} <- yes, do: assert(ask(c, "char_type(#{ch}, #{t})") == ["true"], "#{ch} #{t}")

    no = [
      {"'\\\\'", "graphic"},
      {"'#'", "alpha"},
      {"'7'", "alpha"},
      {"' '", "alpha"},
      {"'('", "alpha"},
      {"''''", "alpha"},
      {"'Ä'", "lower"},
      {"'ā'", "octet"},
      {"'2'", "binary_digit"},
      {"g", "hexadecimal_digit"},
      {"'8'", "octal_digit"},
      {"'\\x3000\\'", "layout"},
      {"'€'", "ascii"},
      {"' '", "ascii_graphic"},
      {"'\\x7\\'", "prolog"}
    ]

    for {ch, t} <- no, do: assert(ask(c, "char_type(#{ch}, #{t})") == [], "#{ch} #{t}")

    assert ask(c, "char_type(ß, upper(U))") == [~s|U = "SS"|]
    assert ask(c, "char_type('A', lower(L))") == [~s|L = "a"|]
    assert ask(c, "char_type(X, decimal_digit)") |> length() == 10
    assert ask(c, "char_type(X, decimal_digit)") |> hd() == "X = '0'"
  end

  test "char_type/2: Fehler", c do
    assert err(c, "char_type(ab, alpha)") == ["E = type_error(character, ab)"]
    assert err(c, "char_type(1, alpha)") == ["E = type_error(character, 1)"]
    assert err(c, "char_type(a, foo)") == ["E = domain_error(char_type, foo)"]
    assert err(c, "char_type(_, _)") == ["E = instantiation_error"]
  end

  test "read_from_chars/2, read_term_from_chars/3", c do
    assert ask(c, ~s|read_from_chars("f(X, Y, X).", T), T = f(A, B, C), A == C, A \\== B|)
           |> length() == 1

    assert ask(c, ~s{read_from_chars("[1, 2|T] .", L)}) == ["L = [1, 2|_A]"]
    assert ask(c, ~s|read_from_chars("", T)|) == ["T = end_of_file"]
    assert ask(c, ~s|read_from_chars("   ", T)|) == ["T = end_of_file"]
    assert err(c, ~s|read_from_chars("f(", _)|) == ["E = syntax_error(end_of_file_in_term)"]
    assert err(c, "read_from_chars(_, _)") == ["E = instantiation_error"]
    assert err(c, "read_from_chars(abc, _)") == ["E = type_error(list, abc)"]

    assert ask(c, ~s|read_term_from_chars("g(X, _Y).", T, [variable_names(Vs)])|) ==
             ["T = g(_A, _B), Vs = ['X'=_A, '_Y'=_B]"]

    assert err(c, ~s|read_term_from_chars("a.", _, [nix])|) == [
             "E = domain_error(read_option, nix)"
           ]
  end

  test "write_term_to_chars/3: freie Variablen heißen A, B, ... (wie Scryer)", c do
    assert ask(c, ~s|write_term_to_chars(f(X, Y, 'A b'), [quoted(true)], Cs)|) ==
             [~s|Cs = "f(A,B,'A b')"|]

    assert ask(c, ~s|write_term_to_chars(f(X, Y), [variable_names(['A'=Y])], Cs)|) ==
             [~s|Cs = "f(B,A)"|]

    assert ask(c, ~s|write_term_to_chars(- (1), [], Cs)|) == [~s|Cs = "- (1)"|]
    assert ask(c, ~s|write_term_to_chars([a, b], [], Cs)|) == [~s|Cs = "[a,b]"|]
    assert ask(c, ~s|write_term_to_chars('$VAR'(1), [numbervars(true)], Cs)|) == [~s|Cs = "B"|]
    assert err(c, "write_term_to_chars(a, _, _)") == ["E = instantiation_error"]
    assert err(c, "write_term_to_chars(a, [foo], _)") == ["E = domain_error(write_option, foo)"]
    assert err(c, "write_term_to_chars(a, [], x)") == ["E = uninstantiation_error(x)"]
    # Optionen zuerst
    assert err(c, "write_term_to_chars(a, [foo], x)") == ["E = domain_error(write_option, foo)"]
  end

  test "chars_utf8bytes/2, chars_base64/3", c do
    assert ask(c, ~s|chars_utf8bytes("aä€", Bs)|) == ["Bs = [97, 195, 164, 226, 130, 172]"]
    assert ask(c, "chars_utf8bytes(Cs, [97, 195, 164, 226, 130, 172])") == [~s|Cs = "aä€"|]
    assert ask(c, ~s|chars_base64("hello", B, [])|) == [~s|B = "aGVsbG8="|]
    assert ask(c, ~s|chars_base64("hello", B, [padding(false)])|) == [~s|B = "aGVsbG8"|]
    assert ask(c, ~s|chars_base64(C, "aGVsbG8=", [])|) == [~s|C = "hello"|]
    assert ask(c, ~s|chars_base64(X, "-w==", [charset(url)])|) == [~s|X = "û"|]
    assert ask(c, ~s|chars_base64(X, "+w==", [])|) == [~s|X = "û"|]
    assert ask(c, ~s|chars_base64(_, "%%", [])|) == []
    assert err(c, ~s|chars_base64("ā", _, [])|) == ["E = domain_error(octet_character, 'ā')"]
    assert err(c, ~s|chars_base64("a", _, [charset(x)])|) == ["E = domain_error(charset, x)"]
    assert err(c, ~s|chars_base64("a", _, [_])|) == ["E = instantiation_error"]
  end

  test "get_line_to_chars/3, get_n_chars/3", c do
    f = Path.join(c.tmp_dir, "t.txt")
    File.write!(f, "erste\nzweite zeile\n")

    assert ask(c, """
           open('#{f}', read, S), get_line_to_chars(S, L, []),
           get_n_chars(S, 3, C3), get_n_chars(S, N, R), get_line_to_chars(S, E, end),
           close(S)
           """)
           |> hd()
           |> String.replace(~r/S = '\$stream'\(\d+\)/, "S") ==
             ~s|C3 = "zwe", E = end, L = "erste\\n", N = 10, R = "ite zeile\\n", S|

    assert ask(c, "open('#{f}', read, S, [type(binary)]), get_n_chars(S, 2, Cs), close(S)")
           |> hd() =~ ~s|Cs = "er"|

    # Binärstream: Bytes als Zeichen
    File.write!(f, "ä")

    assert ask(c, "open('#{f}', read, S, [type(binary)]), get_n_chars(S, 5, Cs), close(S)")
           |> hd() =~ ~s|Cs = "Ã¤"|

    # bis zum Ende, über mehrere Blöcke von 512 Zeichen
    File.write!(f, String.duplicate("x", 1500))

    assert ask(c, "open('#{f}', read, S), get_n_chars(S, N, _), close(S)") |> hd() =~
             "N = 1500"
  end

  test "dcgs: seq//1, seqq//1, ...//0", c do
    assert ask(c, ~s|phrase((seq(A), "x", ...), "abxcxd")|) == [~s|A = "ab"|, ~s|A = "abxc"|]
    assert ask(c, ~s|phrase(seqq(["ab", "c"]), L)|) == [~s|L = "abc"|]
    assert ask(c, ~s|phrase(seq(X), [])|) == ["X = []"]
    assert ask(c, ~s|phrase((..., [X]), "abc")|) == ["X = c"]
    assert ask(c, ~s|phrase(..., [])|) == ["true"]
  end

  test "append/2", c do
    assert ask(c, "append([[1], [2, 3], []], L)") == ["L = [1, 2, 3]"]
    assert ask(c, "append([X, [3]], [1, 2, 3])") |> hd() == "X = [1, 2]"
    assert err(c, "append([[1]|_], _)") == ["E = instantiation_error"]
    assert err(c, "append(a, _)") == ["E = type_error(list, a)"]
  end
end
