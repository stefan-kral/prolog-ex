defmodule PrologEx.Writer do
  @moduledoc """
  Terme als Text (noch ohne Operator-Schreibweise: `-(1, 2)`).

  Optionen:

    * `quoted: true` – wie `writeq/1`: Atome, die sonst nicht als dasselbe
      Atom gelesen würden, in Hochkommas (`'1'`, `'hello world'`, `'.'`,
      `','`, `''`), mit Escapes (`'it\\'s'`, `'a\\nb'`). Ohne: wie `write/1`.
    * `strings: true` – nicht leere Listen aus Zeichen (Ein-Zeichen-Atomen)
      als `"..."`, wie Scryer bei `double_quotes=chars`. Mit `quoted`
      gedacht: so liest sich die Ausgabe wieder als dieselbe Liste.

  Der Toplevel nutzt beides (bei `double_quotes=chars`), `writeq/1` und
  `print/1` ebenso, `write/1` keines.
  """

  import PrologEx, only: [format_float: 1]

  def format(t, opts \\ []) do
    o = %{quoted: Keyword.get(opts, :quoted, false), strings: Keyword.get(opts, :strings, false)}
    t |> fmt(o) |> IO.iodata_to_binary()
  end

  @doc "Optionen für Antworten/writeq je nach double_quotes-Flag"
  def answer_opts do
    [quoted: true, strings: PrologEx.Flags.get("double_quotes") == {:atom, "chars"}]
  end

  defp fmt({:var, n}, _o) when is_integer(n), do: ["_G", Integer.to_string(n)]
  defp fmt({:var, n}, _o) when is_binary(n), do: n
  defp fmt({:var, {:attv, id}}, _o), do: ["_V", Integer.to_string(id)]
  defp fmt({:var, n}, _o), do: inspect(n)
  defp fmt({:atom, n}, o), do: atom(n, o)
  defp fmt(n, _o) when is_integer(n), do: Integer.to_string(n)
  defp fmt(f, _o) when is_float(f), do: format_float(f)
  defp fmt([], _o), do: "[]"

  defp fmt([_ | _] = l, o), do: list(l, o)
  defp fmt({:glist, l}, o), do: list(l, o)

  defp fmt({tag, f, args}, o) when tag in [:struct, :gstruct],
    do: [atom(f, o), "(", Enum.map_intersperse(args, ", ", &fmt(&1, o)), ")"]

  defp fmt(other, _o), do: inspect(other)

  defp list(l, %{strings: true} = o) do
    case chars(l, []) do
      {:ok, cs} -> [?", Enum.map(cs, &escape(&1, ?")), ?"]
      :no -> ["[", items(l, [], o), "]"]
    end
  end

  defp list(l, o), do: ["[", items(l, [], o), "]"]

  # echte Liste aus Ein-Zeichen-Atomen?
  defp chars([{:atom, c} | t], acc) do
    if single_char?(c), do: chars(t, [c | acc]), else: :no
  end

  defp chars({:glist, l}, acc), do: chars(l, acc)
  defp chars([], [_ | _] = acc), do: {:ok, Enum.reverse(acc)}
  defp chars(_, _), do: :no

  defp single_char?(c), do: match?([_], String.to_charlist(c))

  # endrekursiv entlang der Liste, Akkumulator in umgekehrter Reihenfolge
  defp items([h | t], acc, o) do
    case t do
      [] -> Enum.reverse(acc, [fmt(h, o)])
      [_ | _] -> items(t, [", ", fmt(h, o) | acc], o)
      {:glist, l} -> items(l, [", ", fmt(h, o) | acc], o)
      _ -> Enum.reverse(acc, [fmt(h, o), " | ", fmt(t, o)])
    end
  end

  # ---------------------------------------------------------------------
  # Atome
  # ---------------------------------------------------------------------

  @doc "Atomname, bei quoted: true wenn nötig in Hochkommas"
  def atom(name, %{quoted: false}), do: name
  def atom(name, _o), do: if(needs_quotes?(name), do: [?', escape(name, ?'), ?'], else: name)

  @graphic ~c"#$&*+-./:<=>?@^~\\"

  @doc "Muss das Atom in writeq-Ausgabe gequotet werden?"
  def needs_quotes?(name) do
    cond do
      name in ["[]", "{}", "!", ";"] -> false
      name == "" -> true
      letter_atom?(name) -> false
      graphic_atom?(name) -> false
      true -> true
    end
  end

  # klein beginnend, dann Buchstaben, Ziffern, _
  defp letter_atom?(name) do
    [first | rest] = String.to_charlist(name)
    lower?(first) and Enum.all?(rest, &alnum?/1)
  end

  # nur Symbolzeichen; "." allein und Kommentaranfänge brauchen Hochkommas
  defp graphic_atom?(name) do
    cs = String.to_charlist(name)

    Enum.all?(cs, &(&1 in @graphic)) and name != "." and not String.starts_with?(name, "/*")
  end

  # Nur ASCII ungequotet: der gprolog-Reader liest Nicht-ASCII nur in
  # Hochkommas (SWI würde 'äb' ohne schreiben)
  defp lower?(c), do: c in ?a..?z
  defp alnum?(c), do: c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_

  # Escapes in gequoteten Atomen und Strings
  defp escape(text, q) do
    for <<c::utf8 <- text>> do
      case c do
        ^q -> [?\\, q]
        ?\\ -> "\\\\"
        ?\n -> "\\n"
        ?\t -> "\\t"
        ?\r -> "\\r"
        7 -> "\\a"
        ?\b -> "\\b"
        ?\f -> "\\f"
        ?\v -> "\\v"
        0 -> "\\0\\"
        c when c < 32 or c == 127 -> ["\\x", Integer.to_string(c, 16), "\\"]
        c -> <<c::utf8>>
      end
    end
  end
end
