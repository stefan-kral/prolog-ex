defmodule PrologEx.Builtins.Pcre do
  @moduledoc """
  Kern von `library(pcre)` (`priv/library/pcre.pl`): reguläre Ausdrücke
  über Erlangs `:re` (ab OTP 28 PCRE2), Schnittstelle wie SWI-Prolog.

  Eine kompilierte Regex ist der gewöhnliche Term `'$regex'(Muster,
  Optionen)`: das Muster als Atom, die Optionen, die das Kompilat
  bestimmen, als nach Namen sortierte Liste ohne Vorgabewerte (etwa
  `[caseless(true), greedy(false)]`). Das Kompilat selbst steht nie in
  einem Term, sondern in einem Cache je Prozess (Schlüssel: Muster und
  Optionen). So kann ein selbst gebauter `'$regex'`-Term nichts
  Schlimmeres sein als eine Regex: Er wird geprüft (sonst
  `domain_error(regex, T)`) und wie jede andere kompiliert. Die Terme
  überstehen `copy_term/2`, `findall/3`, `assert` und `fast_write`.

  Texte: Atome, Zeichen- und Codelisten. Der Ergebnistyp `string` (die
  Vorgabe) ist hier die Textart des Subjekts (bei `[]` die von
  `double_quotes`); dazu `atom`, `chars`, `codes`, `range` (Start-Länge in
  Zeichen) und `term`. Positionen zählen in Zeichen.
  """
  use PrologEx.Builtin
  alias PrologEx.Builtins.{Atoms, Lists}
  alias PrologEx.Error

  @cache_key :prolog_ex_re_cache
  @cache_max 256

  # --- Optionen ------------------------------------------------------------------
  #
  # {Art, Name}: :cbool Kompilieren (Vorgabe false bzw. true bei greedy und
  # auto_capture), :rbool Ausführen, :ignore wird angenommen und
  # übergangen (nur Geschwindigkeit, bei :re ohne Bedeutung)

  @cbool %{
    "caseless" => {false, :caseless},
    "multiline" => {false, :multiline},
    "dotall" => {false, :dotall},
    "extended" => {false, :extended},
    "dollar_endonly" => {false, :dollar_endonly},
    "dupnames" => {false, :dupnames},
    "firstline" => {false, :firstline},
    "ucp" => {false, :ucp},
    "greedy" => {true, :ungreedy},
    "auto_capture" => {true, :no_auto_capture}
  }

  @rbool %{
    "anchored" => {false, :anchored},
    "bol" => {true, :notbol},
    "eol" => {true, :noteol},
    "empty" => {true, :notempty},
    "empty_atstart" => {true, :notempty_atstart}
  }

  @ignore ~w(optimise optimize jit auto_possess dotstar_anchor start_optimize utf_check utf)

  @newlines ~w(any anycrlf cr lf crlf nul)
  @bsrs ~w(anycrlf unicode)
  @ctypes ~w(string atom chars codes range term)

  # Buchstaben in Muster/Flags je Prädikat (wie SWI)
  @match_flags %{
    "x" => {"extended", "true"},
    "i" => {"caseless", "true"},
    "m" => {"multiline", "true"},
    "s" => {"dotall", "true"},
    "a" => {"capture_type", "atom"},
    "r" => {"capture_type", "range"},
    "t" => {"capture_type", "term"}
  }
  @split_flags %{
    "a" => {"capture_type", "atom"},
    "s" => {"capture_type", "string"},
    "n" => {"capture_type", "number"}
  }
  @replace_flags %{
    "g" => {"global", "true"},
    "a" => {"capture_type", "atom"},
    "s" => {"capture_type", "string"}
  }

  # Optionsliste als [{Name, Wert}], erste Angabe gilt (wie SWI);
  # Wert: Atomtext oder Ganzzahl
  defp options!(opts, s) do
    case Lists.skip_list(opts, s) do
      {_, []} -> :ok
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(opts, s))
    end

    opts
    |> Lists.items(s)
    |> Enum.map(&option!(PrologEx.unmark(PrologEx.resolve(&1, s)), s))
    |> Enum.uniq_by(&elem(&1, 0))
  end

  defp option!({:var, _}, _s), do: Error.instantiation!()

  defp option!({:struct, name, [v]} = o, s) do
    name =
      case name do
        "newline2" -> "newline"
        "bsr2" -> "bsr"
        n -> n
      end

    v = PrologEx.walk(v, s)

    cond do
      match?({:var, _}, v) ->
        Error.instantiation!()

      Map.has_key?(@cbool, name) or Map.has_key?(@rbool, name) or name in @ignore ->
        {name, bool!(v)}

      name == "newline" ->
        {name, member!(v, @newlines, o, s)}

      name == "bsr" ->
        {name, member!(v, @bsrs, o, s)}

      name == "capture_type" ->
        {name, member!(v, @ctypes, o, s)}

      name == "start" and is_integer(v) and v >= 0 ->
        {name, v}

      name == "start" and is_integer(v) ->
        Error.domain!("not_less_than_zero", v)

      name == "start" ->
        Error.type!("integer", v)

      true ->
        Error.domain!("re_option", PrologEx.resolve(o, s))
    end
  end

  defp option!(o, s), do: Error.domain!("re_option", PrologEx.resolve(o, s))

  defp bool!({:atom, b}) when b in ["true", "false"], do: b
  defp bool!(other), do: Error.type!("bool", other)

  defp member!({:atom, x}, allowed, o, s) do
    if x in allowed, do: x, else: Error.domain!("re_option", PrologEx.resolve(o, s))
  end

  defp member!(_, _allowed, o, s), do: Error.domain!("re_option", PrologEx.resolve(o, s))

  # Buchstaben aus Muster/Flags als Optionen (vor der Optionsliste: Flags
  # gehen vor); bei Widerspruch gilt der erste
  defp flag_options!(flags, table, s) do
    {text, _} = text!(flags, s)

    text
    |> String.codepoints()
    |> Enum.map(fn c -> Map.get(table, c) || Error.domain!("re_flag", a(c)) end)
  end

  # --- Regex: Muster und Optionen -------------------------------------------------

  # {Muster, kanonische Kompilieroptionen [{Name, Wert}], weitere
  # Optionen [{Name, Wert}]}; table: die erlaubten Flag-Buchstaben
  defp regex!(re, opts, table, s) do
    call_opts = options!(opts, s)

    case PrologEx.unmark(PrologEx.resolve(re, s)) do
      {:var, _} ->
        Error.instantiation!()

      {:struct, "$regex", [_, _]} = t ->
        {pat, copts} = canonical!(t, s)
        # Kompilieroptionen des Aufrufs gelten bei einer kompilierten
        # Regex nicht (wie SWI)
        {pat, copts, Enum.reject(call_opts, &compile_opt?/1)}

      {:struct, "/", [p, f]} ->
        {pat, _} = text!(p, s)
        split_opts(pat, Enum.uniq_by(flag_options!(f, table, s) ++ call_opts, &elem(&1, 0)))

      other ->
        {pat, _} = text!(other, s)
        split_opts(pat, call_opts)
    end
  end

  defp compile_opt?({n, _}),
    do: Map.has_key?(@cbool, n) or n in ["newline", "bsr", "capture_type"]

  defp split_opts(pat, opts) do
    {c, r} = Enum.split_with(opts, &compile_opt?/1)
    {pat, canon(c), r}
  end

  # ohne Vorgabewerte, nach Namen sortiert
  defp canon(copts) do
    copts
    |> Enum.reject(fn
      {"capture_type", "string"} -> true
      {n, v} -> match?({d, _} when d == (v == "true"), Map.get(@cbool, n))
    end)
    |> Enum.sort()
  end

  # '$regex'(Muster, Optionen) prüfen: Atom und kanonische Optionsliste
  defp canonical!({:struct, "$regex", [p, o]} = t, s) do
    bad = fn -> Error.domain!("regex", PrologEx.resolve(t, s)) end

    pat =
      case PrologEx.walk(p, s) do
        {:atom, x} -> x
        _ -> bad.()
      end

    copts =
      try do
        options!(o, s)
      rescue
        Error -> bad.()
      end

    if Enum.all?(copts, &compile_opt?/1) and canon(copts) == copts and
         length(copts) == length(Lists.items(o, s)),
       do: {pat, copts},
       else: bad.()
  end

  defp regex_term(pat, copts) do
    opts = for {n, v} <- copts, do: mk(n, [if(is_integer(v), do: v, else: a(v))])
    mk("$regex", [a(pat), list(opts)])
  end

  # --- Kompilieren (mit Cache) -------------------------------------------------------

  defp compiled(pat, copts) do
    cache = Process.get(@cache_key, %{})

    case Map.fetch(cache, {pat, copts}) do
      {:ok, entry} ->
        entry

      :error ->
        entry = compile!(pat, copts)
        cache = if map_size(cache) >= @cache_max, do: %{}, else: cache
        Process.put(@cache_key, Map.put(cache, {pat, copts}, entry))
        entry
    end
  end

  defp compile!(pat, copts) do
    flags =
      Enum.flat_map(copts, fn
        {"newline", v} -> [{:newline, String.to_atom(v)}]
        {"bsr", v} -> [String.to_atom("bsr_" <> v)]
        {"capture_type", _} -> []
        {n, _} -> [elem(Map.fetch!(@cbool, n), 1)]
      end)

    case :re.compile(pat, [:unicode | flags]) do
      {:ok, mp} ->
        {:namelist, names} = :re.inspect(mp, :namelist)
        auto? = not Enum.member?(copts, {"auto_capture", "false"})
        extended? = Enum.member?(copts, {"extended", "true"})
        named = if names == [], do: %{}, else: named_groups(pat, extended?, auto?, names)

        %{
          mp: mp,
          names: names,
          named: named,
          ctype: List.keyfind(copts, "capture_type", 0, {nil, "string"}) |> elem(1)
        }

      {:error, {msg, pos}} ->
        Error.syntax!("#{msg} at #{pos}")
    end
  end

  # Nummern der benannten Gruppen (Name => Nummer), aus dem Muster gelesen;
  # :unknown, wo das nicht sicher geht ((?| ...), Optionen im Muster) –
  # dann erscheinen benannte Gruppen auch mit Nummer
  defp named_groups(pat, extended?, auto?, names) do
    case scan(pat, extended?, auto?, 0, %{}) do
      {:ok, found} -> if Enum.sort(Map.keys(found)) == Enum.sort(names), do: found, else: :unknown
      :unknown -> :unknown
    end
  end

  defp scan(<<>>, _x, _auto, _n, acc), do: {:ok, acc}

  defp scan(<<"\\Q", rest::binary>>, x, auto, n, acc),
    do: scan(skip_to(rest, "\\E"), x, auto, n, acc)

  defp scan(<<"\\", _::utf8, rest::binary>>, x, auto, n, acc), do: scan(rest, x, auto, n, acc)
  defp scan(<<"[", rest::binary>>, x, auto, n, acc), do: scan(skip_class(rest), x, auto, n, acc)

  defp scan(<<"#", rest::binary>>, true, auto, n, acc),
    do: scan(skip_to(rest, "\n"), true, auto, n, acc)

  defp scan(<<"(*", rest::binary>>, x, auto, n, acc), do: scan(rest, x, auto, n, acc)

  defp scan(<<"(?#", rest::binary>>, x, auto, n, acc),
    do: scan(skip_to(rest, ")"), x, auto, n, acc)

  defp scan(<<"(?|", _::binary>>, _x, _auto, _n, _acc), do: :unknown

  defp scan(<<"(?", c, rest::binary>>, x, auto, n, acc)
       when c in [?<, ?', ?P] do
    case named_start(<<c, rest::binary>>) do
      {:ok, name, rest} -> scan(rest, x, auto, n + 1, Map.put(acc, name, n + 1))
      :no -> scan(rest, x, auto, n, acc)
    end
  end

  # Optionen im Muster ((?x), (?n), (?i:...)) können x und die
  # Nummerierung ändern
  defp scan(<<"(?", c, _::binary>>, _x, _auto, _n, _acc) when c in [?x, ?n, ?^], do: :unknown
  defp scan(<<"(?", rest::binary>>, x, auto, n, acc), do: scan(rest, x, auto, n, acc)
  defp scan(<<"(", rest::binary>>, x, true, n, acc), do: scan(rest, x, true, n + 1, acc)
  defp scan(<<_::utf8, rest::binary>>, x, auto, n, acc), do: scan(rest, x, auto, n, acc)

  defp named_start(<<"<", c, _::binary>>) when c in [?=, ?!], do: :no
  defp named_start(<<"<", rest::binary>>), do: name_until(rest, ">")
  defp named_start(<<"'", rest::binary>>), do: name_until(rest, "'")
  defp named_start(<<"P<", rest::binary>>), do: name_until(rest, ">")
  defp named_start(_), do: :no

  defp name_until(bin, close) do
    case :binary.split(bin, close) do
      [name, rest] -> {:ok, name, rest}
      _ -> :no
    end
  end

  defp skip_to(bin, stop) do
    case :binary.split(bin, stop) do
      [_, rest] -> rest
      _ -> <<>>
    end
  end

  # Zeichenklasse: ] gleich am Anfang (auch nach ^) ist ein Zeichen
  defp skip_class(<<"^]", rest::binary>>), do: class_body(rest)
  defp skip_class(<<"]", rest::binary>>), do: class_body(rest)
  defp skip_class(bin), do: class_body(bin)

  defp class_body(<<>>), do: <<>>
  defp class_body(<<"]", rest::binary>>), do: rest
  defp class_body(<<"\\", _::utf8, rest::binary>>), do: class_body(rest)
  defp class_body(<<"[:", rest::binary>>), do: class_body(skip_to(rest, ":]"))
  defp class_body(<<_::utf8, rest::binary>>), do: class_body(rest)

  # --- Texte -------------------------------------------------------------------------

  # {Binary, Art}: :atom, :chars, :codes
  defp text!(t, s) do
    case PrologEx.walk(t, s) do
      {:var, _} -> Error.instantiation!()
      {:atom, x} -> {x, :atom}
      [] -> {"", default_kind()}
      [_ | _] = l -> list_text!(l, s)
      {:glist, _} = l -> list_text!(l, s)
      other -> Error.type!("text", PrologEx.resolve(other, s))
    end
  end

  defp default_kind do
    case PrologEx.Flags.get("double_quotes") do
      {:atom, "codes"} -> :codes
      {:atom, "atom"} -> :atom
      _ -> :chars
    end
  end

  defp list_text!(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> :ok
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("text", PrologEx.resolve(l, s))
    end

    items = Enum.map(Lists.items(l, s), &PrologEx.walk(&1, s))
    if Enum.any?(items, &match?({:var, _}, &1)), do: Error.instantiation!()

    case items do
      [{:atom, _} | _] ->
        if Enum.all?(items, &char?/1),
          do: {Enum.map_join(items, &elem(&1, 1)), :chars},
          else: Error.type!("text", PrologEx.resolve(l, s))

      _ ->
        if Enum.all?(items, &code?/1),
          do: {List.to_string(items), :codes},
          else: Error.type!("text", PrologEx.resolve(l, s))
    end
  end

  defp char?({:atom, c}), do: match?([_], String.to_charlist(c))
  defp char?(_), do: false

  defp code?(c), do: is_integer(c) and c in 0..0x10FFFF and c not in 0xD800..0xDFFF

  defp out(bin, :atom), do: a(bin)
  defp out(bin, :chars), do: bin |> String.codepoints() |> Enum.map(&a/1) |> list()
  defp out(bin, :codes), do: bin |> String.to_charlist() |> list()

  # Zeichen vor dem Byte-Offset b
  defp chars_before(bin, b), do: bin |> binary_part(0, b) |> String.to_charlist() |> length()

  # Byte-Offset des n-ten Zeichens (höchstens das Ende)
  defp byte_offset(bin, n), do: byte_offset(bin, n, 0)
  defp byte_offset(_bin, 0, acc), do: acc
  defp byte_offset(<<>>, _n, acc), do: acc

  defp byte_offset(<<c::utf8, rest::binary>>, n, acc),
    do: byte_offset(rest, n - 1, acc + byte_size(<<c::utf8>>))

  # --- Ausführen ---------------------------------------------------------------------

  defp run_flags(ropts, subject) do
    Enum.flat_map(ropts, fn
      {"start", n} -> [{:offset, byte_offset(subject, n)}]
      {n, v} when is_map_key(@rbool, n) -> rbool(Map.fetch!(@rbool, n), v)
      _ -> []
    end)
  end

  defp rbool({default, flag}, v), do: if(v == "true" != default, do: [flag], else: [])

  defp run!(subject, entry, ropts, extra) do
    opts = [{:capture, :all, :index}, :report_errors | extra ++ run_flags(ropts, subject)]

    case :re.run(subject, entry.mp, opts) do
      {:match, m} -> m
      :nomatch -> nil
      {:error, :match_limit} -> Error.resource!("match_limit")
      {:error, :match_limit_recursion} -> Error.resource!("match_limit")
      {:error, other} -> Error.resource!(to_string(other))
    end
  end

  # Indizes der benannten Gruppen je Treffer (in der Reihenfolge der namelist)
  defp name_indexes(subject, entry, ropts, extra) do
    opts = [{:capture, :all_names, :index} | extra ++ run_flags(ropts, subject)]

    case :re.run(subject, entry.mp, opts) do
      {:match, m} -> m
      _ -> nil
    end
  end

  # ein Treffer als Paarliste: 0, nicht benannte Gruppen nach Nummer,
  # benannte nach Name (ohne Typ-Endung; die namelist von :re ist schon
  # sortiert); nicht gesetzte fehlen
  defp pairs(subject, kind, idx, name_idx, entry, ctype) do
    named_nums =
      if entry.named == :unknown, do: MapSet.new(), else: MapSet.new(Map.values(entry.named))

    numbered =
      for {{st, len}, i} <- Enum.with_index(idx),
          st >= 0,
          i not in named_nums,
          do: {i, value(subject, kind, st, len, ctype)}

    named =
      for {name, {st, len}} <- Enum.zip(entry.names, name_idx || []), st >= 0 do
        {key, type} = name_type(name, ctype)
        {a(key), value(subject, kind, st, len, type)}
      end

    list(for {k, v} <- numbered ++ named, do: mk("-", [k, v]))
  end

  defp name_type(name, ctype) do
    case Regex.run(~r/^(.+)_([SAIFNTR])$/, name) do
      [_, key, "S"] -> {key, "string"}
      [_, key, "A"] -> {key, "atom"}
      [_, key, "R"] -> {key, "range"}
      [_, key, _] -> {key, "term"}
      nil -> {name, ctype}
    end
  end

  defp value(subject, kind, st, len, type) do
    bin = binary_part(subject, st, len)

    case type do
      "string" -> out(bin, kind)
      "atom" -> a(bin)
      "chars" -> out(bin, :chars)
      "codes" -> out(bin, :codes)
      "range" -> mk("-", [chars_before(subject, st), bin |> String.to_charlist() |> length()])
      "term" -> read_term!(bin)
      "number" -> number_or_atom(bin)
    end
  end

  defp read_term!(bin) do
    t = {:var, PrologEx.Vars.next()}

    case PrologEx.Builtins.IO.read_from_atom(a(bin), t, [], %{}) do
      {:unify, [{^t, term} | _]} -> term
    end
  end

  defp number_or_atom(bin) do
    case Atoms.parse_number(bin) do
      {:ok, n} -> n
      _ -> a(bin)
    end
  end

  # --- Prädikate -----------------------------------------------------------------------

  defbuiltin "$re_compile", [re, opts, r] do
    s = subst()
    {pat, copts, _} = regex!(re, opts, @match_flags, s)
    _ = compiled(pat, copts)
    {:unify, [{r, regex_term(pat, copts)}]}
  end

  defbuiltin "$re_match", [re, str, opts] do
    s = subst()
    {pat, copts, ropts} = regex!(re, opts, @match_flags, s)
    entry = compiled(pat, copts)
    {subject, _} = text!(str, s)
    run!(subject, entry, ropts, []) != nil
  end

  defbuiltin "$re_matchsub", [re, str, opts, sub] do
    s = subst()
    {pat, copts, ropts} = regex!(re, opts, @match_flags, s)
    entry = compiled(pat, copts)
    {subject, kind} = text!(str, s)
    ctype = ctype(ropts, entry)

    case run!(subject, entry, ropts, []) do
      nil ->
        :fail

      idx ->
        names = if entry.names == [], do: [], else: name_indexes(subject, entry, ropts, [])
        {:unify, [{sub, pairs(subject, kind, idx, names, entry, ctype)}]}
    end
  end

  # alle Treffer (für re_foldl/6)
  defbuiltin "$re_matches", [re, str, opts, ms] do
    s = subst()
    {pat, copts, ropts} = regex!(re, opts, @match_flags, s)
    entry = compiled(pat, copts)
    {subject, kind} = text!(str, s)
    ctype = ctype(ropts, entry)
    all = run!(subject, entry, ropts, [:global]) || []

    names =
      if entry.names == [],
        do: List.duplicate([], length(all)),
        else: name_indexes(subject, entry, ropts, [:global]) || []

    matches = Enum.zip_with(all, names, &pairs(subject, kind, &1, &2, entry, ctype))
    {:unify, [{ms, list(matches)}]}
  end

  defbuiltin "$re_split", [re, str, opts, splits] do
    s = subst()
    {pat, copts, ropts} = regex!(re, opts, @split_flags, s)
    entry = compiled(pat, copts)
    {subject, kind} = text!(str, s)
    ctype = ctype(ropts, entry)
    piece = fn st, len -> value(subject, kind, st, len, ctype) end

    {pieces, last} =
      (run!(subject, entry, ropts, [:global]) || [])
      |> Enum.flat_map_reduce(0, fn [{st, len} | _], pos ->
        {[piece.(pos, st - pos), piece.(st, len)], st + len}
      end)

    {:unify, [{splits, list(pieces ++ [piece.(last, byte_size(subject) - last)])}]}
  end

  defbuiltin "$re_replace", [re, with, str, opts, new] do
    s = subst()
    {pat, copts, ropts} = regex!(re, opts, @replace_flags, s)
    entry = compiled(pat, copts)
    {subject, kind} = text!(str, s)
    {template, _} = text!(with, s)
    parts = template!(template, entry)
    global? = List.keyfind(ropts, "global", 0) == {"global", "true"}
    ropts = List.keydelete(ropts, "global", 0)

    out_kind = if ctype(ropts, entry) == "atom", do: :atom, else: kind

    matches =
      case run!(subject, entry, ropts, if(global?, do: [:global], else: [])) do
        nil -> []
        m when global? -> m
        m -> [m]
      end

    names =
      cond do
        matches == [] or entry.names == [] -> List.duplicate([], length(matches))
        global? -> name_indexes(subject, entry, ropts, [:global])
        true -> [name_indexes(subject, entry, ropts, [])]
      end

    {acc, pos} =
      matches
      |> Enum.zip(names)
      |> Enum.reduce({[], 0}, fn {[{st, len} | _] = idx, nidx}, {acc, pos} ->
        repl = Enum.map(parts, &part_text(&1, subject, idx, nidx, entry))
        {[repl, binary_part(subject, pos, st - pos) | acc], st + len}
      end)

    result =
      [binary_part(subject, pos, byte_size(subject) - pos) | acc]
      |> Enum.reverse()
      |> IO.iodata_to_binary()

    {:unify, [{new, out(result, out_kind)}]}
  end

  defbuiltin "$re_flush", [] do
    Process.delete(@cache_key)
    :ok
  end

  defbuiltin "$re_config", [l] do
    v = :re.version()

    {:unify,
     [
       {l,
        list([
          mk("version", [a(v)]),
          mk("unicode", [a("true")]),
          mk("utf8", [a("true")]),
          mk("unicode_properties", [a("true")]),
          mk("jit", [a("false")])
        ])}
     ]}
  end

  defp ctype(ropts, entry) do
    case List.keyfind(ropts, "capture_type", 0) do
      {_, t} -> t
      nil -> entry.ctype
    end
  end

  # --- Ersetzungstext: \N \{N} $Name ${Name}, \\ und $$ ---------------------------

  defp template!(t, entry), do: t |> tparse([]) |> Enum.map(&check_ref!(&1, entry))

  defp tparse(<<>>, acc), do: Enum.reverse(acc)
  defp tparse(<<"\\\\", r::binary>>, acc), do: tparse(r, [{:lit, "\\"} | acc])
  defp tparse(<<"$$", r::binary>>, acc), do: tparse(r, [{:lit, "$"} | acc])

  defp tparse(<<c, "{", r::binary>> = all, acc) when c in [?\\, ?$] do
    case :binary.split(r, "}") do
      [ref, rest] when ref != "" -> tparse(rest, [ref(ref) | acc])
      _ -> lit(all, acc)
    end
  end

  defp tparse(<<"\\", d, _::binary>> = all, acc) when d in ?0..?9 do
    <<"\\", r::binary>> = all
    {digits, rest} = span(r, &(&1 in ?0..?9))
    tparse(rest, [ref(digits) | acc])
  end

  defp tparse(<<"$", c, _::binary>> = all, acc)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ do
    <<"$", r::binary>> = all
    {name, rest} = span(r, &(&1 in ?a..?z or &1 in ?A..?Z or &1 in ?0..?9 or &1 == ?_))
    tparse(rest, [ref(name) | acc])
  end

  defp tparse(bin, acc), do: lit(bin, acc)

  defp lit(<<c::utf8, r::binary>>, acc), do: tparse(r, [{:lit, <<c::utf8>>} | acc])

  defp span(bin, keep?) do
    n = bin |> :binary.bin_to_list() |> Enum.take_while(keep?) |> length()
    {binary_part(bin, 0, n), binary_part(bin, n, byte_size(bin) - n)}
  end

  defp ref(x) do
    case Integer.parse(x) do
      {n, ""} -> {:num, n}
      _ -> {:name, x}
    end
  end

  # Namen ohne Typ-Endung; eine benannte Gruppe nicht über ihre Nummer
  defp check_ref!({:lit, _} = p, _entry), do: p

  defp check_ref!({:name, x}, entry) do
    case Enum.find_index(entry.names, &(elem(name_type(&1, "string"), 0) == x)) do
      nil -> Error.existence!("re_group", a(x))
      i -> {:name, i, elem(name_type(Enum.at(entry.names, i), "string"), 1)}
    end
  end

  defp check_ref!({:num, n} = p, entry) do
    if entry.named != :unknown and n in Map.values(entry.named),
      do: Error.existence!("re_group", n),
      else: p
  end

  defp part_text({:lit, t}, _subject, _idx, _nidx, _entry), do: t

  defp part_text({:num, n}, subject, idx, _nidx, _entry) do
    case Enum.at(idx, n) do
      {st, len} when st >= 0 -> binary_part(subject, st, len)
      _ -> ""
    end
  end

  defp part_text({:name, i, type}, subject, _idx, nidx, _entry) do
    case Enum.at(nidx, i) do
      {st, len} when st >= 0 ->
        bin = binary_part(subject, st, len)
        if type == "term", do: PrologEx.Writer.format(read_term!(bin)), else: bin

      _ ->
        ""
    end
  end
end
