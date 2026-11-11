defmodule PrologEx.Jit do
  @moduledoc """
  Übersetzt deterministische, rein arithmetische Prädikate in BEAM-Code
  (Schritt 2 des JIT-Plans). Innerhalb des übersetzten Stücks liegen die
  Werte in Erlang-Variablen: keine Bindungen, kein Zielstapel, keine
  Kompaktierung. Gebunden wird nur an den Rändern: beim Aufruf die
  Eingaben lesen (Ganzzahlen), am Ende die Ausgaben binden (frische
  Variablen). Passt ein Aufruf nicht dazu, nimmt ihn der Interpreter.

  Was übersetzt wird – jede Klausel:

    * Kopf: Ganzzahlen oder Variablen
    * Rumpf: `V is E`, arithmetische Vergleiche, `!`, `true` und Aufrufe
      des Prädikats selbst (Argumente Ganzzahlen oder Variablen)
    * E aus Ganzzahlen, Variablen und ganzzahligen Operationen
      (+ - * // mod rem div min max >> << /\\ \\/ xor gcd, einstellig
      - + abs sign msb \\)

  und das Prädikat ist nachweislich deterministisch: je zwei Klauseln
  schließen sich aus – durch einen Schnitt in der früheren, verschiedene
  Konstanten im Kopf, einen Vergleich am Anfang, der für die Konstante der
  anderen falsch ist, oder einander ausschließende Vergleiche am Anfang
  (`X > 0` / `X =< 0`). Die Modi (Eingabe/Ausgabe je Argument) ergeben sich
  aus dem Rumpf: gelesen heißt Eingabe, von `is` oder dem eigenen Aufruf
  bestimmt (oder nirgends gelesen) heißt Ausgabe.

  Gleich wie im Interpreter: Antworten, Fehler (dieselben
  Arithmetik-Funktionen), Inferenzen (jeder Aufruf und jedes eingebaute
  Ziel zählt eins, der Schnitt nicht) und Grenzen (Inferenz-, Zeit-,
  Speichergrenzen an denselben Prüfpunkten, siehe tick/0).

  Die Module heißen nach einem Hash ihrer Klauseln: dasselbe Programm
  wieder geladen nimmt das vorhandene Modul.
  """

  @ops2 ~w(+ - * // mod rem div min max >> << /\\ \\/ xor gcd)
  @ops1 ~w(- + abs sign msb \\)
  @cmps ~w(< > =< >= =:= =\\=)

  # --- Analyse ------------------------------------------------------------

  @doc """
  Übersetzt das Prädikat, wenn es passt: `{:ok, modul, eingaben, ausgaben}`
  (Argumentpositionen ab 0) oder `:no`. `source`: [{kopf, rumpf}].
  """
  def compile(source) do
    with {:ok, info} <- analyze(source) do
      {:ok, load(info), info.ins, info.outs}
    end
  catch
    :no -> :no
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
        {args(h), Enum.map(conj(b), &goal(&1, name, arity))}
      end

    modes = modes(clauses, arity)
    ins = for k <- 0..(arity - 1), modes[k] == :in, do: k
    outs = for k <- 0..(arity - 1), modes[k] == :out, do: k
    irs = Enum.map(clauses, &flow(&1, modes))
    exclusive!(irs)
    {:ok, %{name: name, arity: arity, ins: ins, outs: outs, clauses: irs, source: source}}
  end

  defp name_arity({:struct, f, a}), do: {f, length(a)}
  defp name_arity(_), do: throw(:no)

  defp args({:struct, _, a}), do: a

  # wie PrologEx.Compiler: `true` fällt weg (zählt also nicht)
  defp conj({:struct, ",", [a, b]}), do: conj(a) ++ conj(b)
  defp conj({:atom, "true"}), do: []
  defp conj(g), do: [g]

  # Terme ohne Ground-Markierung
  defp plain({tag, f, a}) when tag in [:struct, :gstruct], do: {:struct, f, Enum.map(a, &plain/1)}
  defp plain({:glist, l}), do: plain(l)
  defp plain([h | t]), do: [plain(h) | plain(t)]
  defp plain(t), do: t

  defp goal({:atom, "!"}, _, _), do: :cut
  defp goal({:atom, "true"}, _, _), do: true
  defp goal({:struct, "is", [l, r]}, _, _), do: {:is, term!(l), expr!(r)}
  defp goal({:struct, op, [a, b]}, _, _) when op in @cmps, do: {:cmp, op, expr!(a), expr!(b)}

  defp goal({:struct, name, a}, name, arity) when length(a) == arity,
    do: {:call, Enum.map(a, &term!/1)}

  defp goal(_, _, _), do: throw(:no)

  # Argument: Ganzzahl oder Variable
  defp term!(n) when is_integer(n), do: n
  defp term!({:var, _} = v), do: v
  defp term!(_), do: throw(:no)

  defp expr!(n) when is_integer(n), do: n
  defp expr!({:var, _} = v), do: v
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

  # --- Modi ---------------------------------------------------------------
  #
  # Je Kopfposition mit Variable V: der erste Gebrauch von V im Rumpf –
  # gelesen (Vergleich, rechte Seite von is) heißt Eingabe, bestimmt (linke
  # Seite von is) Ausgabe, als Argument j des eigenen Aufrufs: wie j.
  # Widerspruch: nicht übersetzbar.

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

  defp first_use(_v, []), do: nil

  defp first_use(v, [g | gs]) do
    case g do
      {:cmp, _, a, b} ->
        if v in (vars(a) ++ vars(b)), do: :in, else: first_use(v, gs)

      {:is, l, r} ->
        cond do
          v in vars(r) -> :in
          l == v -> :out
          true -> first_use(v, gs)
        end

      {:call, as} ->
        case Enum.find_index(as, &(&1 == v)) do
          nil -> first_use(v, gs)
          j -> {:as, j}
        end

      _ ->
        first_use(v, gs)
    end
  end

  # --- Datenfluss je Klausel: Zwischenform für die Codeerzeugung ----------

  defp flow({head, goals}, modes) do
    {hin, d} =
      head
      |> Enum.with_index()
      |> Enum.filter(fn {_, k} -> modes[k] == :in end)
      |> Enum.map_reduce(MapSet.new(), fn {a, k}, d ->
        cond do
          is_integer(a) -> {{k, {:const, a}}, d}
          anon?(a) -> {{k, :ignore}, d}
          MapSet.member?(d, a) -> {{k, {:eq, a}}, d}
          true -> {{k, {:bind, a}}, MapSet.put(d, a)}
        end
      end)

    hout =
      for {a, k} <- Enum.with_index(head), modes[k] == :out do
        cond do
          is_integer(a) -> {k, {:const, a}}
          anon?(a) -> throw(:no)
          true -> {k, {:var, a}}
        end
      end

    {irs, d} = Enum.map_reduce(goals, d, &goal_flow(&1, &2, modes))
    for {_, {:var, v}} <- hout, not MapSet.member?(d, v), do: throw(:no)
    %{hin: hin, hout: hout, goals: irs}
  end

  defp goal_flow(:cut, d, _), do: {:cut, d}
  defp goal_flow(true, d, _), do: {true, d}

  defp goal_flow({:cmp, op, a, b}, d, _) do
    defined!(vars(a) ++ vars(b), d)
    {{:cmp, op, a, b}, d}
  end

  defp goal_flow({:is, l, r}, d, _) do
    defined!(vars(r), d)

    cond do
      is_integer(l) or MapSet.member?(d, l) -> {{:is_eq, l, r}, d}
      anon?(l) -> {{:is_eq, :ignore, r}, d}
      true -> {{:is_def, l, r}, MapSet.put(d, l)}
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
          is_integer(a) or MapSet.member?(d, a) -> {{:eq, a}, acc}
          anon?(a) -> {:ignore, acc}
          MapSet.member?(acc, a) -> throw(:no)
          true -> {{:def, a}, MapSet.put(acc, a)}
        end
      end)

    {{:call, ins, outs}, d2}
  end

  defp defined!(vs, d), do: for(v <- vs, not MapSet.member?(d, v), do: throw(:no))

  # --- Ausschließlichkeit -------------------------------------------------

  defp exclusive!(irs) do
    pairs = for {a, i} <- Enum.with_index(irs), {b, j} <- Enum.with_index(irs), i < j, do: {a, b}
    for {a, b} <- pairs, not exclusive?(a, b), do: throw(:no)
    :ok
  end

  defp exclusive?(a, b) do
    :cut in a.goals or consts_differ?(a, b) or const_vs_guard?(a, b) or const_vs_guard?(b, a) or
      complementary?(a, b)
  end

  defp consts_differ?(a, b) do
    Enum.any?(Enum.zip(a.hin, b.hin), fn
      {{k, {:const, x}}, {k, {:const, y}}} -> x != y
      _ -> false
    end)
  end

  # a hat an k die Konstante c, b dort die Variable V und am Anfang einen
  # Vergleich nur über V, der für V = c falsch ist
  defp const_vs_guard?(a, b) do
    Enum.any?(Enum.zip(a.hin, b.hin), fn
      {{k, {:const, c}}, {k, {:bind, v}}} ->
        Enum.any?(guards(b), fn {:cmp, op, x, y} ->
          Enum.all?(vars(x) ++ vars(y), &(&1 == v)) and
            const_cmp(op, x, y, %{v => c}) == false
        end)

      _ ->
        false
    end)
  end

  defp guards(c), do: Enum.take_while(c.goals, &match?({:cmp, _, _, _}, &1))

  defp const_cmp(op, x, y, env) do
    cmp(op, ceval(x, env), ceval(y, env))
  rescue
    _ -> :unknown
  end

  defp ceval(n, _) when is_integer(n), do: n
  defp ceval({:var, _} = v, env), do: Map.fetch!(env, v)
  defp ceval({:op2, op, a, b}, env), do: PrologEx.Arith.op2(op, ceval(a, env), ceval(b, env))
  defp ceval({:op1, op, a}, env), do: PrologEx.Arith.op1(op, ceval(a, env))

  defp cmp("<", x, y), do: x < y
  defp cmp(">", x, y), do: x > y
  defp cmp("=<", x, y), do: x <= y
  defp cmp(">=", x, y), do: x >= y
  defp cmp("=:=", x, y), do: x == y
  defp cmp("=\\=", x, y), do: x != y

  # einander ausschließende Vergleiche am Anfang (über Eingaben des Kopfs)
  defp complementary?(a, b) do
    ga = for g <- guards(a), n = norm(g, a), n != nil, do: n
    gb = for g <- guards(b), n = norm(g, b), n != nil, do: n
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
  # p(Eingaben..., B) -> {:ok, {Ausgaben...}, B} | {:fail, B}; je Klausel
  # cK(...) mit {:cutfail, B} nach einem Schnitt. B: Inferenzen bis zum
  # nächsten Prüfpunkt (tick/0).

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
        {:fail, b} -> unquote(gen_dispatch(i + 1, n, ins))
        {:cutfail, b} -> {:fail, b}
        r -> r
      end
    end
  end

  # Aufruf der Klauselfunktion cI(Eingaben..., b)
  defp ccall(i, ins), do: {:"c#{i}", [], ins ++ [Macro.var(:b, __MODULE__)]}

  defp gen_clause(c, i, info) do
    ins = Enum.map(info.ins, &in_var/1)
    vmap = var_map(c)
    body = gen_goals(c.goals, c, vmap, false)
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
    vs =
      (for({_, {tag, v}} <- c.hin, tag in [:bind, :eq], do: v) ++
         for({_, {:var, v}} <- c.hout, do: v) ++ Enum.flat_map(c.goals, &goal_vars/1))
      |> Enum.uniq()

    vs |> Enum.with_index() |> Map.new(fn {v, j} -> {v, Macro.var(:"v#{j}", __MODULE__)} end)
  end

  defp goal_vars({:cmp, _, a, b}), do: vars(a) ++ vars(b)
  defp goal_vars({:is_def, l, r}), do: [l | vars(r)]
  defp goal_vars({:is_eq, l, r}), do: vars(l) ++ vars(r)

  defp goal_vars({:call, ins, outs}),
    do:
      Enum.filter(ins, &match?({:var, _}, &1)) ++
        for({t, v} <- outs, t in [:def, :eq], match?({:var, _}, v), do: v)

  defp goal_vars(_), do: []

  defp gen_head([], _vmap, body), do: body

  defp gen_head([{k, spec} | rest], vmap, body) do
    i = in_var(k)
    inner = gen_head(rest, vmap, body)

    case spec do
      :ignore ->
        inner

      {:const, c} ->
        quote(do: if(unquote(i) === unquote(c), do: unquote(inner), else: {:fail, b}))

      {:bind, v} ->
        quote do
          unquote(vmap[v]) = unquote(i)
          unquote(inner)
        end

      {:eq, v} ->
        quote(do: if(unquote(i) === unquote(vmap[v]), do: unquote(inner), else: {:fail, b}))
    end
  end

  defp fail_ast(true), do: quote(do: {:cutfail, b})
  defp fail_ast(false), do: quote(do: {:fail, b})

  # eine Inferenz verbrauchen (Prüfpunkt bei 0)
  defp dec_ast, do: quote(do: b = if(b == 0, do: PrologEx.Jit.tick() - 1, else: b - 1))

  defp gen_goals([], c, vmap, _cut) do
    outs = for {_, spec} <- c.hout, do: out_ast(spec, vmap)
    quote(do: {:ok, {unquote_splicing(outs)}, b})
  end

  defp gen_goals([:cut | gs], c, vmap, _cut), do: gen_goals(gs, c, vmap, true)

  defp gen_goals([true | gs], c, vmap, cut) do
    quote do
      unquote(dec_ast())
      unquote(gen_goals(gs, c, vmap, cut))
    end
  end

  defp gen_goals([{:cmp, op, x, y} | gs], c, vmap, cut) do
    test = cmp_ast(op, ex(x, vmap), ex(y, vmap))

    quote do
      unquote(dec_ast())

      if unquote(test),
        do: unquote(gen_goals(gs, c, vmap, cut)),
        else: unquote(fail_ast(cut))
    end
  end

  defp gen_goals([{:is_def, l, r} | gs], c, vmap, cut) do
    quote do
      unquote(dec_ast())
      unquote(vmap[l]) = unquote(ex(r, vmap))
      unquote(gen_goals(gs, c, vmap, cut))
    end
  end

  defp gen_goals([{:is_eq, l, r} | gs], c, vmap, cut) do
    value = ex(r, vmap)

    check =
      case l do
        :ignore -> quote(do: _ = unquote(value))
        _ -> quote(do: unquote(value) === unquote(term_ast(l, vmap)))
      end

    rest = gen_goals(gs, c, vmap, cut)

    if l == :ignore do
      quote do
        unquote(dec_ast())
        unquote(check)
        unquote(rest)
      end
    else
      quote do
        unquote(dec_ast())
        if unquote(check), do: unquote(rest), else: unquote(fail_ast(cut))
      end
    end
  end

  defp gen_goals([{:call, ins, outs} | gs], c, vmap, cut) do
    args = Enum.map(ins, &term_ast(&1, vmap))

    {pats, checks} =
      outs
      |> Enum.with_index()
      |> Enum.map(fn
        {{:def, v}, _} ->
          {vmap[v], nil}

        {:ignore, _} ->
          {Macro.var(:_, nil), nil}

        {{:eq, t}, j} ->
          tmp = Macro.var(:"o#{j}", __MODULE__)
          {tmp, quote(do: unquote(tmp) === unquote(term_ast(t, vmap)))}
      end)
      |> Enum.unzip()

    checks = Enum.reject(checks, &is_nil/1)
    rest = gen_goals(gs, c, vmap, cut)

    rest =
      case checks do
        [] ->
          rest

        _ ->
          test = Enum.reduce(checks, fn x, acc -> quote(do: unquote(acc) and unquote(x)) end)
          quote(do: if(unquote(test), do: unquote(rest), else: unquote(fail_ast(cut))))
      end

    quote do
      unquote(dec_ast())

      case p(unquote_splicing(args), b) do
        {:ok, {unquote_splicing(pats)}, b} -> unquote(rest)
        {_, b} -> unquote(fail_ast(cut))
      end
    end
  end

  defp out_ast({:const, c}, _vmap), do: c
  defp out_ast({:var, v}, vmap), do: vmap[v]

  defp term_ast(n, _vmap) when is_integer(n), do: n
  defp term_ast(v, vmap), do: Map.fetch!(vmap, v)

  # Ausdruck: + - * direkt (Ganzzahlen bleiben Ganzzahlen), sonst genau
  # wie der Interpreter (PrologEx.Arith)
  defp ex(n, _vmap) when is_integer(n), do: n
  defp ex({:var, _} = v, vmap), do: Map.fetch!(vmap, v)
  defp ex({:op2, "+", a, b}, m), do: quote(do: unquote(ex(a, m)) + unquote(ex(b, m)))
  defp ex({:op2, "-", a, b}, m), do: quote(do: unquote(ex(a, m)) - unquote(ex(b, m)))
  defp ex({:op2, "*", a, b}, m), do: quote(do: unquote(ex(a, m)) * unquote(ex(b, m)))

  defp ex({:op2, op, a, b}, m),
    do: quote(do: PrologEx.Arith.op2(unquote(op), unquote(ex(a, m)), unquote(ex(b, m))))

  defp ex({:op1, "-", a}, m), do: quote(do: -unquote(ex(a, m)))
  defp ex({:op1, "+", a}, m), do: ex(a, m)
  defp ex({:op1, op, a}, m), do: quote(do: PrologEx.Arith.op1(unquote(op), unquote(ex(a, m))))

  defp cmp_ast("<", x, y), do: quote(do: unquote(x) < unquote(y))
  defp cmp_ast(">", x, y), do: quote(do: unquote(x) > unquote(y))
  defp cmp_ast("=<", x, y), do: quote(do: unquote(x) <= unquote(y))
  defp cmp_ast(">=", x, y), do: quote(do: unquote(x) >= unquote(y))
  defp cmp_ast("=:=", x, y), do: quote(do: unquote(x) === unquote(y))
  defp cmp_ast("=\\=", x, y), do: quote(do: unquote(x) !== unquote(y))

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
        {:ok, outs, b} -> {:ok, Tuple.to_list(outs), used(b)}
        {_, b} -> {:fail, used(b)}
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
