defmodule PrologEx.Builtins.Format do
  @moduledoc """
  Formatierte Ausgabe: `format/1,2,3` nach PIP 0110 (Prolog Implementers
  Forum, "Formatted output"; wie SWI, SICStus, GNU Prolog im gemeinsamen
  Kern).

  `format(Stream, Control, Args)`: Control ist ein Atom, eine Code- oder
  Zeichenliste; Args eine vollständige Liste. Die Ausgabe entsteht ganz im
  Speicher und wird am Ende auf einmal geschrieben – ein Fehler unterwegs
  schreibt also nichts.

  Direktiven `~NX` (N: Ziffern, `*` = nächstes Argument, ein Ausdruck, oder
  `` `c `` = Zeichencode von c):

    * Terme: `~w` write, `~p` print (mit portray/1), `~q` writeq,
      `~k` write_canonical, `~W` write_term(Term, Optionen) – zwei Argumente
    * Text: `~a` Atom, `~Nc` Code N-mal, `~Ns` Code-/Zeichenliste oder Atom,
      auf N Zeichen aufgefüllt oder gekürzt
    * Zahlen (Argumente werden ausgewertet): `~Nd` Ganzzahl mit N
      Nachkommastellen (`~1d`: 123 -> 12.3), `~ND` mit Tausenderkommas,
      `~Nr`/`~NR` zur Basis N (2..36, Standard 8), `~Ne` `~NE` `~Nf` `~Ng`
      `~NG` wie C printf (Standard 6 Stellen)
    * `~Nn` N Zeilenwechsel, `~N` Zeilenwechsel, außer am Zeilenanfang,
      `~i` Argument überspringen, `~~` eine Tilde
    * Spalten: `~|` bzw. `~N|` Spaltengrenze (an Spalte N), `~N+` Grenze N
      Zeichen nach der vorigen (Standard 8), `~Nt` Füllstelle (Zeichen N,
      Standard Leerzeichen). Der Platz bis zur Grenze verteilt sich auf die
      Füllstellen, spätere bekommen das übrige Zeichen; ohne Füllstelle wird
      rechts aufgefüllt. Ist der Text länger, wird nichts abgeschnitten.

  Fehler: `instantiation_error` und `type_error` wie bei den entsprechenden
  Prädikaten, `type_error(evaluable, F/N)` aus der Arithmetik;
  Formatfehler (unbekannte Direktive, zu wenige oder zu viele Argumente,
  Basis außerhalb 2..36) als `domain_error(format, Grund)`.
  """
  use PrologEx.Builtin
  import Bitwise
  alias PrologEx.{Arith, Error, Writer}
  alias PrologEx.Builtins.{Core, Lists}
  alias PrologEx.Builtins.IO, as: PIO
  alias PrologEx.Stream, as: S

  defbuiltin "format", [f] do
    format(PIO.current_out!(:text), f, [], subst())
  end

  # format/2,3 nicht geschützt: nach use_module(library(format)) gelten
  # Scryers (format_//2)
  defbuiltin "format", [f, args], protected: false do
    format(PIO.current_out!(:text), f, args, subst())
  end

  defbuiltin "format", [stream, f, args], protected: false do
    format(PIO.output!(deref(stream), :text), f, args, subst())
  end

  @doc false
  def format(id, f, args, s) do
    ctl = control!(f, s)
    as = args!(args, s)
    st = %{done: [], pend: [], col: S.get(id).line_pos, start: S.get(id).line_pos}
    st = run(ctl, as, st, s)
    S.put_text(id, finish(st))
    :ok
  end

  # --- Argumente prüfen ---------------------------------------------------

  defp control!(f, s) do
    case PrologEx.walk(f, s) do
      {:var, _} ->
        Error.instantiation!()

      [] ->
        []

      {:atom, name} ->
        String.to_charlist(name)

      l when is_list(l) or (is_tuple(l) and elem(l, 0) == :glist) ->
        text_codes!(l, s, fn -> Error.type!("text", PrologEx.resolve(f, s)) end)

      other ->
        Error.type!("text", PrologEx.resolve(other, s))
    end
  end

  defp args!(args, s) do
    case Lists.skip_list(args, s) do
      {_, []} -> Lists.items(args, s)
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(args, s))
    end
  end

  # Code- oder Zeichenliste -> Codes; partielle Liste: instantiation_error
  defp text_codes!(l, s, bad) do
    case Lists.skip_list(l, s) do
      {_, []} -> :ok
      {_, {:var, _}} -> Error.instantiation!()
      _ -> bad.()
    end

    for x <- Lists.items(l, s) do
      case PrologEx.walk(x, s) do
        {:var, _} -> Error.instantiation!()
        c when is_integer(c) and c >= 0 and c <= 0x10FFFF -> c
        {:atom, ch} -> single_char!(ch, bad)
        _ -> bad.()
      end
    end
  end

  defp single_char!(ch, bad) do
    case String.to_charlist(ch) do
      [c] -> c
      _ -> bad.()
    end
  end

  # --- Ablauf ---------------------------------------------------------------

  defp run([], [], st, _s), do: st
  defp run([], [_ | _] = rest, _st, s), do: too_many!(rest, s)

  defp run([?~ | rest], args, st, s) do
    {n, rest, args} = num_arg(rest, args, s)

    case rest do
      [d | rest] -> directive(d, n, rest, args, st, s)
      [] -> format_error!("truncated format directive")
    end
  end

  defp run(ctl, args, st, s) do
    {text, rest} = Enum.split_while(ctl, &(&1 != ?~))
    run(rest, args, emit(st, List.to_string(text)), s)
  end

  # Zahl vor der Direktive: Ziffern, * (nächstes Argument) oder `c
  defp num_arg([?* | rest], args, s) do
    {a, args} = next(args)
    {nonneg!(a, s), rest, args}
  end

  defp num_arg([?`, c | rest], args, _s), do: {c, rest, args}

  defp num_arg([c | _] = ctl, args, _s) when c in ?0..?9 do
    {digits, rest} = Enum.split_while(ctl, &(&1 in ?0..?9))
    {List.to_integer(digits), rest, args}
  end

  defp num_arg(ctl, args, _s), do: {nil, ctl, args}

  defp next([a | rest]), do: {a, rest}
  defp next([]), do: format_error!("not enough arguments")

  # --- Direktiven -----------------------------------------------------------

  defp directive(?~, _n, rest, args, st, s), do: run(rest, args, emit(st, "~"), s)

  defp directive(d, _n, rest, args, st, s) when d in [?w, ?p, ?q, ?k] do
    {t, args} = next(args)
    run(rest, args, emit(st, write_text(d, t, s)), s)
  end

  defp directive(?W, _n, rest, args, st, s) do
    {t, args} = next(args)
    {opts, args} = next(args)
    text = Writer.format(PrologEx.resolve(t, s), Core.write_options(opts, s))
    run(rest, args, emit(st, text), s)
  end

  defp directive(?a, _n, rest, args, st, s) do
    {t, args} = next(args)

    name =
      case PrologEx.walk(t, s) do
        {:var, _} -> Error.instantiation!()
        [] -> "[]"
        {:atom, n} -> n
        other -> Error.type!("atom", PrologEx.resolve(other, s))
      end

    run(rest, args, emit(st, name), s)
  end

  defp directive(?c, n, rest, args, st, s) do
    {t, args} = next(args)
    code = int!(t, s)

    unless code >= 0 and code <= 0x10FFFF,
      do: Error.representation!("character_code")

    run(rest, args, emit(st, String.duplicate(<<code::utf8>>, n || 1)), s)
  end

  defp directive(?s, n, rest, args, st, s) do
    {t, args} = next(args)

    text =
      case PrologEx.walk(t, s) do
        {:var, _} ->
          Error.instantiation!()

        {:atom, name} ->
          name

        [] ->
          ""

        l ->
          List.to_string(text_codes!(l, s, fn -> Error.type!("text", PrologEx.resolve(t, s)) end))
      end

    text =
      case n do
        nil ->
          text

        n ->
          len = String.length(text)
          if len >= n, do: String.slice(text, 0, n), else: text <> String.duplicate(" ", n - len)
      end

    run(rest, args, emit(st, text), s)
  end

  defp directive(d, n, rest, args, st, s) when d in [?d, ?D] do
    {t, args} = next(args)
    run(rest, args, emit(st, decimal(int!(t, s), n || 0, d == ?D)), s)
  end

  defp directive(d, n, rest, args, st, s) when d in [?r, ?R] do
    radix = n || 8
    unless radix in 2..36, do: format_error!("radix not in 2..36")
    {t, args} = next(args)
    text = Integer.to_string(int!(t, s), radix)
    text = if d == ?r, do: String.downcase(text), else: String.upcase(text)
    run(rest, args, emit(st, text), s)
  end

  defp directive(d, n, rest, args, st, s) when d in [?e, ?E, ?f, ?F, ?g, ?G] do
    {t, args} = next(args)
    x = float!(t, s)
    p = n || 6

    text =
      case d do
        ?e -> sci(x, p)
        ?E -> String.upcase(sci(x, p))
        d when d in [?f, ?F] -> fixed(x, p)
        ?g -> g_format(x, p)
        ?G -> String.upcase(g_format(x, p))
      end

    run(rest, args, emit(st, text), s)
  end

  defp directive(?n, n, rest, args, st, s),
    do: run(rest, args, emit(st, String.duplicate("\n", n || 1)), s)

  defp directive(?N, _n, rest, args, st, s),
    do: run(rest, args, if(st.col == 0, do: st, else: emit(st, "\n")), s)

  defp directive(?i, _n, rest, args, st, s) do
    {_, args} = next(args)
    run(rest, args, st, s)
  end

  # Füllstelle; N ist der Zeichencode (`c oder Zahl), sonst Leerzeichen
  defp directive(?t, n, rest, args, st, s),
    do: run(rest, args, %{st | pend: [{:fill, n || ?\s} | st.pend]}, s)

  defp directive(?|, n, rest, args, st, s), do: run(rest, args, column(st, n || st.col), s)

  defp directive(?+, n, rest, args, st, s),
    do: run(rest, args, column(st, st.start + (n || 8)), s)

  defp directive(d, _n, _rest, _args, _st, _s),
    do: format_error!("unknown directive ~" <> <<d::utf8>>)

  # --- Hilfen ---------------------------------------------------------------

  defp write_text(?w, t, s), do: Writer.format(PrologEx.resolve(t, s), numbervars: true)
  defp write_text(?q, t, s), do: Writer.format(PrologEx.resolve(t, s), Core.writeq_opts())
  defp write_text(?p, t, s), do: Core.print_text(t, s)

  defp write_text(?k, t, s),
    do: Writer.format(PrologEx.resolve(t, s), quoted: true, ignore_ops: true)

  # Ausdruck auswerten; muss eine Ganzzahl ergeben
  defp int!(t, s) do
    case Arith.eval(t, s) do
      n when is_integer(n) -> n
      other -> Error.type!("integer", other)
    end
  end

  defp nonneg!(t, s) do
    case int!(t, s) do
      n when n >= 0 -> n
      n -> Error.domain!("not_less_than_zero", n)
    end
  end

  defp float!(t, s) do
    case Arith.eval(t, s) do
      x when is_float(x) ->
        x

      n when is_integer(n) ->
        try do
          n * 1.0
        rescue
          ArithmeticError -> Error.evaluation!("float_overflow")
        end
    end
  end

  # ~Nd: N Nachkommastellen; ~ND: dazu Tausenderkommas
  defp decimal(v, n, group?) do
    sign = if v < 0, do: "-", else: ""
    digits = Integer.to_string(abs(v)) |> String.pad_leading(n + 1, "0")
    {int, frac} = String.split_at(digits, String.length(digits) - n)
    int = if group?, do: group(int), else: int
    sign <> int <> if(n > 0, do: "." <> frac, else: "")
  end

  defp group(int) do
    int
    |> String.reverse()
    |> String.to_charlist()
    |> Enum.chunk_every(3)
    |> Enum.map(&List.to_string/1)
    |> Enum.join(",")
    |> String.reverse()
  end

  # --- Gleitkommazahlen wie C printf ----------------------------------------
  #
  # Gerundet wird der exakte Binärwert, bei Gleichstand zur geraden Ziffer
  # (wie glibc): 2.5 mit ~0f gibt 2, 2.345 (binär 2.34499...) mit ~2f 2.34.
  # Dazu wird der Float als m * 2^e zerlegt und mit Ganzzahlen gerechnet.

  # {Vorzeichen, m, e} mit |x| = m * 2^e
  defp parts(x) do
    <<sign::1, exp::11, frac::52>> = <<x::float>>
    s = if sign == 1, do: "-", else: ""

    if exp == 0,
      do: {s, frac, -1074},
      else: {s, frac + (1 <<< 52), exp - 1075}
  end

  # round(m * 2^e * 10^k), Gleichstand zur geraden Zahl
  defp scaled(m, e, k) do
    {num, den} =
      cond do
        k >= 0 and e >= 0 -> {m * pow10(k) * (1 <<< e), 1}
        k >= 0 -> {m * pow10(k), 1 <<< -e}
        e >= 0 -> {m * (1 <<< e), pow10(-k)}
        true -> {m, pow10(-k) * (1 <<< -e)}
      end

    q = div(num, den)
    r = num - q * den

    cond do
      2 * r > den -> q + 1
      2 * r < den -> q
      rem(q, 2) == 1 -> q + 1
      true -> q
    end
  end

  defp pow10(k), do: Integer.pow(10, k)

  # Ganzzahl q mit n Nachkommastellen schreiben
  defp with_point(q, 0), do: Integer.to_string(q)

  defp with_point(q, n) do
    digits = q |> Integer.to_string() |> String.pad_leading(n + 1, "0")
    {int, frac} = String.split_at(digits, -n)
    int <> "." <> frac
  end

  # ~Nf
  defp fixed(x, n) do
    {s, m, e} = parts(x)
    s <> with_point(scaled(m, e, n), n)
  end

  # ~Ne: d.ddd e±XX
  defp sci(x, n) do
    {s, m, e} = parts(x)

    if m == 0 do
      s <> with_point(0, n) <> "e+00"
    else
      # Zehnerexponent schätzen, dann so korrigieren, dass die Mantisse
      # n+1 Stellen hat (auch nach dem Runden)
      ex = floor(:math.log10(m) + e * :math.log10(2))
      {q, ex} = sci_digits(m, e, n, ex)
      s <> with_point(q, n) <> exponent(ex)
    end
  end

  defp sci_digits(m, e, n, ex) do
    q = scaled(m, e, n - ex)

    cond do
      q >= pow10(n + 1) -> sci_digits(m, e, n, ex + 1)
      q < pow10(n) -> sci_digits(m, e, n, ex - 1)
      true -> {q, ex}
    end
  end

  defp exponent(ex) do
    sign = if ex < 0, do: "-", else: "+"
    "e" <> sign <> String.pad_leading(Integer.to_string(abs(ex)), 2, "0")
  end

  # ~Ng wie C %g: P signifikante Stellen (mindestens 1); Exponent X nach dem
  # Runden: X < -4 oder X >= P wissenschaftlich, sonst Festkomma mit P-1-X
  # Stellen; Nullen am Ende fallen weg
  defp g_format(x, p) do
    p = max(p, 1)
    sci = sci(x, p - 1)
    [mant, exp] = String.split(sci, "e")
    ex = String.to_integer(exp)

    if ex < -4 or ex >= p,
      do: strip_zeros(mant) <> "e" <> exp,
      else: strip_zeros(fixed(x, p - 1 - ex))
  end

  defp strip_zeros(text) do
    if String.contains?(text, "."),
      do: text |> String.trim_trailing("0") |> String.trim_trailing("."),
      else: text
  end

  defp format_error!(why), do: Error.domain!("format", PrologEx.a(why))

  defp too_many!(_rest, _s), do: format_error!("too many arguments")

  # --- Spalten --------------------------------------------------------------
  #
  # st.done: fertige Ausgabe; st.pend: Stücke seit der letzten
  # Spaltengrenze (umgekehrt): {:t, text} und {:fill, code}; st.col:
  # aktuelle Spalte; st.start: Spalte der letzten Grenze.

  defp emit(st, ""), do: st

  defp emit(st, text) do
    case String.split(text, "\n", parts: 2) do
      [line] ->
        %{st | pend: [{:t, line} | st.pend], col: st.col + String.length(line)}

      [line, more] ->
        st = %{st | pend: [{:t, line} | st.pend]}
        st = %{done: [st.done, flush(st.pend), "\n"], pend: [], col: 0, start: 0}
        emit(st, more)
    end
  end

  # Grenze an Spalte target: fehlender Platz auf die Füllstellen verteilt
  defp column(st, target) do
    pad = target - st.col
    segs = Enum.reverse(st.pend)

    {text, col} =
      if pad > 0 do
        {padded(segs, pad), target}
      else
        {flush(st.pend), st.col}
      end

    %{st | done: [st.done, text], pend: [], col: col, start: col}
  end

  defp padded(segs, pad) do
    k = Enum.count(segs, &match?({:fill, _}, &1))

    if k == 0 do
      [Enum.map(segs, &seg_text/1), String.duplicate(" ", pad)]
    else
      base = div(pad, k)
      extra = rem(pad, k)

      {out, _} =
        Enum.map_reduce(segs, 0, fn
          {:t, t}, i ->
            {t, i}

          {:fill, c}, i ->
            w = base + if(i >= k - extra, do: 1, else: 0)
            {String.duplicate(<<c::utf8>>, w), i + 1}
        end)

      out
    end
  end

  defp flush(pend), do: pend |> Enum.reverse() |> Enum.map(&seg_text/1)

  defp seg_text({:t, t}), do: t
  defp seg_text({:fill, _}), do: ""

  defp finish(st), do: IO.iodata_to_binary([st.done, flush(st.pend)])
end
