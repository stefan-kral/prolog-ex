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
  Übersetzt das Prädikat, wenn es passt: `{:ok, modul, eingaben, ausgaben}`
  (Argumentpositionen ab 0; eingaben `{:num, ks}`, wenn auch Floats
  hineindürfen) oder `:no`. `source`: [{kopf, rumpf}].
  """
  def compile(source) do
    with {:ok, info} <- analyze(source) do
      ins = if info.num, do: {:num, info.ins}, else: info.ins
      {:ok, load(info), ins, info.outs}
    end
  catch
    :no -> :no
  end

  @doc false
  # der erzeugte Elixir-Code (zum Nachsehen)
  def code(source) do
    with {:ok, info} <- analyze(source), do: Macro.to_string(gen(Jit.Code.Show, info))
  end

  @doc false
  def analyze([]), do: :no

  def analyze(source) do
    analyze!(source)
  catch
    :no -> :no
  end

  defp analyze!(source) do
    source = Enum.map(source, fn {h, b} -> {plain(h), plain(b)} end)
    {name, arity} = name_arity(elem(hd(source), 0))
    if arity == 0, do: throw(:no)

    clauses =
      for {h, b} <- source do
        head = args(h)
        Enum.each(head, &term!/1)
        {head, Enum.map(conj(b), &goal(&1, name, arity))}
      end

    num = not int_only?(clauses)
    modes = modes(clauses, arity)
    ins = for k <- 0..(arity - 1), modes[k] == :in, do: k
    outs = for k <- 0..(arity - 1), modes[k] == :out, do: k
    irs = Enum.map(clauses, &flow(&1, modes))
    exclusive!(irs, num)

    {:ok,
     %{name: name, arity: arity, ins: ins, outs: outs, clauses: irs, source: source, num: num}}
  end

  defp name_arity({:struct, f, a}), do: {f, length(a)}
  defp name_arity(_), do: throw(:no)

  defp args({:struct, _, a}), do: a

  # wie PrologEx.Compiler: `true` im Rumpf fällt weg (zählt also nicht)
  defp conj({:struct, ",", [a, b]}), do: conj(a) ++ conj(b)
  defp conj({:atom, "true"}), do: []
  defp conj(g), do: [g]

  # in Steuerkonstrukten bleibt `true` ein Ziel (zählt eins)
  defp seq({:struct, ",", [a, b]}, n, ar), do: seq(a, n, ar) ++ seq(b, n, ar)
  defp seq(g, n, ar), do: [goal(g, n, ar)]

  # Terme ohne Ground-Markierung
  defp plain({tag, f, a}) when tag in [:struct, :gstruct], do: {:struct, f, Enum.map(a, &plain/1)}
  defp plain({:glist, l}), do: plain(l)
  defp plain([h | t]), do: [plain(h) | plain(t)]
  defp plain(t), do: t

  defp goal({:atom, "!"}, _, _), do: :cut
  defp goal({:atom, "true"}, _, _), do: true
  defp goal({:atom, f}, _, _) when f in ["fail", "false"], do: :fail
  defp goal({:struct, "is", [l, r]}, _, _), do: {:is, term!(l), expr!(r)}
  defp goal({:struct, op, [a, b]}, _, _) when op in @cmps, do: {:cmp, op, expr!(a), expr!(b)}
  defp goal({:struct, "=", [a, b]}, _, _), do: {:unify, term!(a), term!(b)}

  defp goal({:struct, ";", [{:struct, "->", [c, t]}, e]}, n, ar),
    do: {:ite, seq(c, n, ar), seq(t, n, ar), seq(e, n, ar)}

  # ( C -> T ) ohne Else: der Interpreter nimmt `fail` als Else (zählt eins)
  defp goal({:struct, "->", [c, t]}, n, ar), do: {:ite, seq(c, n, ar), seq(t, n, ar), [:fail]}
  defp goal({:struct, "\\+", [g]}, n, ar), do: {:not, seq(g, n, ar)}

  defp goal({:struct, name, a}, name, arity) when length(a) == arity,
    do: {:call, Enum.map(a, &term!/1)}

  defp goal(_, _, _), do: throw(:no)

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
  # Seite von is) Ausgabe, als Argument j des eigenen Aufrufs: wie j; in
  # `=` legt er nichts fest. Widerspruch: nicht übersetzbar.

  defp modes(clauses, arity) do
    ev =
      for {head, goals} <- clauses,
          {a, k} <- Enum.with_index(head),
          match?({:var, _}, a),
          not anon?(a),
          e = first_use(a, goals),
          e != nil,
          do: {k, e}

    m0 = for {k, e} <- ev, e in [:in, :out], reduce: %{}, do: (acc -> put_mode(acc, k, e))
    m = fix_modes(m0, ev)
    # unbestimmt (nirgends gelesen): Ausgabe – etwa gcd(X, 0, X); passt ein
    # Aufruf nicht dazu, nimmt ihn der Interpreter
    Map.new(0..(arity - 1), &{&1, Map.get(m, &1, :out)})
  end

  defp put_mode(m, k, e) do
    case m do
      %{^k => ^e} -> m
      %{^k => _} -> throw(:no)
      _ -> Map.put(m, k, e)
    end
  end

  defp fix_modes(m, ev) do
    m2 =
      Enum.reduce(ev, m, fn
        {k, {:as, j}}, acc -> if Map.has_key?(acc, j), do: put_mode(acc, k, acc[j]), else: acc
        _, acc -> acc
      end)

    if m2 == m, do: m, else: fix_modes(m2, ev)
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

  defp use_in(v, {:call, as}) do
    case Enum.find_index(as, &(&1 == v)) do
      nil -> nil
      j -> {:as, j}
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

  defp flow({head, goals}, modes) do
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

    {irs, d} = flow_seq(goals, d, modes)
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

  defp goal_flow({:call, as}, d, modes) do
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

    {{:call, ins, outs}, d2}
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

  defp load(info) do
    hash =
      :crypto.hash(:sha256, :erlang.term_to_binary({info.source, info.ins, info.outs}))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 20)

    mod = Module.concat(PrologEx.Jit.Code, "P" <> hash)

    unless Code.ensure_loaded?(mod) do
      {_, _} = Code.with_diagnostics([log: false], fn -> Code.compile_quoted(gen(mod, info)) end)
    end

    mod
  end

  defp gen(mod, info) do
    ins = Enum.map(info.ins, &in_var/1)
    n = length(info.clauses)

    clause_funs =
      info.clauses
      |> Enum.with_index(1)
      |> Enum.map(fn {c, i} -> gen_clause(c, i, info) end)

    dispatch = gen_dispatch(1, n, ins)

    quote do
      defmodule unquote(mod) do
        @moduledoc false
        @compile {:no_warn_undefined, PrologEx.Jit}

        def entry(unquote_splicing(ins), b) do
          p(unquote_splicing(ins), b)
        rescue
          ArithmeticError -> PrologEx.Error.evaluation!("undefined")
          SystemLimitError -> PrologEx.Error.resource!("memory")
        end

        def p(unquote_splicing(ins), b), do: unquote(dispatch)
        unquote_splicing(clause_funs)
      end
    end
  end

  defp gen_dispatch(n, n, ins), do: ccall(n, ins)

  defp gen_dispatch(i, n, ins) do
    quote do
      case unquote(ccall(i, ins)) do
        b when is_integer(b) and b >= 0 -> unquote(gen_dispatch(i + 1, n, ins))
        r -> r
      end
    end
  end

  # Aufruf der Klauselfunktion cI(Eingaben..., b)
  defp ccall(i, ins), do: {:"c#{i}", [], ins ++ [Macro.var(:b, __MODULE__)]}

  defp gen_clause(c, i, info) do
    ins = Enum.map(info.ins, &in_var/1)
    vmap = var_map(c)
    st = %{vmap: vmap, cut: false, local: false, num: info.num, hout: c.hout}
    body = gen_goals(c.goals ++ [:end], st)
    head = gen_head(c.hin, vmap, body)
    name = :"c#{i}"

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

  defp gen_goals([{:call, ins, outs} | gs], st) do
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
        case p(unquote_splicing(args), b) do
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

  @doc false
  # Prüfpunkt: der laufende Block ist verbraucht. Die Maschine hat vorher
  # {Blockgröße, Prüffunktion} hinterlegt; die Prüffunktion verbucht den
  # Block, prüft die Grenzen (wirft wie der Interpreter) und gibt den
  # nächsten Block zurück (>= 1)
  def tick do
    {chunk, check} = Process.get(@tick_key)
    next = check.(chunk)
    Process.put(@tick_key, {next, check})
    next
  end

  @doc false
  # ein übersetztes Prädikat rufen: {:ok, Ausgaben, verbraucht} | {:fail, verbraucht}
  def run(mod, ins, chunk, check) do
    Process.put(@tick_key, {chunk, check})

    try do
      case apply(mod, :entry, ins ++ [chunk]) do
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
    end
  end

  defp used(b) do
    {chunk, _} = Process.get(@tick_key)
    chunk - b
  end
end
