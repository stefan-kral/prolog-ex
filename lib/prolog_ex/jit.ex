defmodule PrologEx.Jit do
  @moduledoc """
  Übersetzt deterministische, rein arithmetische Prädikate in BEAM-Code.
  Innerhalb des übersetzten Stücks liegen die Werte in Erlang-Variablen:
  keine Bindungen, kein Zielstapel, keine Kompaktierung. Gebunden wird nur
  an den Rändern: beim Aufruf die Eingaben lesen (Zahlen), am Ende die
  Ausgaben binden (frische Variablen). Passt ein Aufruf nicht dazu, nimmt
  ihn der Interpreter.

  Was übersetzt wird – jede Klausel:

    * Kopf: Zahlen oder Variablen
    * Rumpf: `V is E`, arithmetische Vergleiche, `X = Y` (Zahlen oder
      Variablen), `!`, `true`, `fail`, `( C -> T ; E )`, `( C -> T )`,
      `\\+ G` und Aufrufe des Prädikats selbst (Argumente Zahlen oder
      Variablen)
    * E aus Zahlen, Variablen, `pi`, `e`, `epsilon` und den auswertbaren
      Funktoren (außer random/random_float)

  Kommen nur Ganzzahlen und ganzzahlige Operationen vor (+ - * // mod rem
  div min max >> << /\\ \\/ xor gcd, einstellig - + abs sign msb \\),
  rechnet der Code mit + - * direkt und nimmt nur ganzzahlige Eingaben;
  sonst rechnet er alles mit PrologEx.Arith (wie der Interpreter, auch
  rationale Zwischenwerte) und nimmt Ganzzahlen und Floats.

  Das Prädikat ist nachweislich deterministisch: je zwei Klauseln
  schließen sich aus – durch einen Schnitt in der früheren, verschiedene
  Konstanten im Kopf (auch `X = c` am Anfang des Rumpfs), einen Vergleich
  am Anfang, der für die Konstante der anderen falsch ist, oder einander
  ausschließende Vergleiche am Anfang (`X > 0` / `X =< 0`). Vor dem
  ausschließenden Vergleich der späteren Klausel darf nichts einen Fehler
  werfen können (der Interpreter würde sie beim Zurücksetzen versuchen).
  Die Modi (Eingabe/Ausgabe je Argument) ergeben sich aus dem Rumpf:
  gelesen heißt Eingabe, von `is` oder dem eigenen Aufruf bestimmt (oder
  nirgends gelesen) heißt Ausgabe; `=` legt nichts fest.

  Gleich wie im Interpreter: Antworten, Fehler (dieselben
  Arithmetik-Funktionen), Inferenzen (jeder Aufruf und jedes eingebaute
  Ziel zählt eins; Schnitt, `,`, `;` und `->` nicht) und Grenzen
  (Inferenz-, Zeit-, Speichergrenzen an denselben Prüfpunkten, siehe
  tick/0).

  Die Module heißen nach einem Hash ihrer Klauseln: dasselbe Programm
  wieder geladen nimmt das vorhandene Modul.
  """

  {ops2, ops1} = PrologEx.Arith.ops()
  @ops2 ops2
  @ops1 ops1 -- ~w(random random_float)
  # ganzzahlig abgeschlossen: Ganzzahlen rein, Ganzzahlen raus
  @iops2 ~w(+ - * // mod rem div min max >> << /\\ \\/ xor gcd)
  @iops1 ~w(- + abs sign msb \\)
  # auf Ganzzahlen fehlerfrei
  @total2 ~w(+ - * min max /\\ \\/ xor gcd)
  @total1 ~w(- + abs sign \\)
  @cmps ~w(< > =< >= =:= =\\=)
  @consts %{"pi" => :math.pi(), "e" => :math.exp(1), "epsilon" => 2.220446049250313e-16}

  # --- Analyse ------------------------------------------------------------

  @doc """
  Übersetzt die Prädikate eines Ladeschritts (eines Moduls), soweit sie
  passen. `preds`: [{{name, stelligkeit}, [{kopf, rumpf}]}]. `ext`: für ein
  schon geladenes, übersetztes, statisches Prädikat außerhalb des Schritts
  `%{mod: modul, p: funktion, modes: %{k => :in | :out}, num: bool}`, sonst
  nil. `dynamic`: die dynamischen unter `preds` – andere dürfen sie nicht
  rufen (nach einem assert wäre ihr Code falsch).

  Ergebnis: %{{name, stelligkeit} => {{modul, eintritt, p, gerufen},
  eingaben, ausgaben}}; eingaben `{:num, ks}`, wenn auch Floats
  hineindürfen; gerufen: die anderen Prädikate, die der Code direkt ruft.
  """
  def compile_batch(preds, ext \\ fn _ -> nil end, dynamic \\ MapSet.new()) do
    case settle(preds, ext, dynamic) do
      nil -> %{}
      s -> build(s, :load)
    end
  end

  @doc """
  Ein einzelnes Prädikat (Aufrufe nur von sich selbst):
  `{:ok, {modul, eintritt, p, []}, eingaben, ausgaben}` oder `:no`.
  """
  def compile(source) do
    with {:ok, key} <- key_of(source),
         %{^key => {mod, ins, outs}} <- compile_batch([{key, source}]) do
      {:ok, mod, ins, outs}
    else
      _ -> :no
    end
  end

  @doc false
  # der erzeugte Elixir-Code (zum Nachsehen); preds wie compile_batch/3
  def code(preds) do
    case settle(preds, fn _ -> nil end, MapSet.new()) do
      nil -> :no
      s -> build(s, :show)
    end
  end

  defp key_of([{h, _} | _]) do
    case plain(h) do
      {:struct, f, a} -> {:ok, {f, length(a)}}
      _ -> :no
    end
  end

  defp key_of(_), do: :no

  # Analyse bis zum Fixpunkt: was nicht passt, fällt heraus, und mit ihm,
  # wer es ruft
  defp settle(preds, ext0, dynamic) do
    batch = MapSet.new(for {k, _} <- preds, do: k)
    ext = fn k -> if MapSet.member?(batch, k), do: nil, else: ext0.(k) end

    callable = fn k ->
      (MapSet.member?(batch, k) and not MapSet.member?(dynamic, k)) or ext.(k) != nil
    end

    parsed = for {k, src} <- preds, p = parse(k, src, callable), p != nil, into: %{}, do: {k, p}
    settle_loop(parsed, ext)
  end

  defp settle_loop(parsed, ext) do
    parsed = drop_orphans(parsed, ext)

    with true <- map_size(parsed) > 0,
         {:ok, modes} <- global_modes(parsed, ext),
         {:ok, num} <- kinds(parsed, ext),
         {:ok, irs} <- flows(parsed, modes, num, ext) do
      %{parsed: parsed, modes: modes, num: num, irs: irs, ext: ext}
    else
      false -> nil
      {:bad, bad} -> settle_loop(Map.drop(parsed, bad), ext)
    end
  end

  # wer etwas ruft, das weder übersetzt wird noch schon übersetzt ist
  defp drop_orphans(parsed, ext) do
    bad =
      for {k, p} <- parsed,
          Enum.any?(p.deps, &(not Map.has_key?(parsed, &1) and ext.(&1) == nil)),
          do: k

    if bad == [], do: parsed, else: drop_orphans(Map.drop(parsed, bad), ext)
  end

  defp parse({_, arity} = key, source, callable) when arity > 0 do
    source = Enum.map(source, fn {h, b} -> {plain(h), plain(b)} end)
    ctx = %{self: key, callable: callable}

    clauses =
      for {h, b} <- source do
        head = args(h)
        Enum.each(head, &term!/1)
        {head, Enum.map(conj(b), &goal(&1, ctx))}
      end

    deps = clauses |> collect_calls() |> Enum.uniq() |> List.delete(key)
    %{key: key, arity: arity, clauses: clauses, source: source, deps: deps}
  catch
    :no -> nil
  end

  defp parse(_, _, _), do: nil

  defp collect_calls({:call, k, _}), do: [k]
  defp collect_calls(t) when is_tuple(t), do: collect_calls(Tuple.to_list(t))
  defp collect_calls(l) when is_list(l), do: Enum.flat_map(l, &collect_calls/1)
  defp collect_calls(_), do: []

  # je Prädikat: Fluss und Ausschließlichkeit
  defp flows(parsed, modes, num, ext) do
    cm = fn ck ->
      case parsed do
        %{^ck => p} -> Map.new(0..(p.arity - 1), &{&1, modes[{ck, &1}]})
        _ -> ext.(ck).modes
      end
    end

    res =
      for {key, p} <- parsed do
        try do
          irs = Enum.map(p.clauses, &flow(&1, cm.(key), cm))
          exclusive!(irs, MapSet.member?(num, key))
          {key, irs}
        catch
          :no -> {key, :no}
        end
      end

    case for {k, :no} <- res, do: k do
      [] -> {:ok, Map.new(res)}
      bad -> {:bad, bad}
    end
  end

  # Ganzzahlig oder nicht: über Aufrufe hinweg einheitlich (ein Ergebnis
  # kann ein Float sein, ein Argument auch) – je zusammenhängendem Teil
  # des Aufrufgraphen; ein ganzzahliges schon übersetztes Prädikat darf
  # von einem nicht ganzzahligen nicht gerufen werden
  defp kinds(parsed, ext) do
    ext_num = fn d ->
      case ext.(d) do
        nil -> nil
        e -> e.num
      end
    end

    seed =
      for {k, p} <- parsed,
          not int_only?(p.clauses) or Enum.any?(p.deps, &(ext_num.(&1) == true)),
          into: MapSet.new(),
          do: k

    edges = for {k, p} <- parsed, d <- p.deps, Map.has_key?(parsed, d), do: {k, d}
    num = spread(seed, edges)

    case for k <- num, d <- parsed[k].deps, ext_num.(d) == false, do: k do
      [] -> {:ok, num}
      bad -> {:bad, Enum.uniq(bad)}
    end
  end

  defp spread(set, edges) do
    set2 =
      Enum.reduce(edges, set, fn {a, b}, acc ->
        cond do
          MapSet.member?(acc, a) -> MapSet.put(acc, b)
          MapSet.member?(acc, b) -> MapSet.put(acc, a)
          true -> acc
        end
      end)

    if MapSet.equal?(set2, set), do: set, else: spread(set2, edges)
  end

  defp args({:struct, _, a}), do: a

  # wie PrologEx.Compiler: `true` im Rumpf fällt weg (zählt also nicht)
  defp conj({:struct, ",", [a, b]}), do: conj(a) ++ conj(b)
  defp conj({:atom, "true"}), do: []
  defp conj(g), do: [g]

  # in Steuerkonstrukten bleibt `true` ein Ziel (zählt eins)
  defp seq({:struct, ",", [a, b]}, ctx), do: seq(a, ctx) ++ seq(b, ctx)
  defp seq(g, ctx), do: [goal(g, ctx)]

  # Terme ohne Ground-Markierung
  defp plain({tag, f, a}) when tag in [:struct, :gstruct], do: {:struct, f, Enum.map(a, &plain/1)}
  defp plain({:glist, l}), do: plain(l)
  defp plain([h | t]), do: [plain(h) | plain(t)]
  defp plain(t), do: t

  defp goal({:atom, "!"}, _), do: :cut
  defp goal({:atom, "true"}, _), do: true
  defp goal({:atom, f}, _) when f in ["fail", "false"], do: :fail
  defp goal({:struct, "is", [l, r]}, _), do: {:is, term!(l), expr!(r)}
  defp goal({:struct, op, [a, b]}, _) when op in @cmps, do: {:cmp, op, expr!(a), expr!(b)}
  defp goal({:struct, "=", [a, b]}, _), do: {:unify, term!(a), term!(b)}

  defp goal({:struct, ";", [{:struct, "->", [c, t]}, e]}, ctx),
    do: {:ite, seq(c, ctx), seq(t, ctx), seq(e, ctx)}

  # ( C -> T ) ohne Else: der Interpreter nimmt `fail` als Else (zählt eins)
  defp goal({:struct, "->", [c, t]}, ctx), do: {:ite, seq(c, ctx), seq(t, ctx), [:fail]}
  defp goal({:struct, "\\+", [g]}, ctx), do: {:not, seq(g, ctx)}
  defp goal({:struct, ";", _}, _), do: throw(:no)
  defp goal({:struct, "->", _}, _), do: throw(:no)

  # Aufruf: das Prädikat selbst oder ein anderes, das übersetzt wird oder
  # schon übersetzt ist
  defp goal({:struct, name, a}, ctx) do
    key = {name, length(a)}

    if key == ctx.self or ctx.callable.(key),
      do: {:call, key, Enum.map(a, &term!/1)},
      else: throw(:no)
  end

  defp goal(_, _), do: throw(:no)

  # Argument: Zahl oder Variable
  defp term!(n) when is_integer(n) or is_float(n), do: n
  defp term!({:var, _} = v), do: v
  defp term!(_), do: throw(:no)

  defp expr!(n) when is_integer(n) or is_float(n), do: n
  defp expr!({:var, _} = v), do: v
  defp expr!({:atom, c}) when is_map_key(@consts, c), do: @consts[c]
  defp expr!({:struct, op, [a, b]}) when op in @ops2, do: {:op2, op, expr!(a), expr!(b)}
  defp expr!({:struct, op, [a]}) when op in @ops1, do: {:op1, op, expr!(a)}
  defp expr!(_), do: throw(:no)

  defp vars({:var, _} = v), do: [v]
  defp vars({:op2, _, a, b}), do: vars(a) ++ vars(b)
  defp vars({:op1, _, a}), do: vars(a)
  defp vars(_), do: []

  defp anon?({:var, {"_", _}}), do: true
  defp anon?({:var, "_"}), do: true
  defp anon?(_), do: false

  # nur Ganzzahlen und ganzzahlig abgeschlossene Operationen?
  defp int_only?(f) when is_float(f), do: false
  defp int_only?({:var, _}), do: true
  defp int_only?({:op2, op, a, b}), do: op in @iops2 and int_only?(a) and int_only?(b)
  defp int_only?({:op1, op, a}), do: op in @iops1 and int_only?(a)
  defp int_only?(t) when is_tuple(t), do: int_only?(Tuple.to_list(t))
  defp int_only?(l) when is_list(l), do: Enum.all?(l, &int_only?/1)
  defp int_only?(_), do: true

  # --- Modi ---------------------------------------------------------------
  #
  # Je Kopfposition mit Variable V: der erste Gebrauch von V im Rumpf –
  # gelesen (Vergleich, rechte Seite von is) heißt Eingabe, bestimmt (linke
  # Seite von is) Ausgabe, als Argument j eines Aufrufs: wie Position j des
  # Gerufenen; in `=` legt er nichts fest. Für alle Prädikate des Schritts
  # zugleich; Widerspruch: das Prädikat fällt heraus.

  defp global_modes(parsed, ext) do
    ev =
      for {key, p} <- parsed,
          {head, goals} <- p.clauses,
          {a, k} <- Enum.with_index(head),
          match?({:var, _}, a),
          not anon?(a),
          e = first_use(a, goals),
          e not in [nil, :none] do
        case e do
          {:as, ck, j} when not is_map_key(parsed, ck) -> {{key, k}, ext.(ck).modes[j]}
          _ -> {{key, k}, e}
        end
      end

    {m0, bad} =
      Enum.reduce(ev, {%{}, []}, fn
        {pos, e}, {m, bad} when e in [:in, :out] -> put_mode(m, pos, e, bad)
        _, acc -> acc
      end)

    case fix_modes(m0, ev, bad) do
      {m, []} ->
        # unbestimmt (nirgends gelesen): Ausgabe – etwa gcd(X, 0, X); passt
        # ein Aufruf nicht dazu, nimmt ihn der Interpreter
        m =
          for {key, p} <- parsed,
              k <- 0..(p.arity - 1),
              into: m,
              do: {{key, k}, Map.get(m, {key, k}, :out)}

        {:ok, m}

      {_, bad} ->
        {:bad, bad |> Enum.map(&elem(&1, 0)) |> Enum.uniq()}
    end
  end

  defp put_mode(m, pos, e, bad) do
    case m do
      %{^pos => ^e} -> {m, bad}
      %{^pos => _} -> {m, [pos | bad]}
      _ -> {Map.put(m, pos, e), bad}
    end
  end

  defp fix_modes(m, ev, bad) do
    {m2, bad2} =
      Enum.reduce(ev, {m, bad}, fn
        {pos, {:as, ck, j}}, {acc, bad} ->
          if Map.has_key?(acc, {ck, j}),
            do: put_mode(acc, pos, acc[{ck, j}], bad),
            else: {acc, bad}

        _, acc ->
          acc
      end)

    if m2 == m, do: {m, Enum.uniq(bad2)}, else: fix_modes(m2, ev, bad2)
  end

  # nil: kommt nicht vor; :none: kommt vor, legt aber nichts fest
  defp first_use(_v, []), do: nil
  defp first_use(v, [g | gs]), do: use_in(v, g) || first_use(v, gs)

  defp use_in(v, {:cmp, _, a, b}), do: if(v in (vars(a) ++ vars(b)), do: :in)

  defp use_in(v, {:is, l, r}) do
    cond do
      v in vars(r) -> :in
      l == v -> :out
      true -> nil
    end
  end

  defp use_in(v, {:unify, a, b}), do: if(v == a or v == b, do: :none)

  defp use_in(v, {:call, ck, as}) do
    case Enum.find_index(as, &(&1 == v)) do
      nil -> nil
      j -> {:as, ck, j}
    end
  end

  defp use_in(v, {:ite, c, t, e}), do: first_use(v, c) || first_use(v, t) || first_use(v, e)
  defp use_in(v, {:not, g}), do: first_use(v, g)
  defp use_in(_, _), do: nil

  # --- Datenfluss je Klausel: Zwischenform für die Codeerzeugung ----------
  #
  # d: die bestimmten Variablen (MapSet) oder :all hinter einem sicheren
  # Scheitern (alles Weitere ist toter Code). {:poison, V}: V ist nur in
  # einem Zweig eines If-then-else bestimmt – jeder spätere Gebrauch macht
  # die Klausel unübersetzbar.

  # modes: die des Prädikats; cm: Gerufener -> seine Modi
  defp flow({head, goals}, modes, cm) do
    {hin, d} =
      head
      |> Enum.with_index()
      |> Enum.filter(fn {_, k} -> modes[k] == :in end)
      |> Enum.map_reduce(MapSet.new(), fn {a, k}, d ->
        cond do
          is_number(a) -> {{k, {:const, a}}, d}
          anon?(a) -> {{k, :ignore}, d}
          MapSet.member?(d, a) -> {{k, {:eq, a}}, d}
          true -> {{k, {:bind, a}}, MapSet.put(d, a)}
        end
      end)

    hout =
      for {a, k} <- Enum.with_index(head), modes[k] == :out do
        cond do
          is_number(a) -> {k, {:const, a}}
          anon?(a) -> throw(:no)
          true -> {k, {:var, a}}
        end
      end

    {irs, d} = flow_seq(goals, d, cm)
    for {_, {:var, v}} <- hout, not defd?(d, v), do: throw(:no)
    %{hin: hin, hout: hout, goals: irs}
  end

  defp flow_seq(_, :all, _), do: {[], :all}
  defp flow_seq([], d, _), do: {[], d}

  defp flow_seq([g | gs], d, m) do
    {ir, d1} = goal_flow(g, d, m)
    {irs, d2} = flow_seq(gs, d1, m)
    {[ir | irs], d2}
  end

  defp defd?(:all, _), do: true
  defp defd?(d, v), do: MapSet.member?(d, v)

  defp add(d, v) do
    if MapSet.member?(d, {:poison, v}), do: throw(:no)
    MapSet.put(d, v)
  end

  defp meet(:all, d), do: d
  defp meet(d, :all), do: d

  defp meet(a, b) do
    i = MapSet.intersection(a, b)

    for x <- MapSet.difference(MapSet.union(a, b), i), into: i do
      case x do
        {:poison, _} -> x
        v -> {:poison, v}
      end
    end
  end

  defp new_vars(d1, d0),
    do: for({:var, _} = v <- MapSet.difference(d1, d0), do: v) |> Enum.sort()

  defp known?(t, d), do: is_number(t) or defd?(d, t)

  defp goal_flow(:cut, d, _), do: {:cut, d}
  defp goal_flow(true, d, _), do: {true, d}
  defp goal_flow(:fail, _d, _), do: {:fail, :all}

  defp goal_flow({:cmp, op, a, b}, d, _) do
    defined!(vars(a) ++ vars(b), d)
    {{:cmp, op, a, b}, d}
  end

  defp goal_flow({:is, l, r}, d, _) do
    defined!(vars(r), d)

    cond do
      known?(l, d) -> {{:is_eq, l, r}, d}
      anon?(l) -> {{:is_eq, :ignore, r}, d}
      true -> {{:is_def, l, r}, add(d, l)}
    end
  end

  defp goal_flow({:unify, a, b}, d, _) do
    cond do
      a == b or anon?(a) or anon?(b) -> {:u_nop, d}
      known?(a, d) and known?(b, d) -> {{:u_eq, a, b}, d}
      known?(a, d) -> {{:u_def, b, a}, add(d, b)}
      known?(b, d) -> {{:u_def, a, b}, add(d, a)}
      true -> throw(:no)
    end
  end

  defp goal_flow({:call, ck, as}, d, cm) do
    modes = cm.(ck)
    ins = for {a, k} <- Enum.with_index(as), modes[k] == :in, do: a
    defined!(Enum.filter(ins, &match?({:var, _}, &1)), d)

    {outs, d2} =
      as
      |> Enum.with_index()
      |> Enum.filter(fn {_, k} -> modes[k] == :out end)
      |> Enum.map_reduce(d, fn {a, _}, acc ->
        cond do
          known?(a, d) -> {{:eq, a}, acc}
          anon?(a) -> {:ignore, acc}
          defd?(acc, a) -> throw(:no)
          true -> {{:def, a}, add(acc, a)}
        end
      end)

    {{:call, ck, ins, outs}, d2}
  end

  # die Bedingung sieht d, Then sieht zusätzlich, was die Bedingung bestimmt,
  # Else nur d; danach gilt, was beide Zweige bestimmen
  defp goal_flow({:ite, c, t, e}, d, m) do
    {ci, dc} = flow_seq(c, d, m)
    if dc == :all, do: throw(:no)
    {ti, dt} = flow_seq(t, dc, m)
    {ei, de} = flow_seq(e, d, m)
    dn = meet(dt, de)
    nvars = if dn == :all, do: :dead, else: new_vars(dn, d)
    {{:ite, ci, new_vars(dc, d), ti, ei, nvars}, dn}
  end

  # was G bestimmt, gilt danach nicht
  defp goal_flow({:not, g}, d, m) do
    {gi, _} = flow_seq(g, d, m)
    {{:not, gi}, d}
  end

  defp defined!(vs, d), do: for(v <- vs, not defd?(d, v), do: throw(:no))

  # --- Ausschließlichkeit -------------------------------------------------

  defp exclusive!(irs, num) do
    pairs = for {a, i} <- Enum.with_index(irs), {b, j} <- Enum.with_index(irs), i < j, do: {a, b}
    for {a, b} <- pairs, not exclusive?(a, b, num), do: throw(:no)
    :ok
  end

  # a vor b: hat a eine Lösung, scheitert b sicher (ohne Fehler davor)
  defp exclusive?(a, b, num) do
    :cut in a.goals or consts_differ?(a, b) or const_vs_guard?(a, b, num) or
      complementary?(a, b, num)
  end

  # Vergleiche und `=` am Anfang des Rumpfs
  defp guards(c),
    do: Enum.take_while(c.goals, &(match?({:cmp, _, _, _}, &1) or match?({:u_eq, _, _}, &1)))

  # die Wächter von b, die b erreicht, ohne dass einer davor werfen kann
  defp reachable(c, num) do
    Enum.reduce_while(guards(c), [], fn g, acc ->
      if safe?(g, num), do: {:cont, [g | acc]}, else: {:halt, [g | acc]}
    end)
    |> Enum.reverse()
  end

  defp safe?({:u_eq, _, _}, _), do: true
  defp safe?({:cmp, _, x, y}, num), do: safe_ex?(x, num) and safe_ex?(y, num)

  defp safe_ex?(n, _) when is_number(n), do: true
  defp safe_ex?({:var, _}, _), do: true

  defp safe_ex?({:op2, op, a, b}, false) when op in @total2,
    do: safe_ex?(a, false) and safe_ex?(b, false)

  defp safe_ex?({:op1, op, a}, false) when op in @total1, do: safe_ex?(a, false)
  defp safe_ex?(_, _), do: false

  # Kopfeingaben, mit `V = c` am Anfang als Konstante
  defp eff_hin(c) do
    eqs =
      for {:u_eq, x, y} <- guards(c),
          {v, n} <- [{x, y}, {y, x}],
          is_number(n),
          into: %{},
          do: {v, n}

    Enum.map(c.hin, fn
      {k, {:bind, v}} = e -> if Map.has_key?(eqs, v), do: {k, {:const, eqs[v]}}, else: e
      e -> e
    end)
  end

  defp consts_differ?(a, b) do
    Enum.any?(Enum.zip(eff_hin(a), eff_hin(b)), fn
      {{k, {:const, x}}, {k, {:const, y}}} -> x !== y
      _ -> false
    end)
  end

  # a hat an k die Konstante c, b dort die Variable V und am Anfang einen
  # Wächter nur über V, der für V = c falsch ist
  defp const_vs_guard?(a, b, num) do
    Enum.any?(Enum.zip(eff_hin(a), b.hin), fn
      {{k, {:const, c}}, {k, {:bind, v}}} ->
        Enum.any?(reachable(b, num), fn g ->
          Enum.all?(guard_vars(g), &(&1 == v)) and guard_val(g, %{v => c}) == false
        end)

      _ ->
        false
    end)
  end

  defp guard_vars({:cmp, _, x, y}), do: vars(x) ++ vars(y)
  defp guard_vars({:u_eq, x, y}), do: vars(x) ++ vars(y)

  defp guard_val({:cmp, op, x, y}, env) do
    PrologEx.compare(op, ceval(x, env), ceval(y, env))
  rescue
    _ -> :unknown
  catch
    _ -> :unknown
  end

  defp guard_val({:u_eq, x, y}, env), do: ceval(x, env) === ceval(y, env)

  defp ceval(n, _) when is_number(n), do: n
  defp ceval({:var, _} = v, env), do: Map.fetch!(env, v)
  defp ceval({:op2, op, a, b}, env), do: PrologEx.Arith.op2(op, ceval(a, env), ceval(b, env))
  defp ceval({:op1, op, a}, env), do: PrologEx.Arith.op1(op, ceval(a, env))

  # einander ausschließende Vergleiche am Anfang (über Eingaben des Kopfs)
  defp complementary?(a, b, num) do
    ga = for g <- guards(a), n = norm(g, a), n != nil, do: n
    gb = for g <- reachable(b, num), n = norm(g, b), n != nil, do: n
    Enum.any?(ga, fn x -> Enum.any?(gb, &complement?(x, &1)) end)
  end

  # Vergleich mit Positionen statt Variablen; < und =< (> und >= gedreht)
  defp norm({:cmp, op, x, y}, c) do
    pos = for {k, {:bind, v}} <- c.hin, into: %{}, do: {v, {:pos, k}}

    with {:ok, x} <- subst_pos(x, pos), {:ok, y} <- subst_pos(y, pos) do
      case op do
        ">" -> {y, "<", x}
        ">=" -> {y, "=<", x}
        _ -> {x, op, y}
      end
    else
      _ -> nil
    end
  end

  defp norm(_, _), do: nil

  defp subst_pos({:var, _} = v, pos), do: if(Map.has_key?(pos, v), do: {:ok, pos[v]}, else: :no)

  defp subst_pos({:op2, op, a, b}, pos) do
    with {:ok, a} <- subst_pos(a, pos), {:ok, b} <- subst_pos(b, pos), do: {:ok, {:op2, op, a, b}}
  end

  defp subst_pos({:op1, op, a}, pos) do
    with {:ok, a} <- subst_pos(a, pos), do: {:ok, {:op1, op, a}}
  end

  defp subst_pos(n, _), do: {:ok, n}

  defp complement?({a, "<", b}, {b, "=<", a}), do: true
  defp complement?({a, "=<", b}, {b, "<", a}), do: true
  defp complement?({a, "=:=", b}, {a, "=\\=", b}), do: true
  defp complement?({a, "=:=", b}, {b, "=\\=", a}), do: true
  defp complement?({a, "=\\=", b}, {a, "=:=", b}), do: true
  defp complement?({a, "=\\=", b}, {b, "=:=", a}), do: true
  defp complement?(_, _), do: false

  # --- Codeerzeugung (Elixir-AST) und Laden -------------------------------
  #
  # p(Eingaben..., B) -> {B, Ausgaben...} | B | -B-1. B >= 0: Inferenzen bis
  # zum nächsten Prüfpunkt (tick/0). Erfolg ist ein Tupel; Scheitern die
  # bloße Zahl B, nach einem Schnitt -B-1 (die nächste Klausel nicht mehr
  # versuchen). Scheitern legt also nichts auf den Heap: bei tiefer
  # Rekursion durchsucht jede Garbage Collection den ganzen Stack, jede
  # vermiedene zählt.
  #
  # Teilfolgen (Bedingung, Zweige, \+) enden mit {B, Variablen...}, eine
  # Bedingung ohne neue Variablen mit -B-1 (in ihr gibt es kein Scheitern
  # nach Schnitt); scheitern sie, mit B. Nach den Zweigen folgt der Rest der
  # Klausel einmal. Enthält ein Zweig einen Schnitt, folgt der Rest in jedem
  # Zweig (der Schnitt ändert, wie danach Scheitern aussieht).

  # Module: je stark zusammenhängender Komponente des Aufrufgraphen eines,
  # Gerufene zuerst – so kann der Name (Hash des Inhalts, samt der Namen
  # gerufener Module) jedes Moduls feststehen, bevor es ein Rufer braucht.
  # Im Modul je Prädikat j: e<j> (Eintritt), p<j> (Klauselwahl), c<j>_<i>.
  defp build(s, how) do
    s
    |> sccs()
    |> Enum.reduce({%{}, []}, fn scc, {done, shown} ->
      infos =
        scc
        |> Enum.with_index()
        |> Enum.map(fn {key, j} ->
          p = s.parsed[key]
          ins = for k <- 0..(p.arity - 1), s.modes[{key, k}] == :in, do: k
          outs = for k <- 0..(p.arity - 1), s.modes[{key, k}] == :out, do: k

          %{
            key: key,
            j: j,
            ins: ins,
            outs: outs,
            clauses: s.irs[key],
            source: p.source,
            num: MapSet.member?(s.num, key),
            deps: p.deps
          }
        end)

      local = Map.new(infos, &{&1.key, {:local, :"p#{&1.j}"}})

      remote =
        for i <- infos, d <- i.deps, not Map.has_key?(local, d), into: %{} do
          case done do
            %{^d => {{mod, _, pf, _}, _, _}} -> {d, {:remote, mod, pf}}
            _ -> (e = s.ext.(d)) && {d, {:remote, e.mod, e.p}}
          end
        end

      targets = Map.merge(remote, local)

      hash =
        :crypto.hash(
          :sha256,
          :erlang.term_to_binary(
            {Enum.map(infos, &{&1.source, &1.ins, &1.outs, &1.num}), Enum.sort(remote)}
          )
        )
        |> Base.encode16(case: :lower)
        |> binary_part(0, 20)

      mod = Module.concat(PrologEx.Jit.Code, "P" <> hash)
      ast = gen(mod, infos, targets)

      case how do
        :show ->
          {done, [Macro.to_string(ast) | shown]}

        :load ->
          unless Code.ensure_loaded?(mod) do
            {_, _} = Code.with_diagnostics([log: false], fn -> Code.compile_quoted(ast) end)
          end

          done =
            for i <- infos,
                into: done,
                do:
                  {i.key,
                   {{mod, :"e#{i.j}", :"p#{i.j}", i.deps},
                    if(i.num, do: {:num, i.ins}, else: i.ins), i.outs}}

          {done, shown}
      end
    end)
    |> case do
      {_, shown} when how == :show -> shown |> Enum.reverse() |> Enum.join("\n")
      {done, _} -> done
    end
  end

  defp sccs(s) do
    g = :digraph.new()

    try do
      for k <- Map.keys(s.parsed), do: :digraph.add_vertex(g, k)

      for {k, p} <- s.parsed,
          d <- p.deps,
          Map.has_key?(s.parsed, d),
          do: :digraph.add_edge(g, k, d)

      c = :digraph_utils.condensation(g)

      try do
        # Rufer vor Gerufenen; umgekehrt: Gerufene zuerst
        c |> :digraph_utils.topsort() |> Enum.reverse() |> Enum.map(&Enum.sort/1)
      after
        :digraph.delete(c)
      end
    after
      :digraph.delete(g)
    end
  end

  defp gen(mod, infos, targets) do
    funs =
      Enum.flat_map(infos, fn info ->
        ins = Enum.map(info.ins, &in_var/1)
        n = length(info.clauses)
        e = :"e#{info.j}"
        pf = :"p#{info.j}"

        clause_funs =
          info.clauses
          |> Enum.with_index(1)
          |> Enum.map(fn {c, i} -> gen_clause(c, i, info, targets) end)

        dispatch = gen_dispatch(1, n, ins, info.j)

        [
          quote do
            def unquote(e)(unquote_splicing(ins), b) do
              unquote(pf)(unquote_splicing(ins), b)
            rescue
              ArithmeticError -> PrologEx.Error.evaluation!("undefined")
              SystemLimitError -> PrologEx.Error.resource!("memory")
            end
          end,
          quote(do: def(unquote(pf)(unquote_splicing(ins), b), do: unquote(dispatch)))
          | clause_funs
        ]
      end)

    quote do
      defmodule unquote(mod) do
        @moduledoc false
        @compile {:no_warn_undefined, PrologEx.Jit}
        unquote_splicing(funs)
      end
    end
  end

  defp gen_dispatch(n, n, ins, j), do: ccall(j, n, ins)

  defp gen_dispatch(i, n, ins, j) do
    quote do
      case unquote(ccall(j, i, ins)) do
        b when is_integer(b) and b >= 0 -> unquote(gen_dispatch(i + 1, n, ins, j))
        r -> r
      end
    end
  end

  # Aufruf der Klauselfunktion c<j>_<i>(Eingaben..., b)
  defp ccall(j, i, ins), do: {:"c#{j}_#{i}", [], ins ++ [Macro.var(:b, __MODULE__)]}

  defp gen_clause(c, i, info, targets) do
    ins = Enum.map(info.ins, &in_var/1)
    vmap = var_map(c)
    st = %{vmap: vmap, cut: false, local: false, num: info.num, hout: c.hout, targets: targets}
    body = gen_goals(c.goals ++ [:end], st)
    head = gen_head(c.hin, vmap, body)
    name = :"c#{info.j}_#{i}"

    quote do
      defp unquote(name)(unquote_splicing(ins), b) do
        _ = b
        unquote(head)
      end
    end
  end

  defp in_var(k), do: Macro.var(:"i#{k}", __MODULE__)

  defp var_map(c) do
    (collect(c.hin) ++ collect(c.hout) ++ collect(c.goals))
    |> Enum.uniq()
    |> Enum.with_index()
    |> Map.new(fn {v, j} -> {v, Macro.var(:"v#{j}", __MODULE__)} end)
  end

  defp collect({:var, _} = v), do: [v]
  defp collect(t) when is_tuple(t), do: collect(Tuple.to_list(t))
  defp collect(l) when is_list(l), do: Enum.flat_map(l, &collect/1)
  defp collect(_), do: []

  defp gen_head([], _vmap, body), do: body

  defp gen_head([{k, spec} | rest], vmap, body) do
    i = in_var(k)
    inner = gen_head(rest, vmap, body)

    case spec do
      :ignore ->
        inner

      {:const, c} ->
        quote(do: if(unquote(i) === unquote(c), do: unquote(inner), else: b))

      {:bind, v} ->
        quote do
          unquote(vmap[v]) = unquote(i)
          unquote(inner)
        end

      {:eq, v} ->
        quote(do: if(unquote(i) === unquote(vmap[v]), do: unquote(inner), else: b))
    end
  end

  # Scheitern: nach einem Schnitt (nicht lokal in einer Bedingung oder
  # unter \+) -b-1, sonst b
  defp failure(%{local: false, cut: true}), do: quote(do: -b - 1)
  defp failure(_), do: quote(do: b)

  # Ergebnis eines Aufrufs: Scheitern (auch nach Schnitt) in b
  defp unfail(r), do: quote(do: if(unquote(r) >= 0, do: unquote(r), else: -unquote(r) - 1))

  # eine Inferenz verbrauchen (Prüfpunkt bei 0)
  defp dec_ast, do: quote(do: b = if(b == 0, do: PrologEx.Jit.tick() - 1, else: b - 1))

  defp counted(rest) do
    quote do
      unquote(dec_ast())
      unquote(rest)
    end
  end

  defp test(t, rest, st),
    do: counted(quote(do: if(unquote(t), do: unquote(rest), else: unquote(failure(st)))))

  defp vs(vars, st), do: Enum.map(vars, &Map.fetch!(st.vmap, &1))

  defp gen_goals([:end], st) do
    outs = for {_, spec} <- st.hout, do: out_ast(spec, st.vmap)
    quote(do: {b, unquote_splicing(outs)})
  end

  defp gen_goals([{:yield, :cond, []}], _st), do: quote(do: -b - 1)
  defp gen_goals([{:yield, _, vars}], st), do: quote(do: {b, unquote_splicing(vs(vars, st))})

  # Schnitt in einer Bedingung oder unter \+: lokal, ohne Wirkung
  defp gen_goals([:cut | gs], %{local: false} = st), do: gen_goals(gs, %{st | cut: true})
  defp gen_goals([:cut | gs], st), do: gen_goals(gs, st)
  defp gen_goals([true | gs], st), do: counted(gen_goals(gs, st))
  defp gen_goals([:fail | _], st), do: counted(failure(st))
  defp gen_goals([:u_nop | gs], st), do: counted(gen_goals(gs, st))

  defp gen_goals([{:cmp, op, x, y} | gs], st),
    do: test(cmp_ast(op, ex(x, st), ex(y, st), st), gen_goals(gs, st), st)

  defp gen_goals([{:is_def, l, r} | gs], st) do
    counted(
      quote do
        unquote(st.vmap[l]) = unquote(ex(r, st))
        unquote(gen_goals(gs, st))
      end
    )
  end

  defp gen_goals([{:is_eq, :ignore, r} | gs], st) do
    counted(
      quote do
        _ = unquote(ex(r, st))
        unquote(gen_goals(gs, st))
      end
    )
  end

  defp gen_goals([{:is_eq, l, r} | gs], st),
    do: test(quote(do: unquote(ex(r, st)) === unquote(term_ast(l, st))), gen_goals(gs, st), st)

  defp gen_goals([{:u_eq, a, b} | gs], st),
    do:
      test(
        quote(do: unquote(term_ast(a, st)) === unquote(term_ast(b, st))),
        gen_goals(gs, st),
        st
      )

  defp gen_goals([{:u_def, v, t} | gs], st) do
    counted(
      quote do
        unquote(st.vmap[v]) = unquote(term_ast(t, st))
        unquote(gen_goals(gs, st))
      end
    )
  end

  defp gen_goals([{:call, ck, ins, outs} | gs], st) do
    args = Enum.map(ins, &term_ast(&1, st))

    {pats, checks} =
      outs
      |> Enum.with_index()
      |> Enum.map(fn
        {{:def, v}, _} ->
          {st.vmap[v], nil}

        {:ignore, _} ->
          {Macro.var(:_, nil), nil}

        {{:eq, t}, j} ->
          tmp = Macro.var(:"o#{j}", __MODULE__)
          {tmp, quote(do: unquote(tmp) === unquote(term_ast(t, st)))}
      end)
      |> Enum.unzip()

    checks = Enum.reject(checks, &is_nil/1)
    rest = gen_goals(gs, st)

    rest =
      case checks do
        [] ->
          rest

        _ ->
          t = Enum.reduce(checks, fn x, acc -> quote(do: unquote(acc) and unquote(x)) end)
          quote(do: if(unquote(t), do: unquote(rest), else: unquote(failure(st))))
      end

    r = Macro.var(:r, __MODULE__)

    counted(
      quote do
        case unquote(call_ast(st.targets[ck], args)) do
          {b, unquote_splicing(pats)} ->
            unquote(rest)

          unquote(r) ->
            b = unquote(unfail(r))
            unquote(failure(st))
        end
      end
    )
  end

  defp gen_goals([{:not, g} | gs], st) do
    inner = gen_goals(g ++ [{:yield, :cond, []}], %{st | local: true})

    counted(
      quote do
        case unquote(inner) do
          b when b >= 0 ->
            unquote(gen_goals(gs, st))

          nb ->
            b = -nb - 1
            unquote(failure(st))
        end
      end
    )
  end

  defp gen_goals([{:ite, c, cvars, t, e, nvars} | gs], st) do
    {th, el} =
      if nvars == :dead or (not st.local and (cut_in?(t) or cut_in?(e))),
        do: {gen_goals(t ++ gs, st), gen_goals(e ++ gs, st)},
        else:
          {gen_goals(t ++ [{:yield, :join, nvars}], st),
           gen_goals(e ++ [{:yield, :join, nvars}], st)}

    cond_code = gen_goals(c ++ [{:yield, :cond, cvars}], %{st | local: true})

    branches =
      case cvars do
        [] ->
          quote do
            case unquote(cond_code) do
              b when b >= 0 ->
                unquote(el)

              nb ->
                b = -nb - 1
                unquote(th)
            end
          end

        _ ->
          quote do
            case unquote(cond_code) do
              {b, unquote_splicing(vs(cvars, st))} -> unquote(th)
              b -> unquote(el)
            end
          end
      end

    if nvars == :dead or (not st.local and (cut_in?(t) or cut_in?(e))) do
      branches
    else
      quote do
        case unquote(branches) do
          {b, unquote_splicing(vs(nvars, st))} -> unquote(gen_goals(gs, st))
          r -> r
        end
      end
    end
  end

  defp call_ast({:local, f}, args), do: {f, [], args ++ [Macro.var(:b, __MODULE__)]}

  defp call_ast({:remote, mod, f}, args),
    do: quote(do: unquote(mod).unquote(f)(unquote_splicing(args), b))

  defp cut_in?(gs) do
    Enum.any?(gs, fn
      :cut -> true
      {:ite, _, _, t, e, _} -> cut_in?(t) or cut_in?(e)
      _ -> false
    end)
  end

  defp out_ast({:const, c}, _vmap), do: c
  defp out_ast({:var, v}, vmap), do: vmap[v]

  defp term_ast(n, _st) when is_number(n), do: n
  defp term_ast(v, st), do: Map.fetch!(st.vmap, v)

  # Ausdruck: nur Ganzzahlen – + - * direkt; sonst genau wie der
  # Interpreter (PrologEx.Arith)
  defp ex(n, _st) when is_number(n), do: n
  defp ex({:var, _} = v, st), do: Map.fetch!(st.vmap, v)

  defp ex({:op2, op, a, b}, %{num: false} = st) when op in ~w(+ - *),
    do: {String.to_atom(op), [], [ex(a, st), ex(b, st)]}

  defp ex({:op2, op, a, b}, st),
    do: quote(do: PrologEx.Arith.op2(unquote(op), unquote(ex(a, st)), unquote(ex(b, st))))

  defp ex({:op1, "-", a}, %{num: false} = st), do: quote(do: -unquote(ex(a, st)))
  defp ex({:op1, "+", a}, %{num: false} = st), do: ex(a, st)
  defp ex({:op1, op, a}, st), do: quote(do: PrologEx.Arith.op1(unquote(op), unquote(ex(a, st))))

  # Vergleich: nur Ganzzahlen direkt, sonst wie der Interpreter
  defp cmp_ast(op, x, y, %{num: true}),
    do: quote(do: PrologEx.compare(unquote(op), unquote(x), unquote(y)))

  defp cmp_ast("<", x, y, _), do: quote(do: unquote(x) < unquote(y))
  defp cmp_ast(">", x, y, _), do: quote(do: unquote(x) > unquote(y))
  defp cmp_ast("=<", x, y, _), do: quote(do: unquote(x) <= unquote(y))
  defp cmp_ast(">=", x, y, _), do: quote(do: unquote(x) >= unquote(y))
  defp cmp_ast("=:=", x, y, _), do: quote(do: unquote(x) === unquote(y))
  defp cmp_ast("=\\=", x, y, _), do: quote(do: unquote(x) !== unquote(y))

  # --- Laufzeit -----------------------------------------------------------

  @tick_key :prolog_ex_jit
  @heap_key :prolog_ex_jit_heap

  @doc false
  # Prüfpunkt: der laufende Block ist verbraucht. Die Maschine hat vorher
  # {Blockgröße, Prüffunktion} hinterlegt; die Prüffunktion verbucht den
  # Block, prüft die Grenzen (wirft wie der Interpreter) und gibt den
  # nächsten Block zurück (>= 1)
  def tick do
    {chunk, check} = Process.get(@tick_key)
    next = check.(chunk)
    Process.put(@tick_key, {next, check})
    deep_stack()
    next
  end

  # Tiefe Rekursion: jede Garbage Collection durchsucht den ganzen Stack.
  # Ist er tief, bekommt der Heap Luft im Verhältnis (min_heap_size), damit
  # die Collections selten bleiben; nach dem Aufruf wieder wie vorher
  @deep 50_000
  defp deep_stack do
    {:stack_size, s} = Process.info(self(), :stack_size)

    if s > @deep do
      want = 4 * s

      case Process.get(@heap_key) do
        nil ->
          Process.put(@heap_key, {Process.flag(:min_heap_size, want), want})

        {old, have} when want > 2 * have ->
          Process.flag(:min_heap_size, want)
          Process.put(@heap_key, {old, want})

        _ ->
          :ok
      end
    end
  end

  @doc false
  # ein übersetztes Prädikat rufen: {:ok, Ausgaben, verbraucht} | {:fail, verbraucht}
  def run({mod, entry, _, _}, ins, chunk, check) do
    Process.put(@tick_key, {chunk, check})

    try do
      case apply(mod, entry, ins ++ [chunk]) do
        r when is_tuple(r) ->
          [b | outs] = Tuple.to_list(r)
          {:ok, outs, used(b)}

        b when b >= 0 ->
          {:fail, used(b)}

        b ->
          {:fail, used(-b - 1)}
      end
    after
      Process.delete(@tick_key)

      case Process.delete(@heap_key) do
        nil -> :ok
        {old, _} -> Process.flag(:min_heap_size, old)
      end
    end
  end

  defp used(b) do
    {chunk, _} = Process.get(@tick_key)
    chunk - b
  end
end
