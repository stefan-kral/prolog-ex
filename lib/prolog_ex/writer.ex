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
  #
  # Ohne Rekursion: descend/6 steigt in einen Term ab und legt für jede
  # Struktur einen Rahmen auf einen Stapel (was noch fehlt: weitere
  # Argumente, der rechte Operand, ")" ...); ret/3 bekommt das fertige Stück
  # eines Kindes, macht mit dem nächsten Kind weiter oder schließt den
  # Rahmen und gibt das Stück eine Ebene höher. Beide rufen sich nur
  # endrekursiv. Der Stapel liegt auf dem Heap: f(1,f(2,...)), a:-b,c,...,
  # ((1+2)+3)+..., - - - a, [[[...]]] oder g(1, g(2, ...), x) brauchen keinen
  # Stack, der mit der Tiefe wächst.
  # ---------------------------------------------------------------------

  defp w(t, max, role, d, o), do: descend(t, max, role, d, o, [])

  defp descend(_t, _max, _role, d, %{max_depth: m} = o, st) when m > 0 and d > m,
    do: ret(st, piece("..."), o)

  defp descend({tag, f, args}, max, _role, d, o, st) when tag in [:struct, :gstruct],
    do: compound(f, args, max, d, o, st)

  defp descend([_ | _] = l, _max, _role, d, o, st), do: list(l, d, o, st)
  defp descend({:glist, l}, _max, _role, d, o, st), do: list(l, d, o, st)
  defp descend(t, _max, role, _d, o, st), do: ret(st, leaf(t, role, o), o)

  # Variablen: Ränder Buchstabe/_ (für glue? zählt nur die Klasse)
  defp leaf({:var, n} = v, _role, o) do
    case o.var_names do
      %{^v => name} -> piece(name)
      _ -> {var_name(n), ?_, ?_}
    end
  end

  # Zahlen: vorn Ziffer oder -, hinten Ziffer
  defp leaf(n, _role, _o) when is_integer(n),
    do: {Integer.to_string(n), if(n < 0, do: ?-, else: ?0), ?0}

  defp leaf(f, _role, _o) when is_float(f) do
    text = format_float(f)
    {text, first(text), ?0}
  end

  defp leaf([], role, o), do: leaf({:atom, "[]"}, role, o)

  defp leaf({:atom, name}, role, o) do
    text = atom(name, o)

    if role == :operand and not o.ignore_ops and Map.has_key?(o.ops, name),
      do: paren(piece(text)),
      else: piece(text)
  end

  defp leaf(other, _role, _o), do: piece(inspect(other))

  defp var_name(n) when is_integer(n), do: "_G#{n}"
  defp var_name(n) when is_binary(n), do: n
  defp var_name({:attv, id}), do: "_V#{id}"
  defp var_name(n), do: inspect(n)

  # --- Strukturen ---------------------------------------------------------

  defp compound("{}", [x], _max, d, o, st) when not o.ignore_ops,
    do: descend(x, 1200, :arg, d + 1, o, [:curly | st])

  defp compound("$VAR", [n], _max, _d, %{numbervars: true} = o, st)
       when is_integer(n) and n >= 0 do
    letter = <<?A + rem(n, 26)>>
    ret(st, piece(if n >= 26, do: letter <> Integer.to_string(div(n, 26)), else: letter), o)
  end

  # Operator-Eintrag einmal holen (nicht in den Guards dreier Klauseln)
  defp compound(f, args, max, d, o, st) do
    entry = if o.ignore_ops, do: nil, else: Map.get(o.ops, f)

    case {args, entry} do
      {[l, r], %{infix: {p, type}}} ->
        {lp, rp} = infix_args(p, type)
        descend(l, lp, :operand, d + 1, o, [{:infix_l, f, p, max, r, rp, d} | st])

      {[x], %{prefix: {p, type}}} ->
        ap = if type == "fy", do: p, else: p - 1
        descend(x, ap, :operand, d + 1, o, [{:prefix, f, p, max} | st])

      {[x], %{postfix: {p, type}}} ->
        ap = if type == "yf", do: p, else: p - 1
        descend(x, ap, :operand, d + 1, o, [{:postfix, f, p, max} | st])

      {[], _} ->
        name = atom(f, o)
        ret(st, {[name, "()"], first(name), ?)}, o)

      {[a | rest], _} ->
        descend(a, 999, :arg, d + 1, o, [{:args, f, rest, [], d} | st])
    end
  end

  # Stück eines Kindes zurück an den obersten Rahmen
  defp ret([], piece, _o), do: piece

  defp ret([{:args, f, [], acc, _d} | st], {io, _, _}, o) do
    name = atom(f, o)
    ret(st, {[name, "(", :lists.reverse(acc, [io]), ")"], first(name), ?)}, o)
  end

  defp ret([{:args, f, [a | rest], acc, d} | st], {io, _, _}, o),
    do: descend(a, 999, :arg, d + 1, o, [{:args, f, rest, [o.comma, io | acc], d} | st])

  defp ret([{:infix_l, f, p, max, r, rp, d} | st], left, o),
    do: descend(r, rp, :operand, d + 1, o, [{:infix_r, f, p, max, left} | st])

  defp ret([{:infix_r, f, p, max, left} | st], right, o),
    do: ret(st, infix(f, p, max, left, right, o), o)

  defp ret([{:prefix, f, p, max} | st], arg, o), do: ret(st, prefix(f, p, max, arg, o), o)

  defp ret([{:postfix, f, p, max} | st], {aio, af, al}, o) do
    op = atom(f, o)
    sep = if alpha?(op) or glue?(al, first(op)), do: " ", else: ""
    ret(st, wrap({[aio, sep, op], af || first(op), last(op)}, p, max), o)
  end

  defp ret([:curly | st], {io, _, _}, o), do: ret(st, {["{", io, "}"], ?{, ?}}, o)

  defp ret([{:list, t, n, acc, d} | st], {io, _, _}, o), do: list_next(t, n, [io | acc], d, o, st)

  defp ret([{:tail, acc} | st], {io, _, _}, o),
    do: ret(st, {["[", :lists.reverse(acc, ["|", io]), "]"], ?[, ?]}, o)

  defp infix(f, p, max, {lio, lf, ll}, {rio, rf, rl}, o) do
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

  defp prefix(f, p, max, arg, o) do
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

  defp infix_args(p, "xfx"), do: {p - 1, p - 1}
  defp infix_args(p, "xfy"), do: {p - 1, p}
  defp infix_args(p, "yfx"), do: {p, p - 1}

  defp wrap(t, p, max) when p > max, do: paren(t)
  defp wrap(t, _p, _max), do: t

  # --- Listen -------------------------------------------------------------

  defp list(l, d, %{strings: true} = o, st) do
    case chars(l, []) do
      {:ok, cs} -> ret(st, {[?", Enum.map(cs, &escape(&1, ?")), ?"], ?", ?"}, o)
      :no -> list_first(l, d, o, st)
    end
  end

  defp list(l, d, o, st), do: list_first(l, d, o, st)

  defp list_first([h | t], d, o, st),
    do: descend(h, 999, :arg, d + 1, o, [{:list, t, 1, [], d} | st])

  # nach dem n-ten Element (acc: geschriebene Elemente und Kommas, umgekehrt);
  # bei max_depth nach n Elementen "|..."
  defp list_next(t, n, acc, _d, %{max_depth: m} = o, st) when m > 0 and n >= m and t != [],
    do: ret(st, {["[", :lists.reverse(acc, ["|..."]), "]"], ?[, ?]}, o)

  defp list_next([], _n, acc, _d, o, st),
    do: ret(st, {["[", :lists.reverse(acc), "]"], ?[, ?]}, o)

  defp list_next([h | t], n, acc, d, o, st),
    do: descend(h, 999, :arg, d + 1, o, [{:list, t, n + 1, [o.comma | acc], d} | st])

  defp list_next({:glist, l}, n, acc, d, o, st), do: list_next(l, n, acc, d, o, st)

  defp list_next(t, _n, acc, d, o, st),
    do: descend(t, 999, :arg, d + 1, o, [{:tail, acc} | st])

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
