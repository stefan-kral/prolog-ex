defmodule PrologEx.Builtins.Readutil do
  @moduledoc """
  `library(readutil)` wie in SWI-Prolog (Zeilen, Streams und Dateien
  lesen), in Elixir; dieselbe Bibliothek in reinem Prolog:
  `library(readutil_pl)`. Strings gibt es in PrologEx nicht: statt
  `read_line_to_string/2` und `read_file_to_string/3` gibt es
  `read_line_to_chars/2` und `read_file_to_chars/3` (Zeichenlisten, wie
  `"…"` mit `double_quotes` = `chars`).

    * `read_line_to_codes(+S, -Codes)` – die nächste Zeile ohne `\\n`
      (jedes `\\r` fällt weg, wie in SWI); am Ende `end_of_file`
    * `read_line_to_codes(+S, -Codes, ?Rest)` – Differenzliste, `\\n` bleibt;
      am Ende `Codes = Rest = []` (auch nach einer letzten Zeile ohne `\\n`
      ist `Rest = []`)
    * `read_line_to_chars(+S, -Chars)` – wie `read_line_to_string/2`: ohne
      `\\n`, `\\r` an den Enden fällt weg; am Ende (nichts mehr gelesen)
      `end_of_file`, eine letzte Zeile ohne `\\n` kommt noch
    * `read_stream_to_codes(+S, -Codes)`, `read_stream_to_codes(+S, -Codes,
      ?Rest)` – der ganze Rest
    * `read_file_to_codes(+Datei, -Codes, +Optionen)` – Option `tail(T)`:
      Differenzliste; `read_file_to_chars(+Datei, -Chars, +Optionen)`
    * `read_file_to_terms(+Datei, -Terme, +Optionen)` – Option `tail(T)`;
      Optionen von `read_term/3` (`variable_names/1` …) gelten je Term
    * Andere Optionen (für `absolute_file_name/3`, `open/4` in SWI) werden
      übergangen.

  Unterschied zur Prolog-Variante: eine Zeile bzw. der Rest in einem Zug
  aus dem Puffer des Streams (Stream.read_line/1, Stream.read_rest/1),
  eine Datei mit File.read/1 – statt Zeichen für Zeichen über
  `get_code/2`. Lesen ist Ein-/Ausgabe: im Kind von library(concurrent)
  nur von eigenen Streams und Dateien (PrologEx.Effects).
  """
  use PrologEx.Builtin, module: "readutil"
  alias PrologEx.{Error, Store}
  alias PrologEx.Stream, as: S
  alias PrologEx.Builtins.IO, as: PIO

  # --- Zeilen ------------------------------------------------------------------

  defbuiltin "read_line_to_codes", [stream, codes] do
    case line(deref(stream)) do
      :eof -> {:unify, [{codes, a("end_of_file")}]}
      text -> {:unify, [{codes, PrologEx.list(text |> chomp() |> no_cr() |> to_codes())}]}
    end
  end

  defbuiltin "read_line_to_codes", [stream, codes, rest] do
    case line(deref(stream)) do
      :eof ->
        {:unify, [{codes, rest}, {rest, []}]}

      # die letzte Zeile ohne \n: das Ende ist erreicht, Rest = [] (wie SWI)
      text ->
        if String.ends_with?(text, "\n"),
          do: {:unify, [{codes, PrologEx.list(to_codes(text), rest)}]},
          else: {:unify, [{codes, PrologEx.list(to_codes(text), rest)}, {rest, []}]}
    end
  end

  defbuiltin "read_line_to_chars", [stream, chars] do
    case line(deref(stream)) do
      :eof ->
        {:unify, [{chars, a("end_of_file")}]}

      text ->
        {:unify, [{chars, PrologEx.list(text |> chomp() |> String.trim("\r") |> to_chars())}]}
    end
  end

  # --- Streams ------------------------------------------------------------------

  defbuiltin "read_stream_to_codes", [stream, codes] do
    {:unify, [{codes, PrologEx.list(to_codes(rest_of(deref(stream))))}]}
  end

  defbuiltin "read_stream_to_codes", [stream, codes, rest] do
    {:unify, [{codes, PrologEx.list(to_codes(rest_of(deref(stream))), rest)}]}
  end

  # --- Dateien ------------------------------------------------------------------

  defbuiltin "read_file_to_codes", [file, codes, opts] do
    s = subst()
    tail = tail_opt(opts, s)
    {:unify, [{codes, PrologEx.list(to_codes(file_text(file, s)), tail)}]}
  end

  defbuiltin "read_file_to_chars", [file, chars, opts] do
    s = subst()
    _ = tail_opt(opts, s)
    {:unify, [{chars, PrologEx.list(to_chars(file_text(file, s)))}]}
  end

  # '$rdu_split'(+Optionen, -Rest, -LeseOptionen): tail(T) heraus (sonst
  # []), dazu die Optionen von read_term/3; der Rest wird übergangen
  @read_opts ~w(variables variable_names singletons syntax_errors double_quotes
                back_quotes module term_position subterm_positions comments)

  defbuiltin "$rdu_split", [opts, tail, ropts] do
    s = subst()
    os = opt_list!(opts, s)

    t =
      Enum.find_value(os, [], fn o ->
        case PrologEx.unmark_top(Store.walk(o, s)) do
          {:struct, "tail", [t]} -> t
          _ -> nil
        end
      end)

    rs =
      for o <- os,
          match?({:struct, n, [_]} when n in @read_opts, PrologEx.unmark_top(Store.walk(o, s))),
          do: o

    {:unify, [{tail, t}, {ropts, PrologEx.list(rs)}]}
  end

  def library do
    import PrologEx, only: [s: 2, v: 1, a: 1, rule: 2]
    [f, ts, os, st, tl, ro, t, ts1] = Enum.map(~w(F Ts Os S Tl Ro T Ts1), &v/1)

    %{
      "readutil" => [
        # read_file_to_terms/3: die Datei offen nur während des Lesens
        rule(s("read_file_to_terms", [f, ts, os]), [
          s("$rdu_split", [os, tl, ro]),
          s("setup_call_cleanup", [
            s("open", [f, a("read"), st]),
            s("$rdu_terms", [st, ts, tl, ro]),
            s("close", [st])
          ])
        ]),
        rule(s("$rdu_terms", [st, ts, tl, ro]), [
          s("read_term", [st, t, ro]),
          s(";", [
            s("->", [s("==", [t, a("end_of_file")]), s("=", [ts, tl])]),
            s(",", [s("=", [ts, [t | ts1]]), s("$rdu_terms", [st, ts1, tl, ro])])
          ])
        ])
      ]
    }
  end

  # --- Hilfen ---------------------------------------------------------------------

  # eine Zeile (mit \n) oder :eof (dann hinter dem Ende, wie get_code/2)
  defp line(st) do
    id = PIO.input!(st, :text)

    case PIO.pre_read(id, st) do
      :eof ->
        :eof

      _ ->
        case S.read_line(id) do
          :eof ->
            S.mark_past(id)
            :eof

          :invalid ->
            S.invalid_char!()

          text ->
            text
        end
    end
  end

  defp rest_of(st) do
    id = PIO.input!(st, :text)

    case PIO.pre_read(id, st) do
      :eof ->
        ""

      _ ->
        case S.read_rest(id) do
          :invalid ->
            S.invalid_char!()

          text ->
            S.mark_past(id)
            text
        end
    end
  end

  defp file_text(file, s) do
    path = PrologEx.Builtins.Filesex.text!(file, s)

    case File.read(path) do
      {:ok, bin} ->
        if String.valid?(bin), do: bin, else: S.invalid_char!()

      {:error, :enoent} ->
        Error.existence!("source_sink", PrologEx.resolve(file, s))

      {:error, _} ->
        Error.permission!("open", "source_sink", PrologEx.resolve(file, s))
    end
  end

  defp tail_opt(opts, s) do
    Enum.find_value(opt_list!(opts, s), [], fn o ->
      case PrologEx.unmark_top(Store.walk(o, s)) do
        {:struct, "tail", [t]} -> t
        _ -> nil
      end
    end)
  end

  defp opt_list!(l, s) do
    case PrologEx.Builtins.Lists.skip_list(l, s) do
      {_, []} -> collect(Store.walk(l, s), s)
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(l, s))
    end
  end

  defp collect(l, s) do
    case PrologEx.uncons(Store.walk(l, s)) do
      :empty -> []
      {:cons, h, t} -> [h | collect(t, s)]
    end
  end

  defp chomp(text), do: String.replace_suffix(text, "\n", "")
  defp no_cr(text), do: String.replace(text, "\r", "")
  defp to_codes(text), do: String.to_charlist(text)
  defp to_chars(text), do: for(<<c::utf8 <- text>>, do: a(<<c::utf8>>))
end
