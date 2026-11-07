defmodule PrologEx.DcgPcreTest do
  # library(dcg/pcre): re//1,2,3 – ein Muster verankert an der aktuellen
  # Stelle; dazu call_dcg/3 (library(dcgs))
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  @src ~S"""
  :- use_module(library(dcg/pcre)).
  :- use_module(library(pcre)).
  :- use_module(library(dcgs)).
  :- use_module(library(lists)).
  :- use_module(library(between)).
  :- use_module(library(iso_ext)).
  :- use_module(library(pio)).
  :- use_module(library(format)).
  toks([T|Ts]) --> ws, tok(T), !, toks(Ts).
  toks([]) --> ws.
  ws --> re("\\s*").
  tok(num(N)) --> re("[0-9]+(\\.[0-9]+)?", [0-Cs|_]), { number_chars(N, Cs) }.
  tok(id(A)) --> re("[a-z_]\\w*", [0-A], [capture_type(atom)]).
  tok(op(A)) --> re("[-+*/=()]", [0-A], [capture_type(atom)]).
  rest(R, R, []).
  % Zelle für Zelle gebaut (gebundene Variablen in der Kette)
  cells([], []).
  cells([C|Cs], [D|Ds]) :- D = C, cells(Cs, Ds).
  gen(F, N) :- open(F, write, S), forall(between(1, N, I), format(S, "w~d ~d, ", [I, I])), close(S).
  cnt(N0, N) --> re("w([0-9]+) ([0-9]+), ", [_, 1-A, 2-A]), !, { N1 is N0+1 }, cnt(N1, N).
  cnt(N, N) --> [].
  """

  defp ask(c, q, src \\ @src) do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))
    PrologEx.put_db(db)
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    db
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  test "Tokenizer: Muster an der aktuellen Stelle, Treffer verbraucht", c do
    assert ask(c, ~S|phrase(toks(Ts), "x1 = 3.14 * (foo + 42)")|) == [
             "Ts = [id(x1),op(=),num(3.14),op(*),op('('),id(foo),op(+),num(42),op(')')]"
           ]
  end

  test "Sub wie re_matchsub, Optionen, Codes", c do
    assert ask(c, ~S|phrase((re("a(b)?(?<n>c)", S), rest(R)), "abcd")|) ==
             [~S|R = "d", S = [0-"abc",1-"b",n-"c"]|]

    assert ask(c, ~S|phrase((re("ab"/i, S), rest(R)), "ABc")|) == [~S|R = "c", S = [0-"AB"]|]

    assert ask(c, ~S|phrase((re("ab", S, [caseless(true)]), rest(R)), "ABc")|) ==
             [~S|R = "c", S = [0-"AB"]|]

    assert ask(c, ~S|phrase((re("a+", S), rest(R)), [0'a, 0'a, 0'b])|) ==
             [~S|R = [98], S = [0-[97,97]]|]

    # Positionen ab der aktuellen Stelle
    assert ask(c, ~S|phrase((re("x"), re("(y)", S, [capture_type(range)]), rest(_)), "xyz")|) ==
             [~S|S = [0-(0-1),1-(0-1)]|]
  end

  test "verankert, deterministisch, leere Treffer", c do
    assert ask(c, ~S|phrase(re("b"), "ab")|) == []
    assert ask(c, ~S|phrase((re("a"), re("^b$")), "ab")|) == ["true"]
    assert ask(c, ~S|phrase((re("a"), re("(?<=a)b")), "ab")|) == []
    assert ask(c, ~S|phrase((re("a*", S), rest(R)), "bc")|) == [~S|R = "bc", S = [0-[]]|]

    assert ask(c, ~S{call_cleanup(phrase((re("a|ab"), rest(R)), "abc"), Det = true)}) ==
             [~S|Det = true, R = "bc"|]
  end

  test "Unicode: Zeichen, ucp, Nicht-ASCII-Muster auf ASCII-Rest", c do
    assert ask(
             c,
             ~S|phrase((re("\\w+", [0-W], [ucp(true)]), re(" "), re("(?<x>.)", S)), "αβγ δ")|
           ) ==
             [~S|S = [0-"δ",x-"δ"], W = "αβγ"|]

    assert ask(c, ~S|phrase(re("\\w+"), "αβγ")|) == []
    # Nicht-ASCII-Muster auf ASCII-Rest: Quantoren gelten für Zeichen
    assert ask(c, ~S|phrase((re("ä{0}b"), re("é?a")), "ba")|) == ["true"]
    # Nicht-ASCII im Rest: Zeichen, nicht Bytes
    assert ask(c, ~S|phrase((re(".", [0-X]), re("..$", [0-Y])), "äöü")|) == [
             ~S|X = "ä", Y = "öü"|
           ]

    # nach einem Nicht-ASCII-Zeichen ist der Rest ASCII: gleiches Ergebnis
    for {pat, txt} <- [
          {"[[:alpha:]]+", "äabc1"},
          {".{2}", "äab"},
          {"(?i)AB", "äab"},
          {"\\\\p{L}+", "äab1"},
          {"[^ä]+", "äabä"},
          {"x|a", "äab"},
          {"\\\\w+$", "äab"}
        ] do
      assert ask(
               c,
               ~s|atom_chars('#{txt}', _L0), append([_], _Cs, _L0), | <>
                 ~s|phrase((re("#{pat}", _S1), rest(_)), _Cs), atom_chars(_A, _Cs), | <>
                 ~s|re_matchsub("^(?:#{pat})", _A, _S2, [capture_type(chars)]), _S1 == _S2|
             ) == ["true"],
             pat
    end
  end

  test "faule Listen (phrase_from_file) werden zu Ende gelesen", c do
    f = Path.join(System.tmp_dir!(), "px_dcg_pcre_#{System.unique_integer([:positive])}.txt")

    try do
      assert ask(c, "gen('#{f}', 2000), phrase_from_file(cnt(0, N), '#{f}')") == ["N = 2000"]

      assert ask(c, "gen('#{f}', 3), phrase_from_file((re(\"w1 \"), re(\"1, w2\")), '#{f}', [])") ==
               []

      assert ask(
               c,
               "gen('#{f}', 3), phrase_from_file((re(\"w1 1, \"), re(\"(.*)\", [_, 1-R])), '#{f}')"
             ) ==
               [~S|R = "w2 2, w3 3, "|]
    after
      File.rm(f)
    end
  end

  test "lange Listen: ein Tokenizer bleibt linear", c do
    # 20 000 Treffer über einem Text von gut 200 000 Zeichen (nur das
    # Zerlegen gemessen)
    txt = Enum.map_join(1..20000, fn i -> "w#{i} #{i}, " end)
    src = @src <> "big('#{txt}').\n"

    q =
      "big(_A), atom_chars(_A, _Cs), statistics(runtime, [_T0|_]), phrase(cnt(0, N), _Cs), " <>
        "statistics(runtime, [_T1|_]), T is _T1 - _T0"

    [res] = ask(c, q, src)
    assert res =~ "N = 20000"
    [_, ms] = Regex.run(~r/T = (\d+)/, res)
    assert String.to_integer(ms) < 5000, res
  end

  test "der gemerkte Text: neu gebundene Variablen, mehrere Listen", c do
    # nach dem Zurücksetzen ist T anders gebunden: der Text wird neu gelesen
    assert ask(
             c,
             ~S{L = [a|T], (T = [b], phrase(re("ab"), L), fail ; T = [c], phrase(re("ac"), L))}
           ) == [~S|L = "ac", T = "c"|]

    assert ask(
             c,
             ~S{cells("abcabc", L), L = [_|L1], phrase(re("bc"), L1, L2), } <>
               ~S{(L2 = [X|_], X = a -> true ; true), phrase(re("abc", _), L2), phrase(re("bcabc"), L1)}
           )
           |> length() == 1

    # zwei Listen im Wechsel
    assert ask(
             c,
             ~S|A = "aaa", B = "bbb", phrase((re("a"), rest(A1)), A), phrase((re("b"), rest(B1)), B), | <>
               ~S|phrase(re("aa"), A1), phrase(re("bb"), B1), phrase(re("aaa"), A)|
           )
           |> length() == 1
  end

  test "Fehler", c do
    assert ask(c, ~S{catch(phrase(re("a"), [a|_]), error(E, _), true)}) == [
             "E = instantiation_error"
           ]

    assert ask(c, ~S|catch(phrase(re("a"), [a, _]), error(E, _), true)|) == [
             "E = instantiation_error"
           ]

    assert ask(c, ~S{catch(phrase(re("a"), [a|b]), error(E, _), true)}) == [
             "E = type_error(list,[a|b])"
           ]

    assert ask(c, ~S|catch(phrase(re("a"), [a, 0'b]), error(E, _), true)|) |> hd() =~
             "type_error(text,"

    assert ask(c, ~S|catch(phrase(re("("), "a"), error(E, _), true)|) |> hd() =~ "syntax_error("

    assert ask(
             c,
             ~S{X = [a|X], catch(phrase(re("a"), X), error(E, _), true), E = type_error(list, [a|_])}
           ) != []
  end

  test "call_dcg/3", c do
    assert ask(c, ~S|call_dcg((re("a"), [b]), "abc", R)|) == [~S|R = "c"|]
    assert ask(c, ~S|call_dcg(toks(Ts), "a 1", [])|) == ["Ts = [id(a),num(1)]"]
  end

  test "nur nach use_module(library(dcg/pcre))", c do
    assert ask(c, ~S|catch(phrase(re("a"), "a"), error(E, _), true)|, "") ==
             ["E = existence_error(procedure,re/3)"]
  end
end
