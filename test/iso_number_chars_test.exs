defmodule PrologEx.IsoNumberCharsTest do
  # Konformitätstests von Ulrich Neumerkel (ISO/IEC JTC1 SC22 WG17):
  # https://www.complang.tuwien.ac.at/ulrich/iso-prolog/number_chars
  # Erwartungen nach Cor.2; wo die Tabelle mehrere Fehler zulässt, jeder
  # davon. Fall 46 (zyklische Liste) fehlt: prolog-ex hängt dort (bewusst).
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @cases [
    {1, "number_chars(1.2,['1',.,'2']).", true},
    {2, "number_chars(1.0e9,['1',.,'0','E','9']).", true},
    {3, "number_chars(1,['0','1']).", true},
    {4, "number_chars(1,[a]).", {:error, ["syntax_error"]}},
    {5, "number_chars(1,[]).", {:error, ["syntax_error"]}},
    {6, "number_chars(1,[[]]).", {:error, ["type_error(character, [])"]}},
    {7, "number_chars(1,[' ',[]]).", {:error, ["type_error(character, [])"]}},
    {8, "number_chars(1,[0]).", {:error, ["type_error(character, 0)"]}},
    {9, "number_chars(1,[_,[]]).", {:error, ["type_error(character, [])"]}},
    {10, "number_chars(N,[X]).", {:error, ["instantiation_error"]}},
    {11, "number_chars(N,['0'|_]).", {:error, ["instantiation_error"]}},
    {12, "number_chars(N,'1').", {:error, ["type_error(list, '1')"]}},
    {13, "number_chars(N,[a|a]).", {:error, ["type_error(list, [a|a])"]}},
    {14, "number_chars(N,[49]).", {:error, ["type_error(character, 49)"]}},
    {15, "number_chars(N,[]).", {:error, ["syntax_error"]}},
    {16, "number_chars(N,['3',' ']).", {:error, ["syntax_error"]}},
    {17, "number_chars(N,['3',.]).", {:error, ["syntax_error"]}},
    {18, "number_chars(N,[' ','1']).", ["N = 1"]},
    {19, "number_chars(N,['\\n','1']).", ["N = 1"]},
    {20, "number_chars(N,[' ','0','''',a]).", ["N = 97"]},
    {21, "number_chars(N,[-,' ','1']).", ["N = -1"]},
    {22, "number_chars(N,[/,*,*,/,'1']).", ["N = 1"]},
    {23, "number_chars(N,['%','\\n','1']).", ["N = 1"]},
    {24, "number_chars(N,[-,/,*,*,/,'1']).", {:error, ["syntax_error"]}},
    {25, "number_chars(N,['1',e,'1']).", {:error, ["syntax_error"]}},
    {26, "number_chars(N,['1',.,'0',e]).", {:error, ["syntax_error"]}},
    {27, "number_chars(N,['1',.,'0',e,e]).", {:error, ["syntax_error"]}},
    {28, "number_chars(N,['0',x,'1']).", ["N = 1"]},
    {29, "number_chars(N,['0','X','1']).", {:error, ["syntax_error"]}},
    {30, "number_chars(1E1,_).", :read_error},
    {31, "number_chars(1,[C]).", ["C = '1'"]},
    {32, "number_chars(1,[C,D]).", :fail},
    {33, "number_chars(1,[C,C]).", :fail},
    {34, "number_chars(0,[C,C]).", :fail},
    {35, "number_chars(10,[C,D]).", ["C = '1', D = '0'"]},
    {36, "number_chars(100,[C,D]).", :fail},
    {37, "number_chars(N,[X|2]).", {:error, ["type_error(list, [", "instantiation_error"]}},
    {38, "number_chars(N,[1|_]).", {:error, ["instantiation_error", "type_error(character, 1)"]}},
    {39, "number_chars(V,[1|2]).",
     {:error, ["type_error(list, [1|2])", "type_error(character, 1)"]}},
    {40, "number_chars([],1).", {:error, ["type_error(number, [])", "type_error(list, 1)"]}},
    {41, "number_chars(1,1).", {:error, ["type_error(list, 1)"]}},
    {42, "number_chars(1,[a|2]).", {:error, ["type_error(list, [a|2])"]}},
    {43, "number_chars(1,[_|2]).", {:error, ["type_error(list, ["]}},
    {44, "number_chars(1,[[]|_]).", {:error, ["type_error(character, [])"]}},
    {45, "number_chars(1,[[]|2]).",
     {:error, ["type_error(character, [])", "type_error(list, [[]|2])"]}},
    {47, "number_chars(1,['.'|_]).", :fail},
    {48, "number_chars(N,[+,'1']).", {:error, ["syntax_error"]}},
    {49, "number_chars(N,[+,' ','1']).", {:error, ["syntax_error"]}},
    {50, "number_chars(N,['''',+,'''','1']).", {:error, ["syntax_error"]}},
    {51, "number_chars(N,['11']).", {:error, ["type_error(character, '11')"]}},
    {52, "number_chars(N,['1.1']).", {:error, ["type_error(character, '1.1')"]}},
    {53, "number_chars(1+1,['2']).", {:error, ["type_error(number, 1+1)"]}}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  for {n, query, expected} <- @cases do
    test "Fall #{n}: #{query}", %{reader: r} do
      check(r, unquote(query), unquote(Macro.escape(expected)))
    end
  end

  defp check(r, query, expected) do
    case {Reader.read_terms(r, query), expected} do
      {[{:error, _}], :read_error} ->
        :ok

      {[{:term, g, _}], expected} ->
        run = fn ->
          PrologEx.query(%{}, g)
          |> Enum.take(2)
          |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
        end

        case expected do
          true ->
            assert run.() == ["true"]

          :fail ->
            assert run.() == []

          {:error, alternatives} ->
            e = assert_raise(PrologEx.Error, run)
            msg = Exception.message(e)
            assert Enum.any?(alternatives, &String.starts_with?(msg, &1)), msg

          answers ->
            assert run.() == answers
        end
    end
  end
end
