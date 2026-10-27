defmodule PrologEx.TermScanner do
  @moduledoc """
  Findet das Ende des nächsten Terms in einem Text (für read/1 von einem
  Stream): das Endezeichen `.` – ein einzelner Punkt, gefolgt von Leerraum,
  `%` oder dem Dateiende – außerhalb von Quotes (`'...'`, `"..."`, `` `...` ``
  mit Escapes und verdoppelten Quotes), Kommentaren (`% ...`, `/* ... */`),
  Zeichencodes (`0'c`, `0'''`, `0'\\n`) und Symbolfolgen (`=..`, `...`).

  `scan(text, eof?)`:

    * `{:end, n}` – die ersten n Bytes sind der Term samt Punkt; das
      folgende Leerraumzeichen bleibt im Stream (ISO 8.14.1.4: nach
      `read` auf "term1. term2." steht noch " term2." an),
    * `:empty` – bis zum Dateiende nur Leerraum und Kommentare,
    * `{:eof_inside, n}` – Dateiende mitten in einem Term (Syntaxfehler),
    * `:more` – der Text reicht nicht, es muss nachgelesen werden.

  Den Term selbst liest dann gprolog; hier wird nur die Grenze gesucht.
  """

  @symbol ~c"#$&*+-./:<=>?@^~\\\\"
  @layout [?\s, ?\t, ?\n, ?\r, ?\f, ?\v]

  def scan(text, eof?), do: scan(text, 0, false, eof?)

  defp scan(text, i, started, eof?) when i >= byte_size(text) do
    cond do
      not eof? -> :more
      started -> {:eof_inside, i}
      true -> :empty
    end
  end

  defp scan(text, i, started, eof?) do
    c = :binary.at(text, i)

    cond do
      c in @layout ->
        scan(text, i + 1, started, eof?)

      c == ?% ->
        case :binary.match(text, "\n", scope: {i, byte_size(text) - i}) do
          {p, 1} -> scan(text, p + 1, started, eof?)
          :nomatch -> scan(text, byte_size(text), started, eof?)
        end

      c == ?/ and at(text, i + 1) == ?* ->
        case :binary.match(text, "*/", scope: {i + 2, byte_size(text) - i - 2}) do
          {p, 2} -> scan(text, p + 2, started, eof?)
          :nomatch -> if eof?, do: {:eof_inside, byte_size(text)}, else: :more
        end

      c in [?', ?", ?`] ->
        case quoted(text, i + 1, c) do
          :more -> if eof?, do: {:eof_inside, byte_size(text)}, else: :more
          j -> scan(text, j, true, eof?)
        end

      c in ?0..?9 ->
        number(text, i, eof?)

      c in ?a..?z or c in ?A..?Z or c == ?_ ->
        scan(text, alnum_end(text, i), true, eof?)

      c in @symbol ->
        j = symbol_end(text, i)

        cond do
          j - i == 1 and c == ?. ->
            # Ende, wenn danach Leerraum, % oder das Dateiende kommt
            case at(text, j) do
              nil -> if eof?, do: {:end, j}, else: :more
              # das Layoutzeichen bleibt im Stream (ISO 6.4.8, 8.14.1.4)
              n when n in @layout -> {:end, j}
              ?% -> {:end, j}
              _ -> scan(text, j, true, eof?)
            end

          j >= byte_size(text) and not eof? ->
            # die Symbolfolge könnte weitergehen
            :more

          true ->
            scan(text, j, true, eof?)
        end

      true ->
        scan(text, i + 1, true, eof?)
    end
  end

  defp at(text, i) when i < byte_size(text), do: :binary.at(text, i)
  defp at(_text, _i), do: nil

  # Ende eines gequoteten Tokens ab Position j (nach dem öffnenden Quote)
  defp quoted(text, j, q) do
    case at(text, j) do
      nil ->
        :more

      ^q ->
        if at(text, j + 1) == q, do: quoted(text, j + 2, q), else: j + 1

      ?\\ ->
        if at(text, j + 1) == nil, do: :more, else: quoted(text, j + 2, q)

      _ ->
        quoted(text, j + 1, q)
    end
  end

  # Zahl ab i; 0'c ist ein Zeichencode (das Quote beginnt kein Atom)
  defp number(text, i, eof?) do
    j = alnum_end(text, i)

    if j == i + 1 and :binary.at(text, i) == ?0 and at(text, j) == ?' do
      case char_code_end(text, j + 1) do
        :more -> if eof?, do: {:eof_inside, byte_size(text)}, else: :more
        k -> scan(text, k, true, eof?)
      end
    else
      scan(text, j, true, eof?)
    end
  end

  # nach 0': '' | \Escape | ein Zeichen
  defp char_code_end(text, k) do
    case at(text, k) do
      nil ->
        :more

      ?' ->
        if at(text, k + 1) == ?', do: k + 2, else: k + 1

      ?\\ ->
        case at(text, k + 1) do
          nil ->
            :more

          e when e == ?x or e in ?0..?7 ->
            # \x41\ und \101\ bis zum schließenden Backslash
            case :binary.match(text, "\\", scope: {k + 2, byte_size(text) - k - 2}) do
              {p, 1} -> p + 1
              :nomatch -> :more
            end

          _ ->
            k + 2
        end

      _ ->
        next_char(text, k)
    end
  end

  defp next_char(text, k) do
    case binary_part(text, k, byte_size(text) - k) do
      <<c::utf8, _::binary>> -> k + byte_size(<<c::utf8>>)
      _ -> k + 1
    end
  end

  defp alnum_end(text, i) do
    case at(text, i) do
      c when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ -> alnum_end(text, i + 1)
      _ -> i
    end
  end

  defp symbol_end(text, i) do
    case at(text, i) do
      c when c in @symbol -> symbol_end(text, i + 1)
      _ -> i
    end
  end
end
