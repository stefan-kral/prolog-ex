defmodule PrologEx.DcgLibsTest do
  # library(dcg/high_order) (wie SWI) und library(dcg/chars) (SWIs
  # dcg/basics auf Zeichen)
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

  @src """
  :- use_module(library(dcg/high_order)).
  :- use_module(library(dcg/chars)).
  :- use_module(library(lists)).
  d(D) --> [D], { member(D, "0123456789") }.
  kv(K-V) --> csym(K), "=", integer(V).
  """

  defp ask(c, q, src \\ @src) do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))
    PrologEx.put_db(db)
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    db
    |> PrologEx.query(g)
    |> Enum.take(5)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp all(c, q), do: ask(c, "findall(X, #{q}, Xs)")

  describe "dcg/high_order" do
    test "sequence//2,3,5", c do
      assert ask(c, "phrase(sequence(d, Ds), \"123\")") == ["Ds = \"123\""]
      assert ask(c, "phrase(sequence(d, \",\", Ds), \"1,2,3\")") == ["Ds = \"123\""]
      # wie SWI: ein Trenner am Ende wird mitgelesen
      assert ask(c, "phrase(sequence(d, \",\", Ds), \"1,2,\")") == ["Ds = \"12\""]
      assert ask(c, "phrase(sequence(d, \",\", Ds), \"\")") == ["Ds = []"]

      assert ask(c, "phrase(sequence(\"[\", kv, \",\", \"]\", L), \"[a=1,b=2]\")") ==
               ["L = [a-1,b-2]"]

      assert ask(c, "phrase(sequence(\"[\", d, \",\", \"]\", L), \"[]\")") == ["L = []"]
      # deterministisch
      assert ask(c, "findall(L, phrase(sequence(\"(\", d, \",\", \")\", L), \"(1,2)\"), Ls)") ==
               ["Ls = [\"12\"]"]

      # erzeugen: wie SWI mit Trenner am Ende (Sep vor dem Ende versucht)
      assert ask(c, "phrase(sequence(d, \",\", \"12\"), Cs)") == ["Cs = \"1,2,\""]
      # alle Zerlegungen bei sequence//2
      assert all(c, "(phrase((sequence(d, A), sequence(d, B)), \"12\"), X = A-B)") ==
               ["Xs = [\"12\"-[],\"1\"-\"2\",[]-\"12\"]"]
    end

    test "optional//2", c do
      assert ask(c, "phrase((optional(\"-\", []), integer(I)), \"-1\")") == ["I = 1"]
      assert ask(c, "phrase((optional(\"+\", []), integer(I)), \"5\")") == ["I = 5"]
      assert ask(c, "phrase(optional(\"x\", \"y\"), Cs)") == ["Cs = \"x\""]
      assert all(c, "phrase((optional(\"a\", []), remainder(X)), \"ab\")") == ["Xs = [\"b\"]"]
    end

    test "foreach//2,3", c do
      assert ask(c, "phrase(foreach(member(Y, [a,b,c]), [Y], \", \"), Cs)") ==
               ["Cs = \"a, b, c\""]

      assert ask(c, "phrase(foreach(member(Y, [1,2]), integer(Y)), Cs)") == ["Cs = \"12\""]
      assert ask(c, "phrase(foreach(fail, [x]), Cs)") == ["Cs = []"]
    end

    test "im Modul des Aufrufers (meta_predicate)", c do
      assert ask(c, "phrase(sequence(kv, \";\", L), \"x=1;y=2\")") == ["L = [x-1,y-2]"]
    end
  end

  describe "dcg/chars" do
    test "Leerraum", c do
      assert ask(c, "phrase((blanks, \"a\", blanks), \" \\t\\na \")") == ["true"]
      assert ask(c, "phrase((whites, \"a\"), \" \\ta\")") == ["true"]
      assert ask(c, "phrase((whites, \"a\"), \"\\na\")") == []
      assert ask(c, "phrase(blank, \"x\")") == []
      assert ask(c, "phrase(nonblanks(W), \"ab c\", R)") == ["R = \" c\", W = \"ab\""]
      assert ask(c, "phrase(nonblank(C), \"x\")") == ["C = x"]
      assert ask(c, "phrase((blanks_to_nl, \"x\"), \" \\t\\nx\")") == ["true"]
      assert ask(c, "phrase(blanks_to_nl, \"  \")") == ["true"]
      assert ask(c, "phrase(blanks_to_nl, \" x\")") == []
    end

    test "Zahlen lesen", c do
      for {inp, nt, res} <- [
            {"42", "integer", "42"},
            {"-42", "integer", "-42"},
            {"+7", "integer", "7"},
            {"3.25", "number", "3.25"},
            {"-3", "number", "-3"},
            {"1e3", "number", "1000.0"},
            {"2.5E-2", "number", "0.025"},
            {"1.5e+2", "number", "150.0"},
            {"1.5", "float", "1.5"},
            {"ff", "xinteger", "255"},
            {"1A", "xinteger", "26"}
          ] do
        assert ask(c, "phrase(#{nt}(N), \"#{inp}\")") == ["N = #{res}"], inp
      end

      assert ask(c, "phrase(float(_), \"12\")") == []
      assert ask(c, "phrase(integer(_), \"-\")") == []
      assert ask(c, "phrase(integer(_), \"\")") == []
      # "12." ist 12 und ein Rest
      assert ask(c, "phrase(number(N), \"12.\", R)") == ["N = 12, R = \".\""]
      assert ask(c, "phrase(number(N), \"12.x\", R)") == ["N = 12, R = \".x\""]
      assert ask(c, "phrase(digits(Ds), \"123x\", R)") == ["Ds = \"123\", R = \"x\""]
      assert ask(c, "phrase(digits(Ds), \"x\", R)") == ["Ds = [], R = \"x\""]
      assert ask(c, "phrase(digit(D), \"7\")") == ["D = '7'"]
      assert ask(c, "phrase(xdigit(W), \"c\")") == ["W = 12"]
      assert ask(c, "phrase(xdigits(Ws), \"1aF\")") == ["Ws = [1,10,15]"]
    end

    test "Zahlen erzeugen", c do
      assert ask(c, "phrase(integer(-42), Cs)") == ["Cs = \"-42\""]
      assert ask(c, "phrase(number(1.5), Cs)") == ["Cs = \"1.5\""]
      assert ask(c, "phrase(float(2.0), Cs)") == ["Cs = \"2.0\""]
      assert ask(c, "phrase(xinteger(255), Cs)") == ["Cs = \"ff\""]
      assert ask(c, "phrase(csym(abc), Cs)") == ["Cs = \"abc\""]
      assert ask(c, "phrase(atom('a b'), Cs)") == ["Cs = \"a b\""]
      assert ask(c, "catch(phrase(atom(_), _), error(E, _), true)") == ["E = instantiation_error"]
    end

    test "Text", c do
      assert ask(c, "phrase((string_without(\",\", S), \",\", remainder(R)), \"ab,cd\")") ==
               ["R = \"cd\", S = \"ab\""]

      assert ask(c, "phrase((string_without(',;', S), remainder(R)), \"ab;c\")") ==
               ["R = \";c\", S = \"ab\""]

      assert ask(c, "phrase((string(K), \"=\", string(V)), \"k=v\")") == ["K = \"k\", V = \"v\""]

      assert ask(c, "findall(S, phrase((string(S), remainder(_)), \"ab\"), Ss)") ==
               ["Ss = [[],\"a\",\"ab\"]"]

      assert ask(c, "phrase((csym(C), blanks, prolog_symbol(P)), \"foo_1  =>\")") ==
               ["C = foo_1, P = =>"]

      assert ask(c, "phrase(csym(_), \"1a\")") == []
      assert ask(c, "phrase(csyms(Cs), \"a_1-\", R)") == ["Cs = \"a_1\", R = \"-\""]
      assert ask(c, "phrase(alpha_to_lower(L), \"Q\")") == ["L = q"]
      assert ask(c, "phrase(alpha_to_lower(q), \"Q\")") == ["true"]
      assert ask(c, "phrase(alpha_to_lower(_), \"-\")") == []
      assert ask(c, "phrase((\"a\", eol, \"b\", eol), \"a\\nb\")") == ["true"]
      assert ask(c, "phrase((\"a\", eol, \"b\"), \"a\\r\\nb\")") == ["true"]
      assert ask(c, "phrase(eos, \"x\")") == []
      assert ask(c, "phrase(remainder(R), \"xy\")") == ["R = \"xy\""]
    end

    test "zusammen: Schlüssel-Wert-Zeilen", c do
      assert ask(
               c,
               "phrase(sequence(kv, (blanks, \",\", blanks), L), \"a=1 , b=-2,c=30\")"
             ) == ["L = [a-1,b- -2,c-30]"]
    end

    test "deterministisch, wo SWI es ist", c do
      for g <- [
            "phrase(sequence(\"[\", d, \",\", \"]\", _), \"[1,2]\", _)",
            "phrase(blanks, \"  \")",
            "phrase(integer(_), \"-1\")",
            "phrase(number(_), \"1.5\")",
            "phrase(nonblanks(_), \"ab\")"
          ] do
        assert ask(c, "call_cleanup(#{g}, Det = true)") == ["Det = true"], g
      end

      # nach einem Trenner kein Zurück (wie SWI)
      assert ask(c, "findall(L-R, phrase(sequence(digit, \",\", L), \"1,2\", R), X)") ==
               ["X = [\"12\"-[],\"1\"-\"2\"]"]

      assert ask(c, "phrase(blanks_to_nl, \" x\", R)") == []
      assert ask(c, "phrase(nonblank(_), \" \")") == []
    end

    test "ohne Import nicht sichtbar", c do
      assert ask(c, "catch(phrase(blanks, []), error(E, _), true)", "") ==
               ["E = existence_error(procedure,blanks/2)"]
    end
  end
end
