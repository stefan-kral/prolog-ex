defmodule PrologEx.Writer do
  @moduledoc """
  Terme als Text, mit Operatoren (ISO 7.10.5), im Stil von gprolog (dem
  ISO-konformen Writer, mit dem wir auch lesen):

      1+2*3   (1+2)*3   a:-b,c   - (1)   - -1   a- -b   \\+ (a,b)
      a mod b   (-) mod (+)   f((a:-b))   [a,b|T]   {a,b}

  Regeln:

    * Operanden mit höherer Priorität als erlaubt kommen in Klammern
      (links bei xfx/xfy P-1, bei yfx P; rechts umgekehrt; Argumente von
      Strukturen und Listenelemente höchstens 999).
    * Ein Atom, das ein Operator ist, kommt als Operand in Klammern:
      `a-(mod)`, `- (-)`; als Argument nicht: `f(:-,-)`.
    * Präfix-`-` vor einer Zahl: Operand in Klammern, `- (1)`,
      `- (1^2)` – sonst läse man eine negative Zahl (`+1` dagegen ist
      `+(1)`, wie ISO).
    * Nach einem alphanumerischen Präfix-Operator immer ein Leerzeichen:
      `dynamic -a` (gprolog schreibt `dynamic-a`, was andere Systeme als
      Infix lesen könnten).
    * Nach einem Präfix-Operator vor `(` ein Leerzeichen: `- (a,b)`;
      ebenso zwischen zwei Zeichen, die sonst zu einem Token verschmölzen
      (`1- -1`, `a- -b`, `a mod b`).

  Optionen:

    * `quoted: true` – Atome, wo nötig, in Hochkommas (`writeq/1`).
    * `ignore_ops: true` – kanonisch, `+(1,2)` (`write_canonical/1`).
    * `numbervars: true` – `'$VAR'(N)` als Variablenname `A`, `B`, ...,
      `Z`, `A1`, ...
    * `strings: true` – Listen aus Zeichen als `"..."` (bei
      `double_quotes=chars`).
    * `spacing: :next_argument` – Leerzeichen nach Kommas (Argumente,
      Listen, Komma-Operator): Stil der Toplevel-Antworten.
    * `max_depth: n` – tiefer geschachtelte Terme als `...`, Listen nach
      n Elementen mit `|...` (0: unbegrenzt).
    * `priority: p` – höchste Priorität des ganzen Terms (Standard 1200;
      Antworten `X = T` schreiben T mit 699).
    * `operand: true` – der ganze Term ist Operand eines Operators
      (Operator-Atome dann in Klammern: `X = (-)`).
    * `variable_names: %{var => "Name"}` – Variablen mit diesen Namen
      (ISO `variable_names/1`).
    * `ops:` – Operatortabelle (Standard: die der Sitzung, `PrologEx.Ops`).
  """

  import PrologEx, only: [format_float: 1]
  alias PrologEx.Ops

  def format(t, opts \\ []) do
    o = %{
      quoted: Keyword.get(opts, :quoted, false),
      ignore_ops: Keyword.get(opts, :ignore_ops, false),
      numbervars: Keyword.get(opts, :numbervars, false),
      strings: Keyword.get(opts, :strings, false),
      comma: if(Keyword.get(opts, :spacing) == :next_argument, do: ", ", else: ","),
      max_depth: Keyword.get(opts, :max_depth, 0),
      var_names: Keyword.get(opts, :variable_names, %{}),
      ops: Keyword.get_lazy(opts, :ops, &Ops.table/0)
    }

    role = if Keyword.get(opts, :operand, false), do: :operand, else: :arg
    {io, _, _} = w(t, Keyword.get(opts, :priority, 1200), role, 1, o)
    IO.iodata_to_binary(io)
  end

  @doc "Optionen für Toplevel-Antworten, writeq und print"
  def answer_opts do
    [
      quoted: true,
      numbervars: true,
      spacing: :next_argument,
      strings: PrologEx.Flags.get("double_quotes") == {:atom, "chars"}
    ]
  end

  # ---------------------------------------------------------------------
  # Ein Stück Text: {iodata, erstes Zeichen, letztes Zeichen} – die Ränder
  # entscheiden, ob zwischen zwei Stücken ein Leerzeichen nötig ist.
  # w(Term, höchste Priorität, Rolle, Tiefe, Optionen); Rolle :operand,
  # wenn der Term Operand eines Operators ist, sonst :arg.
  # ---------------------------------------------------------------------

  defp w(_t, _max, _role, d, %{max_depth: m}) when m > 0 and d > m, do: piece("...")

  # Variablen: Ränder Buchstabe/_ (für glue? zählt nur die Klasse)
  defp w({:var, n} = v, _max, _role, _d, o) do
    case o.var_names do
      %{^v => name} -> piece(name)
      _ -> {var_name(n), ?_, ?_}
    end
  end

  # Zahlen: vorn Ziffer oder -, hinten Ziffer
  defp w(n, _max, _role, _d, _o) when is_integer(n),
    do: {Integer.to_string(n), if(n < 0, do: ?-, else: ?0), ?0}

  defp w(f, _max, _role, _d, _o) when is_float(f) do
    text = format_float(f)
    {text, first(text), ?0}
  end

  defp w([], max, role, d, o), do: w({:atom, "[]"}, max, role, d, o)

  defp w({:atom, name}, _max, role, _d, o) do
    text = atom(name, o)

    if role == :operand and not o.ignore_ops and Map.has_key?(o.ops, name),
      do: paren(piece(text)),
      else: piece(text)
  end

  defp w([_ | _] = l, _max, _role, d, o), do: list(l, d, o)
  defp w({:glist, l}, _max, _role, d, o), do: list(l, d, o)

  defp w({tag, f, args}, max, role, d, o) when tag in [:struct, :gstruct],
    do: compound(f, args, max, role, d, o)

  defp w(other, _max, _role, _d, _o), do: piece(inspect(other))

  defp var_name(n) when is_integer(n), do: "_G#{n}"
  defp var_name(n) when is_binary(n), do: n
  defp var_name({:attv, id}), do: "_V#{id}"
  defp var_name(n), do: inspect(n)

  # --- Strukturen ---------------------------------------------------------

  defp compound("{}", [x], _max, _role, d, o) when not o.ignore_ops do
    {io, _, _} = w(x, 1200, :arg, d + 1, o)
    {["{", io, "}"], ?{, ?}}
  end

  defp compound("$VAR", [n], _max, _role, _d, %{numbervars: true})
       when is_integer(n) and n >= 0 do
    letter = <<?A + rem(n, 26)>>
    piece(if n >= 26, do: letter <> Integer.to_string(div(n, 26)), else: letter)
  end

  # Operator-Eintrag einmal holen (nicht in den Guards dreier Klauseln)
  defp compound(f, args, max, _role, d, o) do
    entry = if o.ignore_ops, do: nil, else: Map.get(o.ops, f)

    case {args, entry} do
      {[l, r], %{infix: inf}} -> infix(f, inf, l, r, max, d, o)
      {[x], %{prefix: pre}} -> prefix(f, pre, x, max, d, o)
      {[x], %{postfix: post}} -> postfix(f, post, x, max, d, o)
      _ -> canonical(f, args, d, o)
    end
  end

  defp infix(f, {p, type}, l, r, max, d, o) do
    {lp, rp} = infix_args(p, type)
    {lio, lf, ll} = w(l, lp, :operand, d + 1, o)
    {rio, rf, rl} = w(r, rp, :operand, d + 1, o)

    op =
      case f do
        "," -> o.comma
        "|" -> "|"
        _ -> atom(f, o)
      end

    t =
      if alpha?(op) do
        {[lio, " ", op, " ", rio], lf, rl}
      else
        of = first(op)
        ol = last(op)
        s1 = if glue?(ll, of), do: " ", else: ""
        s2 = if glue?(ol, rf), do: " ", else: ""
        {[lio, s1, op, s2, rio], lf || of, rl || ol}
      end

    wrap(t, p, max)
  end

  defp prefix(f, {p, type}, x, max, d, o) do
    ap = if type == "fy", do: p, else: p - 1
    arg = w(x, ap, :operand, d + 1, o)

    # - (1), - (1^2): sonst läse man eine negative Zahl (+1 ist keine
    # Zahl, sondern +(1) – wie ISO und gprolog)
    {aio, af, al} =
      if f == "-" and digit?(elem(arg, 1)),
        do: paren(arg),
        else: arg

    op = atom(f, o)

    # Leerzeichen: vor "(" (sonst Funktionsschreibweise), nach einem
    # alphanumerischen Operator, und wo Zeichen verschmölzen
    sep = if af == ?( or alpha?(op) or glue?(last(op), af), do: " ", else: ""
    wrap({[op, sep, aio], first(op), al || last(op)}, p, max)
  end

  defp postfix(f, {p, type}, x, max, d, o) do
    ap = if type == "yf", do: p, else: p - 1
    {aio, af, al} = w(x, ap, :operand, d + 1, o)
    op = atom(f, o)
    sep = if alpha?(op) or glue?(al, first(op)), do: " ", else: ""
    wrap({[aio, sep, op], af || first(op), last(op)}, p, max)
  end

  defp canonical(f, args, d, o) do
    items = Enum.map(args, fn a -> elem(w(a, 999, :arg, d + 1, o), 0) end)
    name = atom(f, o)
    {[name, "(", Enum.intersperse(items, o.comma), ")"], first(name), ?)}
  end

  defp infix_args(p, "xfx"), do: {p - 1, p - 1}
  defp infix_args(p, "xfy"), do: {p - 1, p}
  defp infix_args(p, "yfx"), do: {p, p - 1}

  defp wrap(t, p, max) when p > max, do: paren(t)
  defp wrap(t, _p, _max), do: t

  # --- Listen -------------------------------------------------------------

  defp list(l, d, %{strings: true} = o) do
    case chars(l, []) do
      {:ok, cs} -> {[?", Enum.map(cs, &escape(&1, ?")), ?"], ?", ?"}
      :no -> plain_list(l, d, o)
    end
  end

  defp list(l, d, o), do: plain_list(l, d, o)

  defp plain_list(l, d, o) do
    {["[", items(l, [], 1, d, o), "]"], ?[, ?]}
  end

  # endrekursiv entlang der Liste, Akkumulator in umgekehrter Reihenfolge
  defp items([h | t], acc, n, d, o) do
    {io, _, _} = w(h, 999, :arg, d + 1, o)

    cond do
      o.max_depth > 0 and n >= o.max_depth and t != [] ->
        Enum.reverse(acc, [io, "|..."])

      true ->
        case t do
          [] -> Enum.reverse(acc, [io])
          [_ | _] -> items(t, [o.comma, io | acc], n + 1, d, o)
          {:glist, l} -> items(l, [o.comma, io | acc], n + 1, d, o)
          _ -> Enum.reverse(acc, [io, "|", elem(w(t, 999, :arg, d + 1, o), 0)])
        end
    end
  end

  # echte Liste aus Ein-Zeichen-Atomen?
  defp chars([{:atom, c} | t], acc) do
    if single_char?(c), do: chars(t, [c | acc]), else: :no
  end

  defp chars({:glist, l}, acc), do: chars(l, acc)
  defp chars([], [_ | _] = acc), do: {:ok, Enum.reverse(acc)}
  defp chars(_, _), do: :no

  defp single_char?(c), do: match?([_], String.to_charlist(c))

  # --- Stücke zusammensetzen -------------------------------------------------

  defp piece(text), do: {text, first(text), last(text)}

  defp paren({io, _, _}), do: {["(", io, ")"], ?(, ?)}

  defp first(<<c, _::binary>>) when c < 128, do: c
  defp first(<<c::utf8, _::binary>>), do: c
  defp first(""), do: nil

  defp last(""), do: nil

  # letztes Zeichen: bei ASCII das letzte Byte (String.last zerlegte in
  # Grapheme – zu teuer für jedes Stück)
  defp last(s) do
    case :binary.last(s) do
      b when b < 128 -> b
      _ -> s |> String.last() |> first()
    end
  end

  @symbol ~c"#$&*+-./:<=>?@^~\\"

  defp glue?(a, b) when is_nil(a) or is_nil(b), do: false

  defp glue?(a, b),
    do: (alnum?(a) and alnum?(b)) or (symbol?(a) and symbol?(b)) or (digit?(a) and b == ?')

  # als Guards: zur Übersetzungszeit zu Vergleichen aufgelöst
  defp symbol?(c) when c in @symbol, do: true
  defp symbol?(_), do: false

  defp alnum?(c) when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_, do: true
  defp alnum?(_), do: false

  defp digit?(c) when is_integer(c) and c in ?0..?9, do: true
  defp digit?(_), do: false

  # alphanumerischer Operator (mod, is, dynamic, ...)
  defp alpha?(text) when is_binary(text), do: text != "" and lower?(first(text))
  defp alpha?(_), do: false

  # ---------------------------------------------------------------------
  # Atome
  # ---------------------------------------------------------------------

  @doc "Atomname, bei quoted: true wenn nötig in Hochkommas"
  def atom(name, %{quoted: false}), do: name

  def atom(name, _o),
    do: if(needs_quotes?(name), do: "'" <> escape_text(name, ?') <> "'", else: name)

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

  # klein beginnend, dann Buchstaben, Ziffern, _ (Bytes: Nicht-ASCII nie)
  defp letter_atom?(<<c, rest::binary>>) when c in ?a..?z, do: alnum_bytes?(rest)
  defp letter_atom?(_), do: false

  defp alnum_bytes?(<<c, rest::binary>>)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_,
       do: alnum_bytes?(rest)

  defp alnum_bytes?(<<>>), do: true
  defp alnum_bytes?(_), do: false

  # nur Symbolzeichen; "." allein und Kommentaranfänge brauchen Hochkommas
  defp graphic_atom?(name),
    do: name != "." and not String.starts_with?(name, "/*") and graphic_bytes?(name)

  defp graphic_bytes?(<<c, rest::binary>>) when c in @graphic, do: graphic_bytes?(rest)
  defp graphic_bytes?(<<>>), do: true
  defp graphic_bytes?(_), do: false

  # Nur ASCII ungequotet: der gprolog-Reader liest Nicht-ASCII nur in
  # Hochkommas (SWI würde 'äb' ohne schreiben)
  defp lower?(c), do: is_integer(c) and c in ?a..?z

  defp escape_text(text, q), do: text |> escape(q) |> IO.iodata_to_binary()

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
