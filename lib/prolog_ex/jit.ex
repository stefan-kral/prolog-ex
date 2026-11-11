defmodule PrologEx.Jit do
  @moduledoc """
  Übersetzt deterministische Prädikate über Zahlen und Listen in BEAM-Code.
  Innerhalb des übersetzten Stücks liegen die Werte in Erlang-Variablen:
  keine Bindungen, kein Zielstapel, keine Kompaktierung. Gebunden wird nur
  an den Rändern: beim Aufruf die Eingaben lesen (Zahlen, echte Listen
  einmal aufgelöst, sonst Terme, die nur durchgereicht werden), am Ende
  die Ausgaben binden (frische Variablen). Passt ein Aufruf nicht dazu,
  nimmt ihn der Interpreter.

  Was übersetzt wird – jede Klausel:

    * Kopf: Zahlen, Variablen, `[]`, `[E1, ..., En | T]` (E Zahlen oder
      Variablen, T Variable oder `[]`)
    * Rumpf: `V is E`, arithmetische Vergleiche, `X = Y` (Terme wie im
      Kopf), `!`, `true`, `fail`, `( C -> T ; E )`, `( C -> T )`, `\\+ G`
      und Aufrufe des Prädikats selbst oder anderer übersetzter (Argumente
      Terme wie im Kopf)
    * E aus Zahlen, Variablen, `pi`, `e`, `epsilon` und den auswertbaren
      Funktoren (außer random/random_float)

  Werte haben einen Typ: Zahl, Liste, Liste von Zahlen oder beliebig
  (nur durchgereicht – auch eine ungebundene Variable). Was ein Wert sein
  muss, ergibt sich aus dem Gebrauch (gerechnet: Zahl; zerlegt: Liste;
  verglichen: Zahl oder Liste von Zahlen) und wird für Eingaben beim
  Aufruf geprüft. Ausgabetypen dürfen von Eingaben abhängen: app/3 gibt
  eine Liste, wenn das zweite Argument eine ist.

  Kommen nur Ganzzahlen und ganzzahlige Operationen vor (+ - * // mod rem
  div min max >> << /\\ \\/ xor gcd, einstellig - + abs sign msb \\),
  rechnet der Code mit + - * direkt und nimmt nur ganzzahlige Zahlen;
  sonst rechnet er alles mit PrologEx.Arith (wie der Interpreter, auch
  rationale Zwischenwerte) und nimmt Ganzzahlen und Floats.

  Das Prädikat ist nachweislich deterministisch: je zwei Klauseln
  schließen sich aus – durch einen Schnitt in der früheren, verschiedene
  Muster im Kopf (Konstanten, `[]` gegen `[_|_]`; auch `X = c` am Anfang
  des Rumpfs), einen Vergleich am Anfang, der für die Konstante der
  anderen falsch ist, oder einander ausschließende Vergleiche am Anfang
  (`X > 0` / `X =< 0`). Vor dem ausschließenden Vergleich der späteren
  Klausel darf nichts einen Fehler werfen können (der Interpreter würde
  sie beim Zurücksetzen versuchen).

  Die Modi (Eingabe/Ausgabe je Argument): steht eine Kopfvariable zuerst
  in einem Vergleich oder rechts in `is`, ist sie Eingabe, links in `is`
  Ausgabe, als Argument eines Aufrufs wie dort. Die übrigen Positionen
  werden durchprobiert, mehr Ausgaben zuerst, Ausgaben eher rechts.

  Gleich wie im Interpreter: Antworten, Fehler (dieselben
  Arithmetik-Funktionen), Inferenzen (jeder Aufruf und jedes eingebaute
  Ziel zählt eins; Schnitt, `,`, `;` und `->` nicht) und Grenzen
  (Inferenz-, Zeit-, Speichergrenzen an denselben Prüfpunkten, siehe
  tick/0).

  Die Module heißen nach einem Hash ihres Inhalts: dasselbe Programm
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
  @type_tests ~w(var nonvar atom number integer float atomic compound callable is_list)
  @consts %{"pi" => :math.pi(), "e" => :math.exp(1), "epsilon" => 2.220446049250313e-16}
  # höchstens so viele Positionen ohne Hinweis werden durchprobiert
  @max_enum 6
  @max_vars 200
  # so viele Ziele (ohne Rekursion), damit sich der Eintritt lohnt
  @entry_size 1
  @raise_key :prolog_ex_jit_raise
  @why_key :prolog_ex_jit_why
  @soft_key :prolog_ex_jit_soft

  # --- Schnittstelle ------------------------------------------------------

  @doc """
  Übersetzt die Prädikate eines Ladeschritts (eines Moduls), soweit sie
  passen. `preds`: [{{name, stelligkeit}, [{kopf, rumpf}]}]. `ext`: für ein
  schon geladenes, übersetztes, statisches Prädikat außerhalb des Schritts
  `%{mod: modul, p: funktion, sig: signatur}`, sonst nil. `dynamic`: die
  dynamischen unter `preds` – andere dürfen sie nicht rufen (nach einem
  assert wäre ihr Code falsch).

  Ergebnis: %{{name, stelligkeit} => {{modul, eintritt, p, gerufen, sig},
  eingaben, ausgaben}}: eingaben [{k, prüfung}] mit prüfung :int, :num,
  :list, :ilist (Ganzzahlen), :nlist (Zahlen) oder :any; ausgaben [k];
  gerufen: die anderen Prädikate, die der Code direkt ruft.
  """
  def compile_batch(preds, ext \\ fn _ -> nil end, dynamic \\ MapSet.new()) do
    case settle(preds, ext, dynamic) do
      %{solved: solved} when map_size(solved) == 0 -> %{}
      s -> build(s, :load)
    end
  end

  @doc """
  Wie compile_batch/3, aber nur die Analyse: %{{name, stelligkeit} =>
  {:ok, signatur} | {:no, grund}} (für jit_listing).
  """
  def explain(preds, ext \\ fn _ -> nil end, dynamic \\ MapSet.new()) do
    s = settle(preds, ext, dynamic)

    Map.new(preds, fn {k, _} ->
      case s.solved do
        %{^k => r} -> {k, {:ok, r.sig}}
        _ -> {k, {:no, Map.get(s.why, k, "?")}}
      end
    end)
  end

  @doc "Ein einzelnes Prädikat (Aufrufe nur von sich selbst), sonst :no"
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
      %{solved: solved} when map_size(solved) == 0 -> :no
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

  # --- Ablauf -------------------------------------------------------------
  #
  # Zerlegen; ganzzahlig oder nicht je zusammenhängendem Aufrufgraphen;
  # dann die stark zusammenhängenden Komponenten, Gerufene zuerst: Modi,
  # Typen, Fluss, Ausschließlichkeit. Was nicht passt, fällt heraus, und
  # mit ihm, wer es ruft.

  defp settle(preds, ext0, dynamic) do
    Process.put(@why_key, %{})

    try do
      settle_(preds, ext0, dynamic)
    after
      Process.delete(@why_key)
    end
  end

  defp settle_(preds, ext0, dynamic) do
    batch = MapSet.new(for {k, _} <- preds, do: k)
    ext = fn k -> if MapSet.member?(batch, k), do: nil, else: ext0.(k) end

    callable = fn k ->
      cond do
        MapSet.member?(dynamic, k) -> :dynamic
        MapSet.member?(batch, k) or ext.(k) != nil -> true
        true -> false
      end
    end

    parsed = for {k, src} <- preds, p = parse(k, src, callable), p != nil, into: %{}, do: {k, p}
    {parsed, num} = kinds(drop_orphans(parsed, ext), ext)

    solved =
      parsed
      |> sccs()
      |> Enum.reduce(%{}, fn scc, solved ->
        ready =
          Enum.all?(scc, fn k ->
            Enum.all?(parsed[k].deps, &(&1 in scc or Map.has_key?(solved, &1) or ext.(&1) != nil))
          end)

        if not ready do
          for k <- scc,
              d <- parsed[k].deps,
              not (d in scc or Map.has_key?(solved, d) or ext.(d) != nil),
              do: why(k, "ruft #{pi(d)}, das nicht übersetzt wird")
        end

        case ready && solve(scc, parsed, solved, ext, num) do
          {:ok, res} -> Map.merge(solved, res)
          _ -> solved
        end
      end)

    %{parsed: parsed, solved: solved, ext: ext, why: Process.get(@why_key)}
  end

  # Grund, warum key nicht übersetzt wird (der erste zählt)
  defp why(key, reason),
    do: Process.put(@why_key, Map.put_new(Process.get(@why_key), key, reason))

  defp no!(reason), do: throw({:no, reason})

  defp pi({n, a}), do: "#{n}/#{a}"

  defp vname({:var, {n, _}}) when is_binary(n), do: n
  defp vname({:var, n}) when is_binary(n), do: n
  defp vname(_), do: "_"

  # ein Term oder Ziel, kurz
  defp desc({:atom, a}), do: a
  defp desc({:struct, f, a}), do: "#{f}/#{length(a)}"
  defp desc({:var, _} = v), do: "Variable #{vname(v)}"
  defp desc(t) when is_binary(t), do: "Zeichenkette"
  defp desc(t) when is_list(t), do: "Liste"
  defp desc(t), do: inspect(t)

  defp tname(:num), do: "Zahl"
  defp tname(:list), do: "Liste"
  defp tname(:nlist), do: "Liste von Zahlen"
  defp tname(:any), do: "beliebiger Term"
  defp tname(:bot), do: "?"

  # wer etwas ruft, das weder übersetzt wird noch schon übersetzt ist
  defp drop_orphans(parsed, ext) do
    bad =
      for {k, p} <- parsed,
          Enum.any?(p.deps, &(not Map.has_key?(parsed, &1) and ext.(&1) == nil)),
          do: k

    for k <- bad,
        d <- parsed[k].deps,
        not Map.has_key?(parsed, d) and ext.(d) == nil,
        do: why(k, "ruft #{pi(d)}, das nicht übersetzt wird")

    if bad == [], do: parsed, else: drop_orphans(Map.drop(parsed, bad), ext)
  end

  # Ganzzahlig oder nicht: über Aufrufe hinweg einheitlich (ein Ergebnis
  # kann ein Float sein, ein Argument auch) – je zusammenhängendem Teil
  # des Aufrufgraphen; ein ganzzahliges schon übersetztes Prädikat darf
  # von einem nicht ganzzahligen nicht gerufen werden
  defp kinds(parsed, ext) do
    ext_num = fn d ->
      case ext.(d) do
        nil -> nil
        e -> e.sig.num
      end
    end

    seed =
      for {k, p} <- parsed,
          not int_only?(p.clauses) or Enum.any?(p.deps, &(ext_num.(&1) == true)),
          into: MapSet.new(),
          do: k

    edges = for {k, p} <- parsed, d <- p.deps, Map.has_key?(parsed, d), do: {k, d}
    num = spread(seed, edges)

    case for k <- num, d <- parsed[k].deps, ext_num.(d) == false, do: {k, d} do
      [] ->
        {parsed, num}

      bad ->
        for {k, d} <- bad,
            do: why(k, "ruft #{pi(d)}: übersetzt nur für Ganzzahlen, hier auch Floats")

        bad = Enum.map(bad, &elem(&1, 0))
        kinds(drop_orphans(Map.drop(parsed, bad), ext), ext)
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

  # Gerufene zuerst
  defp sccs(parsed) do
    g = :digraph.new()

    try do
      for k <- Map.keys(parsed), do: :digraph.add_vertex(g, k)

      for {k, p} <- parsed, d <- p.deps, Map.has_key?(parsed, d), do: :digraph.add_edge(g, k, d)

      c = :digraph_utils.condensation(g)

      try do
        c |> :digraph_utils.topsort() |> Enum.reverse() |> Enum.map(&Enum.sort/1)
      after
        :digraph.delete(c)
      end
    after
      :digraph.delete(g)
    end
  end

  # --- Zerlegen -----------------------------------------------------------

  defp parse({_, arity} = key, source, callable) when arity > 0 do
    source = Enum.map(source, fn {h, b} -> {plain(h), plain(b)} end)
    ctx = %{self: key, callable: callable}

    clauses =
      for {{h, b}, i} <- Enum.with_index(source, 1) do
        try do
          # Variablen einer Klausel liegen in BEAM-Registern (höchstens 1024)
          if {h, b} |> raw_vars([]) |> Enum.uniq() |> length() > @max_vars,
            do: no!("mehr als #{@max_vars} Variablen")

          {Enum.map(args(h), &pat!/1), index_guard(args(h), Enum.map(conj(b), &goal(&1, ctx)))}
        catch
          {:no, r} -> no!("Klausel #{i}: #{r}")
        end
      end

    calls = clauses |> collect_calls() |> Enum.uniq()
    deps = List.delete(calls, key)
    size = clauses |> Enum.map(fn {_, gs} -> goal_count(gs) end) |> Enum.sum()

    %{
      key: key,
      arity: arity,
      clauses: clauses,
      source: source,
      deps: deps,
      rec: key in calls,
      size: size
    }
  catch
    {:no, r} ->
      why(key, r)
      nil
  end

  defp parse(key, _, _) do
    why(key, "ohne Argumente")
    nil
  end

  # Variablen eines Terms (Listen auch mit Variablen als Rest)
  defp raw_vars({:var, _} = v, acc), do: [v | acc]
  defp raw_vars([h | t], acc), do: raw_vars(t, raw_vars(h, acc))
  defp raw_vars(t, acc) when is_tuple(t), do: Enum.reduce(Tuple.to_list(t), acc, &raw_vars/2)
  defp raw_vars(_, acc), do: acc

  defp goal_count(gs) when is_list(gs), do: Enum.reduce(gs, 0, &(goal_count(&1) + &2))
  defp goal_count({:ite, c, t, e}), do: goal_count(c) + goal_count(t) + goal_count(e)
  defp goal_count({:not, g}), do: 1 + goal_count(g)
  defp goal_count(_), do: 1

  # Wie PrologEx.Compiler: ein Typtest als erstes Ziel auf der Variablen des
  # ersten Kopfarguments ist Wächter des Index – der Interpreter lässt die
  # Klausel bei gebundenem Argument weg oder den Test aus, zählt ihn also
  # nicht
  @guards ~w(integer float number atom atomic compound callable var)
  defp index_guard([{:var, v} = x | _], [{:tt, t, x} = g | gs]) when t in @guards and v != "_",
    do: [{:idx, g} | gs]

  defp index_guard(_, gs), do: gs

  defp collect_calls({:call, k, _}), do: [k]
  defp collect_calls(t) when is_tuple(t), do: collect_calls(Tuple.to_list(t))
  defp collect_calls(l) when is_list(l), do: Enum.flat_map(l, &collect_calls/1)
  defp collect_calls(_), do: []

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
  defp goal({:struct, "is", [l, r]}, _), do: {:is, num_term!(l), expr!(r)}
  defp goal({:struct, op, [a, b]}, _) when op in @cmps, do: {:cmp, op, expr!(a), expr!(b)}
  defp goal({:struct, "=", [a, b]}, _), do: {:unify, pat!(a), pat!(b)}
  defp goal({:struct, t, [x]}, _) when t in @type_tests, do: {:tt, t, num_term!(x)}
  defp goal({:struct, "==", [a, b]}, _), do: {:teq, true, pat!(a), pat!(b)}
  defp goal({:struct, "\\==", [a, b]}, _), do: {:teq, false, pat!(a), pat!(b)}

  defp goal({:struct, ";", [{:struct, "->", [c, t]}, e]}, ctx),
    do: {:ite, seq(c, ctx), seq(t, ctx), seq(e, ctx)}

  # ( C -> T ) ohne Else: der Interpreter nimmt `fail` als Else (zählt eins)
  defp goal({:struct, "->", [c, t]}, ctx), do: {:ite, seq(c, ctx), seq(t, ctx), [:fail]}
  defp goal({:struct, "\\+", [g]}, ctx), do: {:not, seq(g, ctx)}
  defp goal({:struct, ";", _}, _), do: no!("Disjunktion (; ohne ->): nicht deterministisch")
  defp goal({:struct, "->", _}, _), do: no!("->")

  # Aufruf: das Prädikat selbst oder ein anderes, das übersetzt wird oder
  # schon übersetzt ist
  defp goal({:struct, name, a}, ctx) do
    key = {name, length(a)}

    case key == ctx.self or ctx.callable.(key) do
      true -> {:call, key, Enum.map(a, &pat!/1)}
      :dynamic -> no!("ruft das dynamische #{pi(key)}")
      false -> no!("Ziel #{pi(key)}")
    end
  end

  defp goal(g, _), do: no!("Ziel #{desc(g)}")

  # Term: Zahl, Variable, :nl ([]) oder {:cons, Element, Rest}; Elemente
  # Zahlen oder Variablen
  defp pat!(n) when is_integer(n) or is_float(n), do: n
  defp pat!({:var, _} = v), do: v
  defp pat!([]), do: :nl
  defp pat!([h | t]), do: {:cons, num_term!(h), pat!(t)}
  defp pat!(t), do: no!("Term #{desc(t)} (nur Zahlen, Variablen, Listen)")

  defp num_term!(n) when is_integer(n) or is_float(n), do: n
  defp num_term!({:var, _} = v), do: v
  defp num_term!(t), do: no!("Term #{desc(t)} (nur Zahl oder Variable)")

  defp expr!(n) when is_integer(n) or is_float(n), do: n
  defp expr!({:var, _} = v), do: v
  defp expr!({:atom, c}) when is_map_key(@consts, c), do: @consts[c]
  defp expr!({:struct, op, [a, b]}) when op in @ops2, do: {:op2, op, expr!(a), expr!(b)}
  defp expr!({:struct, op, [a]}) when op in @ops1, do: {:op1, op, expr!(a)}
  defp expr!(t), do: no!("Ausdruck mit #{desc(t)}")

  defp vars({:var, _} = v), do: [v]
  defp vars({:op2, _, a, b}), do: vars(a) ++ vars(b)
  defp vars({:op1, _, a}), do: vars(a)
  defp vars({:cons, a, b}), do: vars(a) ++ vars(b)
  defp vars(_), do: []

  defp anon?({:var, {"_", _}}), do: true
  defp anon?({:var, "_"}), do: true
  defp anon?(_), do: false

  # nur Ganzzahlen und ganzzahlig abgeschlossene Operationen?
  defp int_only?(f) when is_float(f), do: false
  defp int_only?({:var, _}), do: true
  defp int_only?({:tt, t, _}) when t in ["float", "number"], do: false
  defp int_only?({:op2, op, a, b}), do: op in @iops2 and int_only?(a) and int_only?(b)
  defp int_only?({:op1, op, a}), do: op in @iops1 and int_only?(a)
  defp int_only?(t) when is_tuple(t), do: int_only?(Tuple.to_list(t))
  defp int_only?(l) when is_list(l), do: Enum.all?(l, &int_only?/1)
  defp int_only?(_), do: true

  # --- Eine Komponente lösen ----------------------------------------------
  #
  # Modi aus Hinweisen im Rumpf (erster Gebrauch einer Kopfvariablen); die
  # übrigen Positionen durchprobieren. Je Versuch Typen bis zum Fixpunkt,
  # dann die Ausschließlichkeit.

  defp solve(scc, parsed, solved, ext, num) do
    other = fn ck ->
      case solved do
        %{^ck => r} -> r.sig
        _ -> ext.(ck).sig
      end
    end

    case evidence(scc, parsed, other) do
      :no ->
        for k <- scc, do: why(k, "Modi widersprechen sich")
        nil

      {:ok, fixed} ->
        solve_modes(scc, parsed, other, num, fixed)
    end
  end

  defp solve_modes(scc, parsed, other, num, fixed) do
    open =
      for key <- scc,
          k <- 0..(parsed[key].arity - 1),
          not Map.has_key?(fixed, {key, k}),
          do: {key, k}

    open
    |> candidates()
    |> Enum.find_value(fn assign ->
      modes = Map.merge(fixed, assign)

      try do
        {reqs, outs, irs} = types(scc, parsed, modes, other, num)

        for key <- scc,
            do: exclusive!(Enum.map(irs[key], & &1.ir), MapSet.member?(num, key))

        {:ok,
         Map.new(scc, fn key ->
           p = parsed[key]

           sig = %{
             modes: Map.new(0..(p.arity - 1), &{&1, modes[{key, &1}]}),
             req:
               for(
                 k <- 0..(p.arity - 1),
                 modes[{key, k}] == :in,
                 into: %{},
                 do: {k, reqs[{key, k}]}
               ),
             out:
               for(
                 k <- 0..(p.arity - 1),
                 modes[{key, k}] == :out,
                 into: %{},
                 do: {k, outs[{key, k}]}
               ),
             num: MapSet.member?(num, key)
           }

           {key, %{sig: sig, irs: Enum.map(irs[key], & &1.ir), p: p}}
         end)}
      catch
        # der Grund aus dem letzten Versuch (die meisten Eingaben: meist
        # der gemeinte Modus)
        {:no, r} ->
          for k <- scc, do: Process.put(@why_key, Map.put(Process.get(@why_key), k, r))
          nil
      end
    end)
  end

  # alle Belegungen der offenen Positionen: mehr Ausgaben zuerst, dann
  # Ausgaben eher rechts
  defp candidates(open) when length(open) > @max_enum, do: [Map.new(open, &{&1, :out})]

  defp candidates(open) do
    n = length(open)

    for mask <- 0..(Bitwise.bsl(1, n) - 1) do
      outs =
        for {pos, i} <- Enum.with_index(open), Bitwise.band(mask, Bitwise.bsl(1, i)) != 0, do: pos

      {mask, outs}
    end
    |> Enum.sort_by(fn {mask, outs} -> {-length(outs), -mask} end)
    |> Enum.map(fn {_, outs} ->
      Map.new(open, &{&1, if(&1 in outs, do: :out, else: :in)})
    end)
  end

  defp evidence(scc, parsed, other) do
    ev =
      for key <- scc,
          {head, goals} <- parsed[key].clauses,
          {a, k} <- Enum.with_index(head),
          match?({:var, _}, a),
          not anon?(a),
          e = first_use(a, goals),
          e not in [nil, :none] do
        case e do
          {:as, ck, j} -> if ck in scc, do: {{key, k}, e}, else: {{key, k}, other.(ck).modes[j]}
          _ -> {{key, k}, e}
        end
      end

    {m0, bad} =
      Enum.reduce(ev, {%{}, []}, fn
        {pos, e}, {m, bad} when e in [:in, :out] -> put_mode(m, pos, e, bad)
        _, acc -> acc
      end)

    case fix_modes(m0, ev, bad) do
      {m, []} -> {:ok, m}
      _ -> :no
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

  defp use_in(v, {:unify, a, b}), do: if(v in (vars(a) ++ vars(b)), do: :none)
  defp use_in(v, {:tt, _, x}), do: if(v == x, do: :in)
  defp use_in(v, {:idx, g}), do: use_in(v, g)
  defp use_in(v, {:teq, _, a, b}), do: if(v in (vars(a) ++ vars(b)), do: :in)

  defp use_in(v, {:call, ck, as}) do
    case Enum.find_index(as, &(&1 == v)) do
      nil -> if v in Enum.flat_map(as, &vars/1), do: :none
      j -> {:as, ck, j}
    end
  end

  defp use_in(v, {:ite, c, t, e}), do: first_use(v, c) || first_use(v, t) || first_use(v, e)
  defp use_in(v, {:not, g}), do: first_use(v, g)
  defp use_in(_, _), do: nil

  # --- Typen --------------------------------------------------------------
  #
  # Ein Wert: {t, herkunft}. t: :bot (noch unbekannt), :num, :nlist (Liste
  # von Zahlen), :list, :any. herkunft: {:arg, key, k} (die Eingabe k oder
  # ein Rest davon), {:elem, key, k} (ein Element der Eingabe k). Der Typ
  # ist t vereinigt mit dem der Herkunft; braucht der Code mehr, steigt die
  # Anforderung an die Herkunft (an die Eingabe, beim Aufruf geprüft).
  # Anforderungen: :any < :num, :any < :list < :nlist.
  #
  # Ausgaben: {t, ps} – t vereinigt mit den Typen der Eingaben ps (deren
  # Anforderung :any ist: durchgereicht), am Aufrufort eingesetzt.

  defp types(scc, parsed, modes, other, num) do
    reqs0 =
      for key <- scc,
          k <- 0..(parsed[key].arity - 1),
          modes[{key, k}] == :in,
          into: %{},
          do: {{key, k}, :any}

    outs0 =
      for key <- scc,
          k <- 0..(parsed[key].arity - 1),
          modes[{key, k}] == :out,
          into: %{},
          do: {{key, k}, {:bot, []}}

    types_fix(scc, parsed, modes, {other, num}, reqs0, outs0, 12)
  end

  defp types_fix(_, _, _, _, _, _, 0), do: no!("Typen kommen zu keinem Fixpunkt")

  defp types_fix(scc, parsed, modes, {other, num} = on, reqs, outs, n) do
    sig = fn ck ->
      if ck in scc do
        ar = parsed[ck].arity

        %{
          modes: Map.new(0..(ar - 1), &{&1, modes[{ck, &1}]}),
          req: for(k <- 0..(ar - 1), modes[{ck, k}] == :in, into: %{}, do: {k, reqs[{ck, k}]}),
          out: for(k <- 0..(ar - 1), modes[{ck, k}] == :out, into: %{}, do: {k, outs[{ck, k}]})
        }
      else
        other.(ck)
      end
    end

    Process.put(@raise_key, reqs)
    Process.delete(@soft_key)

    irs =
      try do
        Map.new(scc, fn key ->
          ctx = %{key: key, sig: sig, reqs: reqs, num: MapSet.member?(num, key)}
          pre = if length(scc) > 1, do: "#{pi(key)}, ", else: ""

          {key,
           parsed[key].clauses
           |> Enum.with_index(1)
           |> Enum.map(fn {c, i} ->
             try do
               flow(c, ctx)
             catch
               {:no, r} -> no!("#{pre}Klausel #{i}: #{r}")
             end
           end)}
        end)
      catch
        {:no, _} = e ->
          Process.delete(@raise_key)
          Process.delete(@soft_key)
          throw(e)
      end

    reqs2 = Process.delete(@raise_key)
    soft = Process.delete(@soft_key)

    outs2 =
      for {{key, k}, _} <- outs, into: %{} do
        o =
          irs[key]
          |> Enum.flat_map(fn c -> Map.get(c.otypes, k, []) end)
          |> Enum.map(&out_sig(&1, key, reqs2))
          |> Enum.reduce({:bot, []}, &oj/2)

        {{key, k}, o}
      end

    cond do
      reqs2 != reqs or outs2 != outs -> types_fix(scc, parsed, modes, on, reqs2, outs2, n - 1)
      soft -> no!(soft)
      true -> {reqs, outs, irs}
    end
  end

  defp tj(:bot, x), do: x
  defp tj(x, :bot), do: x
  defp tj(x, x), do: x
  defp tj(a, b) when a in [:list, :nlist] and b in [:list, :nlist], do: :list
  defp tj(_, _), do: :any

  defp vj({t1, o1}, {t2, o2}), do: {tj(t1, t2), Enum.uniq(o1 ++ o2)}

  defp oj({t1, p1}, {t2, p2}), do: {tj(t1, t2), Enum.sort(Enum.uniq(p1 ++ p2))}

  # Anforderungen: Zahl gegen Liste unvereinbar
  defp rj(a, a), do: a
  defp rj(:any, b), do: b
  defp rj(a, :any), do: a
  defp rj(a, b) when a in [:list, :nlist] and b in [:list, :nlist], do: :nlist
  defp rj(a, b), do: no!("ein Argument müsste #{tname(a)} und #{tname(b)} sein")

  # was der Typ t schon garantiert
  defp sat?(:bot, _), do: true
  defp sat?(t, t), do: true
  defp sat?(:nlist, :list), do: true
  defp sat?(_, _), do: false

  # der Wert muss r sein. Passt t nicht, zählt das erst, wenn sich die
  # Typen nicht mehr ändern (vorher kann t aus einer älteren Runde sein)
  defp need(:any, _), do: :ok

  defp need(r, {t, os}) do
    unless sat?(t, r) or Process.get(@soft_key),
      do: Process.put(@soft_key, "#{tname(t)}, wo #{tname(r)} gebraucht wird")

    Enum.each(os, &raise_req(&1, r))
  end

  defp raise_req({:arg, key, k}, r) do
    reqs = Process.get(@raise_key)
    Process.put(@raise_key, Map.put(reqs, {key, k}, rj(Map.fetch!(reqs, {key, k}), r)))
  end

  defp raise_req({:elem, key, k}, :num), do: raise_req({:arg, key, k}, :nlist)
  defp raise_req({:elem, _, _}, r), do: no!("ein Listenelement müsste #{tname(r)} sein")

  # Typ, den der Wert jetzt hat (nach den Anforderungen dieser Runde)
  defp eff({t, os}, reqs), do: Enum.reduce(os, t, &tj(origin_t(&1, reqs), &2))

  defp origin_t({:arg, key, k}, reqs), do: Map.fetch!(reqs, {key, k})

  defp origin_t({:elem, key, k}, reqs),
    do: if(Map.fetch!(reqs, {key, k}) == :nlist, do: :num, else: :any)

  # Ausgabe als Signatur: Eingaben mit Anforderung :any bleiben Parameter
  defp out_sig({t, os}, key, reqs) do
    Enum.reduce(os, {t, []}, fn
      {:arg, ^key, k} = o, {t, ps} ->
        case reqs[{key, k}] do
          :any -> {t, [k | ps]}
          _ -> {tj(t, origin_t(o, reqs)), ps}
        end

      o, {t, ps} ->
        {tj(t, origin_t(o, reqs)), ps}
    end)
    |> then(fn {t, ps} -> {t, Enum.sort(Enum.uniq(ps))} end)
  end

  # Elemente und Rest eines Listenwerts
  defp elem_of({t, os}) do
    et =
      case t do
        :nlist -> :num
        :bot -> :bot
        _ -> :any
      end

    {et, for({:arg, key, k} <- os, do: {:elem, key, k})}
  end

  # --- Datenfluss je Klausel: Zwischenform für die Codeerzeugung ----------
  #
  # d: Variable => Wert (Typ) oder :all hinter einem sicheren Scheitern
  # (alles Weitere ist toter Code). {:poison, V}: V ist nur in einem Zweig
  # eines If-then-else bestimmt – jeder spätere Gebrauch macht die Klausel
  # unübersetzbar.
  #
  # Muster (gegen einen bekannten Wert): {:const, c}, {:bind, V}, {:eq, V},
  # :ignore, :nl, {:cons, Muster, Muster}. Bau (aus bekannten Werten):
  # Zahl, {:var, V}, :nl, {:cons, Bau, Bau}.

  defp flow({head, goals}, ctx) do
    modes = ctx.sig.(ctx.key).modes

    {hin, d} =
      head
      |> Enum.with_index()
      |> Enum.filter(fn {_, k} -> modes[k] == :in end)
      |> Enum.map_reduce(%{}, fn {a, k}, d ->
        {mp, d} = match_pat(a, {:bot, [{:arg, ctx.key, k}]}, d, ctx)
        {{k, mp}, d}
      end)

    {irs, d} = flow_seq(goals, d, ctx)

    {hout, otypes} =
      for {a, k} <- Enum.with_index(head), modes[k] == :out, reduce: {[], %{}} do
        {hout, ot} ->
          if anon?(a), do: no!("Ausgabe _")
          {bt, vt} = build!(a, d, ctx)
          {[{k, bt} | hout], if(d == :all, do: ot, else: Map.put(ot, k, [vt]))}
      end

    %{ir: %{hin: hin, hout: Enum.reverse(hout), goals: irs}, otypes: otypes}
  end

  defp flow_seq(_, :all, _), do: {[], :all}
  defp flow_seq([], d, _), do: {[], d}

  defp flow_seq([g | gs], d, ctx) do
    {ir, d1} = goal_flow(g, d, ctx)
    {irs, d2} = flow_seq(gs, d1, ctx)
    {[ir | irs], d2}
  end

  defp defd?(:all, _), do: true
  defp defd?(d, v), do: Map.has_key?(d, v)

  defp add(d, v, t) do
    if Map.has_key?(d, {:poison, v}),
      do: no!("#{vname(v)} ist nur in einem Zweig eines If-then-else bestimmt")

    Map.put(d, v, t)
  end

  defp meet(:all, d), do: d
  defp meet(d, :all), do: d

  defp meet(a, b) do
    keys = MapSet.new(Map.keys(a) ++ Map.keys(b))

    Map.new(keys, fn
      {:poison, _} = p ->
        {p, true}

      v ->
        case {a, b} do
          {%{^v => x}, %{^v => y}} -> {v, vj(x, y)}
          _ -> {{:poison, v}, true}
        end
    end)
  end

  defp new_vars(d1, d0),
    do: for({:var, _} = v <- Map.keys(d1), not Map.has_key?(d0, v), do: v) |> Enum.sort()

  # Muster gegen einen bekannten Wert vom Typ vt
  defp match_pat(n, vt, d, _ctx) when is_number(n) do
    need(:num, vt)
    {{:const, n}, d}
  end

  defp match_pat({:var, _} = v, vt, d, ctx) do
    cond do
      anon?(v) ->
        {:ignore, d}

      defd?(d, v) ->
        eq_types!(vt, d[v], ctx)
        {{:eq, v}, d}

      true ->
        {{:bind, v}, add(d, v, vt)}
    end
  end

  defp match_pat(:nl, vt, d, _ctx) do
    need(:list, vt)
    {:nl, d}
  end

  # Elemente einer Liste von Zahlen: erst zur Zahl machen (aus der Eingabe
  # kommen sie ungelesen, PrologEx.Jit.num/1)
  defp match_pat({:cons, h, t}, vt, d, ctx) do
    need(:list, vt)
    et = elem_of(vt)
    {hm, d} = match_pat(h, et, d, ctx)
    hm = if eff(et, ctx.reqs) == :num and hm != :ignore, do: {:num, hm}, else: hm
    {tm, d} = match_pat(t, vt, d, ctx)
    {{:cons, hm, tm}, d}
  end

  # Gleichheit zweier Werte mit ===: nur Zahlen (beliebige Terme könnten
  # ungebundene Variablen sein, Listen aus der Eingabe sind ungelesen)
  defp eq_types!(a, b, ctx) do
    if eff(a, ctx.reqs) in [:list, :nlist] or eff(b, ctx.reqs) in [:list, :nlist],
      do: no!("Gleichheit von Listen")

    need(:num, a)
    need(:num, b)
  end

  # Bau aus bekannten Werten: {bau, typ}. Eine Liste aus Zahlen ist
  # :nlist, sonst :list; ein Rest, der keine Liste ist, macht sie beliebig;
  # ein Rest unbekannten Typs gibt seine Herkunft weiter
  defp build!(n, _d, _ctx) when is_number(n), do: {n, {:num, []}}

  defp build!({:var, _} = v, d, _ctx) do
    if anon?(v) or not defd?(d, v), do: no!("#{vname(v)} ist hier nicht bestimmt")
    {v, if(d == :all, do: {:bot, []}, else: Map.fetch!(d, v))}
  end

  defp build!(:nl, _d, _ctx), do: {:nl, {:nlist, []}}

  defp build!({:cons, h, t}, d, ctx) do
    {hb, ht} = build!(h, d, ctx)
    {tb, {tt, tos}} = build!(t, d, ctx)
    base = if eff(ht, ctx.reqs) in [:num, :bot], do: :nlist, else: :list

    t2 =
      case tt do
        x when x in [:num, :any] -> :any
        :bot -> base
        x -> tj(base, x)
      end

    {{:cons, hb, tb}, {t2, tos}}
  end

  defp build_ok?(t, d, ctx) do
    build!(t, d, ctx)
    true
  catch
    {:no, _} -> false
  end

  defp desc_p({:var, _} = v), do: vname(v)
  defp desc_p(:nl), do: "[]"
  defp desc_p({:cons, _, _}), do: "[...]"
  defp desc_p(n), do: inspect(n)

  defp goal_flow(:cut, d, _), do: {:cut, d}
  defp goal_flow(true, d, _), do: {true, d}
  defp goal_flow(:fail, _d, _), do: {:fail, :all}

  defp goal_flow({:cmp, op, a, b}, d, _) do
    nums!(vars(a) ++ vars(b), d)
    {{:cmp, op, a, b}, d}
  end

  defp goal_flow({:is, l, r}, d, ctx) do
    nums!(vars(r), d)

    cond do
      is_number(l) ->
        {{:is_eq, l, r}, d}

      anon?(l) ->
        {{:is_eq, :ignore, r}, d}

      defd?(d, l) ->
        eq_types!({:num, []}, d[l], ctx)
        {{:is_eq, l, r}, d}

      true ->
        {{:is_def, l, r}, add(d, l, {:num, []})}
    end
  end

  # X = Y: eine Seite ganz bekannt (Bau), die andere Muster dagegen
  defp goal_flow({:unify, a, b}, d, ctx) do
    {bt, mp, d} =
      cond do
        build_ok?(a, d, ctx) ->
          {bt, vt} = build!(a, d, ctx)
          {mp, d} = match_pat(b, vt, d, ctx)
          {bt, mp, d}

        build_ok?(b, d, ctx) ->
          {bt, vt} = build!(b, d, ctx)
          {mp, d} = match_pat(a, vt, d, ctx)
          {bt, mp, d}

        true ->
          no!("#{desc_p(a)} = #{desc_p(b)}: beide Seiten nicht bestimmt")
      end

    {{:u, bt, mp}, d}
  end

  # Aufruf: Eingaben bauen (Anforderungen des Gerufenen), Ausgaben als
  # Muster gegen die Ergebnisse (Typ am Aufrufort eingesetzt)
  defp goal_flow({:call, ck, as}, d, ctx) do
    sig = ctx.sig.(ck)
    indexed = Enum.with_index(as)

    ins =
      for {a, k} <- indexed, sig.modes[k] == :in do
        {bt, vt} = build!(a, d, ctx)
        need(sig.req[k], vt)
        {k, bt, vt}
      end

    actual = Map.new(ins, fn {k, _, vt} -> {k, vt} end)

    {outs, d2} =
      indexed
      |> Enum.filter(fn {_, k} -> sig.modes[k] == :out end)
      |> Enum.map_reduce(d, fn {a, k}, acc ->
        {t, ps} = sig.out[k]
        vt = Enum.reduce(ps, {t, []}, &vj(Map.fetch!(actual, &1), &2))
        match_pat(a, vt, acc, ctx)
      end)

    {{:call, ck, Enum.map(ins, &elem(&1, 1)), outs}, d2}
  end

  # die Bedingung sieht d, Then sieht zusätzlich, was die Bedingung bestimmt,
  # Else nur d; danach gilt, was beide Zweige bestimmen
  #
  # Ein Typtest kann einen schon bestimmten Wert verfeinern (integer(X): X
  # ist danach eine gelesene Zahl) – im Code eine neue Bindung, sichtbar nur
  # im Rest derselben Folge. Was eine Bedingung oder ein Zweig verfeinert,
  # gilt danach also wieder mit dem Typ von vorher (restore/2)
  defp goal_flow({:ite, c, t, e}, d, ctx) do
    {ci, dc} = flow_seq(c, d, ctx)
    if dc == :all, do: no!("Bedingung scheitert immer")
    {ti, dt} = flow_seq(t, restore(dc, d), ctx)
    {ei, de} = flow_seq(e, d, ctx)
    dn = restore(meet(dt, de), d)
    nvars = if dn == :all, do: :dead, else: new_vars(dn, d)
    {{:ite, ci, new_vars(dc, d), ti, ei, nvars}, dn}
  end

  # was G bestimmt, gilt danach nicht
  defp goal_flow({:not, g}, d, ctx) do
    {gi, _} = flow_seq(g, d, ctx)
    {{:not, gi}, d}
  end

  # Typtest. Unbestimmt: eine frische Variable (der übersetzte Code bindet
  # Eingaben nie, und Ausgaben erst am Ende). Eine Zahl: meist fest. Sonst
  # zur Laufzeit (PrologEx.Jit.tt/2); integer/1 (float/1, number/1 im Code
  # mit Floats) macht den Wert danach zur Zahl
  defp goal_flow({:tt, t, x}, d, ctx) do
    how =
      cond do
        is_number(x) -> PrologEx.type_test(t, x)
        anon?(x) or not defd?(d, x) -> t == "var"
        eff(d[x], ctx.reqs) == :num -> num_test(t, ctx.num)
        refines?(t, ctx.num) -> :refine
        true -> :rt
      end

    d = if how == :refine, do: Map.put(d, x, {:num, []}), else: d
    {{:tt, t, x, how}, d}
  end

  # Wächter des Index: gebunden (eine Zahl), frisch, oder erst zur Laufzeit
  defp goal_flow({:idx, {:tt, _, x} = g}, d, ctx) do
    {{:tt, _, _, how} = ir, d2} = goal_flow(g, d, ctx)

    bound =
      cond do
        is_number(x) -> true
        anon?(x) or not defd?(d, x) -> false
        how in [:rt, :refine] -> :rt
        true -> true
      end

    {{:idx, ir, bound}, d2}
  end

  # ==, \==: beide Seiten bestimmt; Zahlen mit ===, sonst zur Laufzeit
  # (PrologEx.Jit.teq/2, wie der Interpreter)
  defp goal_flow({:teq, pos, a, b}, d, ctx) do
    {ba, ta} = build!(a, d, ctx)
    {bb, tb} = build!(b, d, ctx)
    how = if eff(ta, ctx.reqs) == :num and eff(tb, ctx.reqs) == :num, do: :num, else: :rt
    {{:teq, pos, ba, bb, how}, d}
  end

  # Typtest auf einer Zahl: true/false, oder (Code mit Floats) :num
  defp num_test(t, _) when t in ["number", "atomic", "nonvar"], do: true
  defp num_test(t, false) when t in ["integer"], do: true
  defp num_test(t, false) when t in ["float"], do: false
  defp num_test(t, true) when t in ["integer", "float"], do: :num
  defp num_test(_, _), do: false

  defp refines?("integer", _), do: true
  defp refines?(t, true) when t in ["float", "number"], do: true
  defp refines?(_, _), do: false

  # Typen bestimmter Variablen wie in d0 (neue bleiben)
  defp restore(:all, _), do: :all

  defp restore(d, d0) do
    Enum.reduce(d0, d, fn
      {{:var, _} = v, t}, acc -> if Map.has_key?(acc, v), do: Map.put(acc, v, t), else: acc
      _, acc -> acc
    end)
  end

  # bestimmt und Zahlen
  defp nums!(vs, d) do
    for v <- vs do
      if not defd?(d, v), do: no!("#{vname(v)} ist hier nicht bestimmt")
      need(:num, Map.get(d, v, {:bot, []}))
    end
  end

  # --- Ausschließlichkeit -------------------------------------------------

  defp exclusive!(irs, num) do
    pairs =
      for {a, i} <- Enum.with_index(irs, 1),
          {b, j} <- Enum.with_index(irs, 1),
          i < j,
          do: {a, b, i, j}

    for {a, b, i, j} <- pairs,
        not exclusive?(a, b, num),
        do: no!("Klauseln #{i} und #{j} schließen sich nicht nachweislich aus")

    :ok
  end

  # a vor b: hat a eine Lösung, scheitert b sicher (ohne Fehler davor)
  defp exclusive?(a, b, num) do
    :cut in a.goals or pats_differ?(a, b) or const_vs_guard?(a, b, num) or
      complementary?(a, b, num) or classes_differ?(a, b, num)
  end

  # Vergleiche, `=` und Typtests am Anfang des Rumpfs
  defp guards(c) do
    c.goals
    |> Enum.map(fn
      {:idx, g, _} -> g
      g -> g
    end)
    |> Enum.take_while(fn
      {:cmp, _, _, _} -> true
      {:u, _, _} -> true
      {:tt, _, _, _} -> true
      _ -> false
    end)
  end

  # Typklassen: was ein Argument nach Muster und Typtests am Anfang noch
  # sein kann; haben a und b an einer Stelle nichts gemeinsam, schließen
  # sie sich aus
  @all ~w(var int float rat nil atom cons struct bytes other)a
  defp classes_differ?(a, b, num) do
    ca = classes(a, guards(a))
    cb = classes(b, reachable(b, num))
    Enum.any?(Enum.zip(ca, cb), fn {x, y} -> MapSet.disjoint?(x, y) end)
  end

  defp classes(c, gs) do
    falsum = Enum.any?(gs, &match?({:tt, _, _, false}, &1))

    for {{_, mp0}, {_, mp}} <- Enum.zip(c.hin, eff_hin(c)) do
      base =
        case mp do
          {:const, n} when is_integer(n) -> [:int]
          {:const, n} when is_float(n) -> [:float]
          :nl -> [nil]
          {:cons, _, _} -> [:cons]
          _ -> @all
        end

      v = with {:bind, v} <- mp0, do: v

      gs
      |> Enum.reduce(MapSet.new(base), fn
        {:tt, t, ^v, how}, acc when how != true -> MapSet.intersection(acc, MapSet.new(tclass(t)))
        _, acc -> acc
      end)
      |> then(&if(falsum, do: MapSet.new(), else: &1))
    end
  end

  defp tclass("var"), do: [:var]
  defp tclass("nonvar"), do: @all -- [:var]
  defp tclass("integer"), do: [:int]
  defp tclass("float"), do: [:float]
  defp tclass("number"), do: [:int, :float, :rat]
  defp tclass("atom"), do: [nil, :atom]
  defp tclass("atomic"), do: [:int, :float, :rat, nil, :atom, :bytes]
  defp tclass("compound"), do: [:cons, :struct]
  defp tclass("callable"), do: [nil, :atom, :cons, :struct]
  defp tclass("is_list"), do: [nil, :cons]

  # die Wächter von b, die b erreicht, ohne dass einer davor werfen kann
  defp reachable(c, num) do
    Enum.reduce_while(guards(c), [], fn g, acc ->
      if safe?(g, num), do: {:cont, [g | acc]}, else: {:halt, [g | acc]}
    end)
    |> Enum.reverse()
  end

  defp safe?({:u, _, _}, _), do: true
  defp safe?({:tt, _, _, _}, _), do: true
  defp safe?({:cmp, _, x, y}, num), do: safe_ex?(x, num) and safe_ex?(y, num)

  defp safe_ex?(n, _) when is_number(n), do: true
  defp safe_ex?({:var, _}, _), do: true

  defp safe_ex?({:op2, op, a, b}, false) when op in @total2,
    do: safe_ex?(a, false) and safe_ex?(b, false)

  defp safe_ex?({:op1, op, a}, false) when op in @total1, do: safe_ex?(a, false)
  defp safe_ex?(_, _), do: false

  # Kopfeingaben, mit `V = Muster` am Anfang als Muster an V's Stelle
  defp eff_hin(c) do
    eqs = for {:u, {:var, _} = v, mp} <- guards(c), into: %{}, do: {v, mp}

    Enum.map(c.hin, fn
      {k, {:bind, v}} = e -> if Map.has_key?(eqs, v), do: {k, eqs[v]}, else: e
      e -> e
    end)
  end

  defp pats_differ?(a, b) do
    Enum.any?(Enum.zip(eff_hin(a), eff_hin(b)), fn {{k, x}, {k, y}} -> pat_differ?(x, y) end)
  end

  defp pat_differ?({:const, x}, {:const, y}), do: x !== y
  defp pat_differ?(:nl, {:cons, _, _}), do: true
  defp pat_differ?({:cons, _, _}, :nl), do: true

  defp pat_differ?({:cons, h1, t1}, {:cons, h2, t2}),
    do: pat_differ?(h1, h2) or pat_differ?(t1, t2)

  defp pat_differ?({:const, _}, x) when x == :nl or elem(x, 0) == :cons, do: true
  defp pat_differ?(x, {:const, _}) when x == :nl or elem(x, 0) == :cons, do: true
  defp pat_differ?(_, _), do: false

  # a hat an k die Konstante c, b dort die Variable V und am Anfang einen
  # Wächter nur über V, der für V = c falsch ist
  defp const_vs_guard?(a, b, num) do
    Enum.any?(Enum.zip(eff_hin(a), b.hin), fn
      {{k, {:const, c}}, {k, {:bind, v}}} ->
        Enum.any?(reachable(b, num), fn g ->
          gv = guard_vars(g)
          gv != :unknown and Enum.all?(gv, &(&1 == v)) and guard_val(g, %{v => c}) == false
        end)

      _ ->
        false
    end)
  end

  defp guard_vars({:cmp, _, x, y}), do: vars(x) ++ vars(y)
  defp guard_vars({:u, {:var, _} = v, {:const, _}}), do: [v]
  defp guard_vars(_), do: :unknown

  defp guard_val({:cmp, op, x, y}, env) do
    PrologEx.compare(op, ceval(x, env), ceval(y, env))
  rescue
    _ -> :unknown
  catch
    _ -> :unknown
  end

  defp guard_val({:u, v, {:const, c}}, env), do: Map.fetch!(env, v) === c

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
  #
  # Module: je Komponente eines, Gerufene zuerst – so steht der Name (Hash
  # des Inhalts, samt der Namen gerufener Module) jedes Moduls fest, bevor
  # ein Rufer ihn braucht. Im Modul je Prädikat j: e<j> (Eintritt), p<j>
  # (Klauselwahl), c<j>_<i>.

  defp build(s, how) do
    s.parsed
    |> Map.take(Map.keys(s.solved))
    |> sccs()
    |> Enum.reduce({%{}, []}, fn scc, {done, shown} -> build_scc(scc, s, how, done, shown) end)
    |> case do
      {_, shown} when how == :show -> shown |> Enum.reverse() |> Enum.join("\n")
      {done, _} -> done
    end
  end

  defp build_scc(scc, s, how, done, shown) do
    infos =
      scc
      |> Enum.with_index()
      |> Enum.map(fn {key, j} ->
        r = s.solved[key]
        sig = r.sig

        ins =
          for {k, req} <- Enum.sort(sig.req),
              do: {k, check_code(req, sig.num)}

        outs = for {k, _} <- Enum.sort(sig.out), do: k

        %{
          key: key,
          j: j,
          ins: ins,
          outs: outs,
          clauses: r.irs,
          source: r.p.source,
          num: sig.num,
          deps: r.p.deps,
          sig: sig
        }
      end)

    local = Map.new(infos, &{&1.key, {:local, :"p#{&1.j}"}})

    # Aus dem Interpreter lohnt der Eintritt, wo der Code wenigstens ein
    # Ziel hat oder etwas wiederholt (rekursiv, oder ruft Rekursives) –
    # schon ein Vergleich spart mehr, als der Wechsel kostet; ein Fakt
    # nicht. Übersetzt wird trotzdem – für übersetzte Rufer
    entry =
      length(scc) > 1 or Enum.any?(scc, &s.parsed[&1].rec) or
        Enum.sum(Enum.map(scc, &s.parsed[&1].size)) >= @entry_size or
        Enum.any?(infos, fn i ->
          Enum.any?(i.deps, fn d ->
            case done do
              %{^d => {{_, _, _, _, sig}, _, _}} -> sig.entry
              _ -> (e = s.ext.(d)) != nil and e.sig.entry
            end
          end)
        end)

    infos = Enum.map(infos, &%{&1 | sig: Map.put(&1.sig, :entry, entry)})

    remote =
      for i <- infos, d <- i.deps, not Map.has_key?(local, d), into: %{} do
        case done do
          %{^d => {{mod, _, pf, _, _}, _, _}} -> {d, {:remote, mod, pf}}
          _ -> (e = s.ext.(d)) && {d, {:remote, e.mod, e.p}}
        end
      end

    targets = Map.merge(remote, local)

    # der Name: Hash der Zwischenform mit Variablen in kanonischer
    # Reihenfolge (dasselbe Programm neu gelesen: derselbe Name)
    hash =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary(
          {Enum.map(
             infos,
             &{Enum.map(&1.clauses, fn c -> canon(c) end), &1.ins, &1.outs, &1.num}
           ), Enum.sort(remote)}
        )
      )
      |> Base.encode16(case: :lower)
      |> binary_part(0, 20)

    mod = Module.concat(PrologEx.Jit.Code, "P" <> hash)

    case how do
      :show ->
        {done, [Macro.to_string(gen(mod, infos, targets)) | shown]}

      :load ->
        register(mod, infos, targets)

        done =
          for i <- infos,
              into: done,
              do: {i.key, {{mod, :"e#{i.j}", :"p#{i.j}", i.deps, i.sig}, i.ins, i.outs}}

        {done, shown}
    end
  end

  defp canon(%{hin: hin, hout: hout, goals: goals}) do
    {t, _} = canon_t({hin, hout, goals}, %{})
    t
  end

  defp canon_t({:var, _} = v, m) do
    case m do
      %{^v => n} -> {{:var, n}, m}
      _ -> {{:var, map_size(m)}, Map.put(m, v, map_size(m))}
    end
  end

  defp canon_t(t, m) when is_tuple(t) do
    {l, m} = canon_t(Tuple.to_list(t), m)
    {List.to_tuple(l), m}
  end

  defp canon_t(l, m) when is_list(l), do: Enum.map_reduce(l, m, &canon_t/2)
  defp canon_t(x, m), do: {x, m}

  # Übersetzt wird erst beim Aufruf (run/7, ensure/1): beim Laden nur die
  # Zwischenform ablegen (persistent_term, wie die Module selbst für alle
  # Prozesse); viele übersetzbare Prädikate einer Bibliothek werden nie
  # gerufen, und der BEAM-Compiler ist das Teure
  defp register(mod, infos, targets) do
    key = {__MODULE__, mod}

    unless :erlang.module_loaded(mod) or :persistent_term.get(key, nil) != nil do
      callees = for({_, {:remote, m, _}} <- targets, do: m) |> Enum.uniq()
      slim = Enum.map(infos, &Map.take(&1, [:j, :ins, :clauses, :num]))
      # Aufrufzähler bis zur Schwelle (Flag jit_threshold, siehe run/7)
      :persistent_term.put(key, {:ir, slim, targets, callees, :atomics.new(1, [])})
    end
  end

  @doc false
  # das Modul geladen? Sonst jetzt übersetzen (Gerufene zuerst); scheitert
  # der Compiler (etwa an einer Grenze der BEAM), bleibt es beim
  # Interpreter (false)
  def ensure(mod), do: :erlang.module_loaded(mod) or compile_now(mod)

  defp compile_now(mod) do
    case :persistent_term.get({__MODULE__, mod}, nil) do
      {:ir, infos, targets, callees, _} ->
        (Enum.all?(callees, &ensure/1) and compiled?(gen(mod, infos, targets))) or
          stub(mod, infos)

      _ ->
        false
    end
  end

  # Ließ sich ein Modul nicht übersetzen: ein Ersatz, dessen Funktionen
  # gleich aufgeben – jeder Aufruf nimmt dann ohne weiteren Versuch den
  # Interpreter (false: auch dieser)
  defp stub(mod, infos) do
    funs =
      for i <- infos, f <- [:"e#{i.j}", :"p#{i.j}"] do
        args = Enum.map(0..length(i.ins), &Macro.var(:"a#{&1}", __MODULE__))
        quote(do: def(unquote(f)(unquote_splicing(args)), do: throw(:jit_deopt)))
      end

    compiled?(quote(do: defmodule(unquote(mod), do: (unquote_splicing(funs)))))
    false
  end

  defp compiled?(ast) do
    {_, _} = Code.with_diagnostics([log: false], fn -> Code.compile_quoted(ast) end)
    true
  rescue
    _ -> false
  end

  # Prüfung einer Eingabe beim Aufruf (siehe PrologEx: jit_ins)
  defp check_code(:num, false), do: :int
  defp check_code(:num, true), do: :num
  defp check_code(:nlist, false), do: :ilist
  defp check_code(:nlist, true), do: :nlist
  defp check_code(r, _), do: r

  defp gen(mod, infos, targets) do
    funs =
      Enum.flat_map(infos, fn info ->
        ins = Enum.map(info.ins, fn {k, _} -> in_var(k) end)
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
    ins = Enum.map(info.ins, fn {k, _} -> in_var(k) end)
    vmap = var_map(c)
    st = %{vmap: vmap, cut: false, local: false, num: info.num, hout: c.hout, targets: targets}
    body = gen_goals(c.goals ++ [:end], st)

    head =
      Enum.reduce(Enum.reverse(c.hin), body, fn {k, mp}, acc ->
        match_ast(in_var(k), mp, acc, st)
      end)

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

  # Muster gegen einen Wert (AST): weiter mit then, sonst Scheitern
  defp match_ast(_v, :ignore, then, _st), do: then

  defp match_ast(v, {:bind, x}, then, st) do
    quote do
      unquote(st.vmap[x]) = unquote(v)
      unquote(then)
    end
  end

  defp match_ast(v, {:eq, x}, then, st),
    do: test_ast(quote(do: unquote(v) === unquote(st.vmap[x])), then, st)

  defp match_ast(v, {:const, c}, then, st),
    do: test_ast(quote(do: unquote(v) === unquote(c)), then, st)

  # Listen werden erst beim Zerlegen gelesen (PrologEx.Jit.list/1)
  defp match_ast(v, :nl, then, st),
    do: test_ast(quote(do: PrologEx.Jit.list(unquote(v)) === []), then, st)

  defp match_ast(v, {:cons, h, t}, then, st) do
    hv = Macro.unique_var(:h, __MODULE__)
    tv = Macro.unique_var(:t, __MODULE__)

    quote do
      case PrologEx.Jit.list(unquote(v)) do
        [unquote(hv) | unquote(tv)] -> unquote(match_ast(hv, h, match_ast(tv, t, then, st), st))
        _ -> unquote(failure(st))
      end
    end
  end

  defp match_ast(v, {:num, mp}, then, st) do
    n = Macro.unique_var(:n, __MODULE__)
    f = if st.num, do: :num, else: :int

    quote do
      unquote(n) = PrologEx.Jit.unquote(f)(unquote(v))
      unquote(match_ast(n, mp, then, st))
    end
  end

  defp test_ast(t, then, st),
    do: quote(do: if(unquote(t), do: unquote(then), else: unquote(failure(st))))

  # Bau (AST)
  defp build_ast(n, _st) when is_number(n), do: n
  defp build_ast({:var, _} = v, st), do: Map.fetch!(st.vmap, v)
  defp build_ast(:nl, _st), do: []
  defp build_ast({:cons, h, t}, st), do: [{:|, [], [build_ast(h, st), build_ast(t, st)]}]

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

  defp test(t, rest, st), do: counted(test_ast(t, rest, st))

  defp vs(vars, st), do: Enum.map(vars, &Map.fetch!(st.vmap, &1))

  defp gen_goals([:end], st) do
    outs = for {_, bt} <- st.hout, do: build_ast(bt, st)
    quote(do: {b, unquote_splicing(outs)})
  end

  defp gen_goals([{:yield, :cond, []}], _st), do: quote(do: -b - 1)
  defp gen_goals([{:yield, _, vars}], st), do: quote(do: {b, unquote_splicing(vs(vars, st))})

  # Schnitt in einer Bedingung oder unter \+: lokal, ohne Wirkung
  defp gen_goals([:cut | gs], %{local: false} = st), do: gen_goals(gs, %{st | cut: true})
  defp gen_goals([:cut | gs], st), do: gen_goals(gs, st)
  defp gen_goals([true | gs], st), do: counted(gen_goals(gs, st))
  defp gen_goals([:fail | _], st), do: counted(failure(st))

  defp gen_goals([{:tt, _, _, _} = g | gs], st), do: counted(tt_code(g, gs, st))

  # Wächter des Interpreter-Index (siehe parse/3): gezählt nur, wenn das
  # erste Argument ungebunden ist
  defp gen_goals([{:idx, g, true} | gs], st), do: tt_code(g, gs, st)
  defp gen_goals([{:idx, g, false} | gs], st), do: gen_goals([g | gs], st)

  defp gen_goals([{:idx, {:tt, _, x, _} = g, :rt} | gs], st) do
    quote do
      b =
        if PrologEx.Jit.var?(unquote(st.vmap[x])),
          do: if(b == 0, do: PrologEx.Jit.tick() - 1, else: b - 1),
          else: b

      unquote(tt_code(g, gs, st))
    end
  end

  defp gen_goals([{:teq, pos, a, b, :num} | gs], st) do
    {a, b} = {build_ast(a, st), build_ast(b, st)}

    t =
      if pos, do: quote(do: unquote(a) === unquote(b)), else: quote(do: unquote(a) !== unquote(b))

    test(t, gen_goals(gs, st), st)
  end

  defp gen_goals([{:teq, pos, a, b, :rt} | gs], st) do
    t =
      quote(
        do: PrologEx.Jit.teq(unquote(build_ast(a, st)), unquote(build_ast(b, st))) == unquote(pos)
      )

    test(t, gen_goals(gs, st), st)
  end

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
    do: test(quote(do: unquote(ex(r, st)) === unquote(build_ast(l, st))), gen_goals(gs, st), st)

  defp gen_goals([{:u, bt, mp} | gs], st),
    do: counted(match_ast(build_ast(bt, st), mp, gen_goals(gs, st), st))

  defp gen_goals([{:call, ck, ins, outs} | gs], st) do
    args = Enum.map(ins, &build_ast(&1, st))
    tmps = for {_, j} <- Enum.with_index(outs), do: Macro.var(:"o#{j}", __MODULE__)

    rest =
      outs
      |> Enum.zip(tmps)
      |> Enum.reverse()
      |> Enum.reduce(gen_goals(gs, st), fn {mp, tmp}, acc -> match_ast(tmp, mp, acc, st) end)

    r = Macro.var(:r, __MODULE__)

    counted(
      quote do
        case unquote(call_ast(st.targets[ck], args)) do
          {b, unquote_splicing(tmps)} ->
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
    dup = nvars == :dead or (not st.local and (cut_in?(t) or cut_in?(e)))

    {th, el} =
      if dup,
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

    if dup do
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

  # ein Typtest (ohne die Inferenz)
  defp tt_code({:tt, _, _, true}, gs, st), do: gen_goals(gs, st)
  defp tt_code({:tt, _, _, false}, _, st), do: failure(st)

  defp tt_code({:tt, t, x, :num}, gs, st) do
    v = st.vmap[x]

    t =
      if t == "integer",
        do: quote(do: is_integer(unquote(v))),
        else: quote(do: is_float(unquote(v)))

    test_ast(t, gen_goals(gs, st), st)
  end

  defp tt_code({:tt, t, x, :rt}, gs, st),
    do:
      test_ast(
        quote(do: PrologEx.Jit.tt(unquote(t), unquote(st.vmap[x])) != false),
        gen_goals(gs, st),
        st
      )

  defp tt_code({:tt, t, x, :refine}, gs, st) do
    v = st.vmap[x]
    w = Macro.unique_var(:w, __MODULE__)

    quote do
      case PrologEx.Jit.tt(unquote(t), unquote(v)) do
        false ->
          unquote(failure(st))

        unquote(w) ->
          unquote(v) = unquote(w)
          unquote(gen_goals(gs, st))
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
  #
  # Während ein übersetztes Prädikat läuft, liegt unter @run_key
  # {Blockgröße, Prüffunktion, Bindungsspeicher, min_heap_size vorher | nil,
  # Ausgabevariablen} – ein Eintrag, einmal gesetzt und einmal entfernt.

  @run_key :prolog_ex_jit

  @doc false
  # Prüfpunkt: der laufende Block ist verbraucht. Die Prüffunktion verbucht
  # den Block, prüft die Grenzen (wirft wie der Interpreter) und gibt den
  # nächsten Block zurück (>= 1)
  def tick do
    {chunk, check, store, heap, outs} = Process.get(@run_key)
    next = check.(chunk)
    Process.put(@run_key, {next, check, store, deep_stack(heap), outs})
    next
  end

  # Tiefe Rekursion: jede Garbage Collection durchsucht den ganzen Stack.
  # Ist er tief, bekommt der Heap Luft im Verhältnis (min_heap_size), damit
  # die Collections selten bleiben; nach dem Aufruf wieder wie vorher.
  # heap: nil oder {min_heap_size vorher, jetzt}
  @deep 50_000
  defp deep_stack(heap) do
    {:stack_size, s} = Process.info(self(), :stack_size)
    want = 4 * s

    case heap do
      _ when s <= @deep ->
        heap

      nil ->
        {Process.flag(:min_heap_size, want), want}

      {old, have} when want > 2 * have ->
        Process.flag(:min_heap_size, want)
        {old, want}

      _ ->
        heap
    end
  end

  @doc false
  # ein übersetztes Prädikat rufen: {:ok, Ausgaben, verbraucht} |
  # {:fail, verbraucht} | :deopt.
  #
  # Eine Liste aus der Eingabe oder einem Ergebnis ist ein gewöhnlicher Term
  # und wird erst beim Zerlegen gelesen: so viel wie der Interpreter auch
  # liest. Stößt der Code auf etwas, das er nicht kann (ein ungebundener
  # Rest, ein Element, das keine Zahl ist), gibt er auf (:deopt): er hat
  # nichts gebunden, der Interpreter fängt den Aufruf neu an. Noch nicht
  # übersetzt (das Modul fehlt): erst ab dem n-ten Aufruf (Flag
  # jit_threshold) übersetzen, vorher :deopt – der Interpreter; selten
  # gerufene Prädikate kosten so keinen Compilerlauf.
  def run({mod, _, _, _, _} = m, ins, chunk, check, store, outs) do
    if :erlang.module_loaded(mod) or warm?(mod),
      do: go(m, ins, chunk, check, store, outs, true),
      else: :deopt
  end

  # noch nicht geladen: zählen; an der Schwelle übersetzen (false: der
  # Compiler scheiterte – dann bleibt es beim Interpreter)
  defp warm?(mod) do
    case :persistent_term.get({__MODULE__, mod}, nil) do
      {:ir, _, _, _, c} ->
        :atomics.add_get(c, 1, 1) >= PrologEx.Flags.get("jit_threshold") and ensure(mod)

      _ ->
        false
    end
  end

  defp go({mod, entry, _, _, _} = m, ins, chunk, check, store, outs, retry) do
    Process.put(@run_key, {chunk, check, store, nil, outs})

    try do
      case apply(mod, entry, ins ++ [chunk]) do
        r when is_tuple(r) ->
          [b | outs] = Tuple.to_list(r)
          {:ok, outs, chunk_now() - b}

        b when b >= 0 ->
          {:fail, chunk_now() - b}

        b ->
          {:fail, chunk_now() + b + 1}
      end
    rescue
      e in UndefinedFunctionError ->
        cond do
          e.module != mod or not retry -> reraise e, __STACKTRACE__
          ensure(mod) -> :retry
          true -> :deopt
        end
    catch
      :jit_deopt -> :deopt
    after
      case Process.delete(@run_key) do
        {_, _, _, {old, _}, _} -> Process.flag(:min_heap_size, old)
        _ -> :ok
      end
    end
    |> case do
      :retry -> go(m, ins, chunk, check, store, outs, false)
      r -> r
    end
  end

  defp chunk_now, do: elem(Process.get(@run_key), 0)

  defp store, do: elem(Process.get(@run_key), 2)

  @doc false
  # ungebunden?
  def var?({:var, _} = v), do: match?({:var, _}, PrologEx.Store.walk(v, store()))
  def var?(_), do: false

  @doc false
  # Typtest auf einem Term (wie der Interpreter): false oder der gelesene
  # Term. Ist er eine Ausgabevariable des Aufrufs (oder enthält is_list/1
  # eine als Rest), aufgeben: der Interpreter hätte sie vielleicht schon
  # gebunden, der übersetzte Code bindet erst am Ende
  def tt(t, x) do
    {_, _, store, _, outs} = Process.get(@run_key)
    w = PrologEx.Store.walk(x, store)
    if outs != [] and :lists.member(w, outs), do: throw(:jit_deopt)

    ok =
      case t do
        "is_list" ->
          {_, rest} = PrologEx.Builtins.Lists.skip_list(w, store)
          if outs != [] and :lists.member(rest, outs), do: throw(:jit_deopt)
          rest == []

        _ ->
          PrologEx.type_test(t, w)
      end

    if ok, do: w, else: false
  end

  @doc false
  # ==/2 wie der Interpreter; enthält ein Term eine Ausgabevariable:
  # aufgeben (wie tt/2; die Variablen wie term_variables/2, auch zyklisch)
  def teq(a, b) do
    {_, _, store, _, outs} = Process.get(@run_key)

    if outs != [] and
         Enum.any?(PrologEx.Builtins.Order.variables([a, b], store), &:lists.member(&1, outs)),
       do: throw(:jit_deopt)

    PrologEx.Order.equal?(a, b, store)
  end

  @doc false
  # eine Listenzelle lesen: [K | R], [] oder ein anderer Term (dann passt
  # kein Muster); ein ungebundener Rest: aufgeben
  def list([_ | _] = l), do: l
  def list([]), do: []
  def list({:glist, l}), do: l

  def list({:var, _} = v) do
    case PrologEx.Store.walk(v, store()) do
      {:var, _} -> throw(:jit_deopt)
      t -> list(t)
    end
  end

  def list(t), do: t

  @doc false
  # ein Element als Zahl (num) bzw. Ganzzahl (int); sonst aufgeben – der
  # Interpreter meldet dann den Fehler oder scheitert an derselben Stelle
  def num(n) when is_integer(n) or is_float(n), do: n
  def num({:var, _} = v), do: walked(v, &(is_integer(&1) or is_float(&1)))
  def num(_), do: throw(:jit_deopt)

  def int(n) when is_integer(n), do: n
  def int({:var, _} = v), do: walked(v, &is_integer/1)
  def int(_), do: throw(:jit_deopt)

  defp walked(v, ok?) do
    x = PrologEx.Store.walk(v, store())
    if ok?.(x), do: x, else: throw(:jit_deopt)
  end
end
