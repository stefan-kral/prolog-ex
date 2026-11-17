defmodule PrologEx.JsonTestSuiteTest do
  # JSONTestSuite (Nicolas Seriot, MIT; github.com/nst/JSONTestSuite, Stand
  # 1ef36fa): 318 Dateien in test/fixtures/jsontestsuite/test_parsing –
  # y_… muss ein Parser annehmen, n_… ablehnen, i_… ist freigestellt.
  # Angenommen heißt: genau ein Wert, danach nur Leerraum (RFC 8259).
  #
  # library(http/json) verhält sich wie SWI-Prolog 9.0.4 und nimmt wie
  # dieses 12 ungültige Texte an (führende Nullen, 2., Komma vor ] und },
  # Tab und Zeilenwechsel in Strings); sonst wie die Suite. PrologEx lehnt
  # ungültiges UTF-8 ab, SWI liest es (mit Warnungen).
  #
  # library(serialization/json) ist Scryers json_chars//1, unverändert:
  # dieselben Ergebnisse wie Scryer, auch die Fehler (Ersatzpaare \ud834…
  # und Nichtzeichen U+1FFFE, U+10FFFE abgelehnt). Ein UTF-8-BOM am Anfang
  # überspringen beide (open/4, bom(true)).
  #
  # Jede Änderung fällt auf, auch eine Verbesserung: dann die Listen hier
  # anpassen.
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @dir "test/fixtures/jsontestsuite/test_parsing"
  @files @dir |> File.ls!() |> Enum.sort()

  @http_lenient ~w(n_array_extra_comma.json n_array_number_and_comma.json n_number_-01.json
    n_number_-1.0..json n_number_-2..json n_number_neg_int_starting_with_zero.json
    n_number_real_without_fractional_part.json n_number_with_leading_zero.json
    n_object_trailing_comma.json n_string_unescaped_ctrl_char.json
    n_string_unescaped_newline.json n_string_unescaped_tab.json)

  @http_i_accept ~w(i_number_double_huge_neg_exp.json i_number_real_underflow.json
    i_number_too_big_neg_int.json i_number_too_big_pos_int.json
    i_number_very_big_negative_int.json i_object_key_lone_2nd_surrogate.json
    i_string_1st_surrogate_but_2nd_missing.json i_string_1st_valid_surrogate_2nd_invalid.json
    i_string_incomplete_surrogate_and_escape_valid.json i_string_incomplete_surrogate_pair.json
    i_string_incomplete_surrogates_escape_valid.json i_string_invalid_lonely_surrogate.json
    i_string_invalid_surrogate.json i_string_inverted_surrogates_U+1D11E.json
    i_string_lone_second_surrogate.json i_structure_500_nested_arrays.json
    i_structure_UTF-8_BOM_empty_object.json)

  @ser_rejects_valid ~w(y_string_accepted_surrogate_pair.json
    y_string_accepted_surrogate_pairs.json y_string_last_surrogates_1_and_2.json
    y_string_surrogates_U+1D11E_MUSICAL_SYMBOL_G_CLEF.json
    y_string_unicode_U+10FFFE_nonchar.json y_string_unicode_U+1FFFE_nonchar.json)

  @ser_i_accept ~w(i_number_double_huge_neg_exp.json i_number_neg_int_huge_exp.json
    i_number_real_neg_overflow.json i_number_real_pos_overflow.json
    i_number_real_underflow.json i_number_too_big_neg_int.json i_number_too_big_pos_int.json
    i_number_very_big_negative_int.json i_structure_500_nested_arrays.json
    i_structure_UTF-8_BOM_empty_object.json)

  # json_chars//1 braucht hierfür (250 000 Zeichen tief verschachtelt) auch
  # in Scryer länger als 10 s
  @ser_skip ~w(n_structure_open_array_object.json)
  @ser_slow ~w(n_structure_100000_opening_arrays.json)

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    prog = """
    :- use_module(library(http/json)).
    :- use_module(library(serialization/json)).
    :- use_module(library(pio)).
    :- use_module(library(iso_ext)).
    http(P, R) :-
        catch(setup_call_cleanup(open(P, read, S, [encoding(utf8)]),
                                 ( json_read(S, _), rest_ws(S) -> R = accept ; R = reject ),
                                 close(S)),
              _, R = reject).
    rest_ws(S) :- get_char(S, C), ( C == end_of_file -> true ; ws(C), rest_ws(S) ).
    ws(' '). ws('\\t'). ws('\\n'). ws('\\r').
    ser(P, R) :- catch(( phrase_from_file(json_chars(_), P, [as(chars)]) -> R = accept ; R = reject ), _, R = reject).
    """

    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(r, prog))
    {:ok, reader: r, db: db}
  end

  defp outcome(c, pred, file) do
    Reader.put_current(c.reader)
    path = Path.join(@dir, file)

    case TableCase.run(c.reader, c.db, "#{pred}('#{path}', R)") do
      {_, {:answers, ["R = accept"]}} -> :accept
      {_, {:answers, ["R = reject"]}} -> :reject
      other -> {:unexpected, other}
    end
  end

  defp expected(file, lenient, i_accept, rejects_valid) do
    cond do
      file in lenient -> :accept
      file in rejects_valid -> :reject
      String.starts_with?(file, "y_") -> :accept
      String.starts_with?(file, "n_") -> :reject
      file in i_accept -> :accept
      true -> :reject
    end
  end

  test "library(http/json): wie die Suite, bis auf SWIs Nachsicht", c do
    bad =
      for f <- @files,
          want = expected(f, @http_lenient, @http_i_accept, []),
          got = outcome(c, "http", f),
          got != want,
          do: {f, want, got}

    assert bad == []
  end

  test "library(serialization/json): wie Scryer", c do
    bad =
      for f <- @files -- (@ser_skip ++ @ser_slow),
          want = expected(f, [], @ser_i_accept, @ser_rejects_valid),
          got = outcome(c, "ser", f),
          got != want,
          do: {f, want, got}

    assert bad == []
  end

  @tag :slow
  test "library(serialization/json): 100 000 offene Klammern", c do
    for f <- @ser_slow, do: assert(outcome(c, "ser", f) == :reject)
  end
end
