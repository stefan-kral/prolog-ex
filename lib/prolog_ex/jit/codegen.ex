defmodule PrologEx.Jit.Codegen do
  @moduledoc """
  Codeerzeugung für PrologEx.Jit: aus der Zwischenform der gelösten
  Komponenten (PrologEx.Jit, settle) Elixir-AST, je Komponente ein Modul
  (Name: Hash des Inhalts), übersetzt beim n-ten Aufruf (ensure/1, Flag
  jit_threshold). Der erzeugte Code ruft PrologEx.Jit.Runtime.
  """
  alias PrologEx.Jit.Util

  # so viele Ziele (ohne Rekursion), damit sich der Eintritt lohnt
  @entry_size 1

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

  def build(s, how) do
    s.parsed
    |> Map.take(Map.keys(s.solved))
    |> Util.sccs()
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
          bdeps: r.p.bdeps,
          sig: sig,
          nd: Map.get(sig, :nd, false)
        }
      end)

    local = Map.new(infos, &{&1.key, {:local, :"p#{&1.j}"}})

    # Aus dem Interpreter lohnt der Eintritt, wo der Code wenigstens ein
    # Ziel hat oder etwas wiederholt (rekursiv, oder ruft Rekursives) –
    # schon ein Vergleich spart mehr, als der Wechsel kostet; ein Fakt
    # nicht. Übersetzt wird trotzdem – für übersetzte Rufer
    entry =
      Enum.any?(infos, & &1.nd) or length(scc) > 1 or Enum.any?(scc, &s.parsed[&1].rec) or
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
             &{Enum.map(&1.clauses, fn c -> canon(c) end), &1.ins, &1.outs, &1.num, &1.nd}
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
              do:
                {i.key, {{mod, :"e#{i.j}", :"p#{i.j}", i.deps ++ i.bdeps, i.sig}, i.ins, i.outs}}

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
    key = {PrologEx.Jit, mod}

    unless :erlang.module_loaded(mod) or :persistent_term.get(key, nil) != nil do
      callees = for({_, {:remote, m, _}} <- targets, do: m) |> Enum.uniq()
      slim = Enum.map(infos, &Map.take(&1, [:j, :ins, :clauses, :num, :nd]))
      # Aufrufzähler bis zur Schwelle (Flag jit_threshold, siehe run/7)
      :persistent_term.put(key, {:ir, slim, targets, callees, :atomics.new(1, [])})
    end
  end

  @doc false
  # das Modul geladen? Sonst jetzt übersetzen (Gerufene zuerst); scheitert
  # der Compiler (etwa an einer Grenze der BEAM), bleibt es beim
  # Interpreter (false)
  #
  # Je Modul nur ein Prozess zugleich (eine Sperre je Modul): übersetzten
  # zwei Prozesse dasselbe Modul gleichzeitig (Kinder von
  # library(concurrent), die das Prädikat zum ersten Mal rufen), scheiterte
  # einer an der doppelten Definition und lüde den Ersatz (stub/2) – der
  # ersetzte das gute Modul, jeder Aufruf gäbe auf, und das Prädikat würde
  # kalt (Interpreter, bis zu 100-mal langsamer). Wer wartet, findet das
  # Modul danach geladen.
  def ensure(mod) do
    :erlang.module_loaded(mod) or
      :global.trans({{PrologEx.Jit, mod}, self()}, fn -> compile_now(mod) end, [node()])
  end

  defp compile_now(mod) do
    case :erlang.module_loaded(mod) or :persistent_term.get({PrologEx.Jit, mod}, nil) do
      true ->
        true

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

        # deterministisch: p ruft die erste Klausel; jede ruft beim
        # Scheitern vor einem Schnitt selbst die nächste (so bleibt ein
        # Aufruf am Schluss einer Klausel Endaufruf, siehe failure/1)
        nd = Map.get(info, :nd, false)

        clause_funs =
          info.clauses
          |> Enum.with_index(1)
          |> Enum.map(fn {c, i} ->
            next = if not nd and i < n, do: ccall(info.j, i + 1, ins)
            gen_clause(c, i, info, targets, not nd and i == n, next)
          end)

        dispatch = ccall(info.j, 1, ins)

        if nd do
          t1 = {:"t#{info.j}_1", [], ins ++ [Macro.var(:b, __MODULE__)]}

          [
            quote(do: def(unquote(e)(unquote_splicing(ins), b), do: unquote(t1))),
            quote(do: def(unquote(pf)(unquote_splicing(ins), b), do: unquote(t1)))
            | gen_nd_chain(info, ins, n) ++ clause_funs
          ]
        else
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
        end
      end)

    cse = if cse_off?(), do: [quote(do: @compile(:no_ssa_opt_cse))], else: []

    quote do
      defmodule unquote(mod) do
        @moduledoc false
        @compile {:no_warn_undefined, PrologEx.Jit.Runtime}
        unquote_splicing(cse)
        unquote_splicing(funs)
      end
    end
  end

  # Der JIT der BEAM rechnet `X * X + X * X` falsch (OTP-19889, behoben in
  # ERTS 16.3.1 und 15.2.7.7): nach der Optimierung gemeinsamer
  # Teilausdrücke wird daraus `Y + Y` aus einem Register, und der
  # Maschinencode liest einen Operanden veraltet (`Z = Y * X, Z + Z` gibt
  # X + Z; `V0 is V1 * 0 + V1 * 0` gab 3, manche Formen bringen die BEAM
  # zum Absturz). Für ERTS vor 15.2.7.7 und 16.0 bis vor 16.3.1 (ältere
  # Linien vorsichtshalber mit) den erzeugten Code ohne sie übersetzen
  # (kostet dort bis 11 %: crypt 8 %, deriv 11 %)
  defp cse_off? do
    case :persistent_term.get({__MODULE__, :cse_off}, nil) do
      nil ->
        v = jit_bug_19889?(erts_version())
        :persistent_term.put({__MODULE__, :cse_off}, v)
        v

      v ->
        v
    end
  end

  @doc false
  def erts_version do
    :erlang.system_info(:version)
    |> to_string()
    |> String.split(".")
    |> Enum.map(&(Integer.parse(&1) |> elem(0)))
  end

  @doc false
  def jit_bug_19889?(v), do: v < [15, 2, 7, 7] or (v >= [16] and v < [16, 3, 1])

  # nichtdeterministisch: t<j>_<i> versucht Klausel i, dann (beim
  # Zurücksetzen) die nächsten. Ergebnis {:sol, b, Ausgaben, weiter} (weiter:
  # fn b -> ... end oder nil, wenn nichts mehr kommt) oder {:none, b}
  defp gen_nd_chain(info, ins, n) do
    b = Macro.var(:b, __MODULE__)
    j = info.j

    for {c, i} <- Enum.with_index(info.clauses, 1) do
      tnext = {:"t#{j}_#{i + 1}", [], ins ++ [b]}
      last = i == n or :cut in c.goals
      next = if last, do: nil, else: quote(do: fn b -> unquote(tnext) end)
      failnext = if i == n, do: quote(do: {:none, b}), else: tnext

      quote do
        defp unquote(:"t#{j}_#{i}")(unquote_splicing(ins), b) do
          case unquote(ccall(j, i, ins)) do
            {:tail, step, mapf} ->
              PrologEx.Jit.Runtime.nd_tail(step, mapf, unquote(next))

            r when is_tuple(r) ->
              [b | outs] = Tuple.to_list(r)
              {:sol, b, outs, unquote(next)}

            b when b >= 0 ->
              unquote(failnext)

            nb ->
              {:none, -nb - 1}
          end
        end
      end
    end
  end

  # Aufruf der Klauselfunktion c<j>_<i>(Eingaben..., b)
  defp ccall(j, i, ins), do: {:"c#{j}_#{i}", [], ins ++ [Macro.var(:b, __MODULE__)]}

  defp gen_clause(c, i, info, targets, last, next) do
    ins = Enum.map(info.ins, fn {k, _} -> in_var(k) end)
    vmap = var_map(c)

    st = %{
      vmap: vmap,
      cut: false,
      local: false,
      num: info.num,
      hout: c.hout,
      targets: targets,
      last: last,
      next: next,
      join: false
    }

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

  defp match_ast(v, {:eqrt, x}, then, st),
    do: test_ast(quote(do: PrologEx.Jit.Runtime.ueq(unquote(v), unquote(st.vmap[x]))), then, st)

  defp match_ast(v, {:const, c}, then, st),
    do: test_ast(quote(do: unquote(v) === unquote(c)), then, st)

  defp match_ast(v, {:constrt, c}, then, st),
    do:
      test_ast(
        quote(do: PrologEx.Jit.Runtime.eqc(unquote(v), unquote(Macro.escape(c)))),
        then,
        st
      )

  # Strukturen werden erst beim Zerlegen gelesen (PrologEx.Jit.Runtime.st/3)
  defp match_ast(v, {:st, f, mps}, then, st) do
    xs = for _ <- mps, do: Macro.unique_var(:a, __MODULE__)

    inner =
      xs
      |> Enum.zip(mps)
      |> Enum.reverse()
      |> Enum.reduce(then, fn {x, mp}, acc -> match_ast(x, mp, acc, st) end)

    quote do
      case PrologEx.Jit.Runtime.st(unquote(v), unquote(f), unquote(length(mps))) do
        [unquote_splicing(xs)] -> unquote(inner)
        _ -> unquote(failure(st))
      end
    end
  end

  # Listen werden erst beim Zerlegen gelesen (PrologEx.Jit.Runtime.list/1)
  defp match_ast(v, :nl, then, st),
    do: test_ast(quote(do: PrologEx.Jit.Runtime.list(unquote(v)) === []), then, st)

  defp match_ast(v, {:cons, h, t}, then, st) do
    hv = Macro.unique_var(:h, __MODULE__)
    tv = Macro.unique_var(:t, __MODULE__)

    quote do
      case PrologEx.Jit.Runtime.list(unquote(v)) do
        [unquote(hv) | unquote(tv)] -> unquote(match_ast(hv, h, match_ast(tv, t, then, st), st))
        _ -> unquote(failure(st))
      end
    end
  end

  defp match_ast(v, {:num, mp}, then, st) do
    n = Macro.unique_var(:n, __MODULE__)
    f = if st.num, do: :num, else: :int

    quote do
      unquote(n) = PrologEx.Jit.Runtime.unquote(f)(unquote(v))
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
  defp build_ast({:atom, _} = a, _st), do: Macro.escape(a)

  # ein Argument, das keine ungebundene Variable sein darf (Types.arg_check/4)
  defp build_ast({:nv, b}, st), do: quote(do: PrologEx.Jit.Runtime.nv(unquote(build_ast(b, st))))

  defp build_ast({:st, f, bs}, st),
    do: quote(do: {:struct, unquote(f), unquote(Enum.map(bs, &build_ast(&1, st)))})

  # Scheitern: lokal (in einer Bedingung, unter \+) b. Sonst nach einem
  # Schnitt -b-1; in einer Klausel eines deterministischen Prädikats davor
  # gleich die nächste Klausel (next), in der letzten -b-1. So scheitert ein
  # deterministisches Prädikat immer mit -b-1, und ein Aufruf am Schluss
  # (letzte Klausel oder nach einem Schnitt) gibt sein Ergebnis unverändert
  # weiter: Endaufruf. In einem Zweig, der danach zusammengeführt wird
  # (join), b – erst nach dem Zusammenführen die nächste Klausel
  defp failure(%{local: true}), do: quote(do: b)
  defp failure(%{cut: true}), do: quote(do: -b - 1)
  defp failure(%{join: true}), do: quote(do: b)
  defp failure(%{last: true}), do: quote(do: -b - 1)
  defp failure(%{next: next}) when next != nil, do: next
  defp failure(_), do: quote(do: b)

  # Ergebnis eines Aufrufs: Scheitern (auch nach Schnitt) in b
  defp unfail(r), do: quote(do: if(unquote(r) >= 0, do: unquote(r), else: -unquote(r) - 1))

  # eine Inferenz verbrauchen (Prüfpunkt bei 0)
  defp dec_ast, do: quote(do: b = if(b == 0, do: PrologEx.Jit.Runtime.tick() - 1, else: b - 1))

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
  # Scheitern ohne Inferenz (Ende einer Disjunktion vor einem Schnitt)
  defp gen_goals([:fail0 | _], st), do: failure(st)

  defp gen_goals([{:tt, _, _, _} = g | gs], st), do: counted(tt_code(g, gs, st))

  # Wächter des Interpreter-Index (siehe parse/3): gezählt nur, wenn das
  # erste Argument ungebunden ist
  defp gen_goals([{:idx, g, true} | gs], st), do: tt_code(g, gs, st)
  defp gen_goals([{:idx, g, false} | gs], st), do: gen_goals([g | gs], st)

  defp gen_goals([{:idx, {:tt, _, x, _} = g, :rt} | gs], st) do
    quote do
      b =
        if PrologEx.Jit.Runtime.var?(unquote(st.vmap[x])),
          do: if(b == 0, do: PrologEx.Jit.Runtime.tick() - 1, else: b - 1),
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
        do:
          PrologEx.Jit.Runtime.teq(unquote(build_ast(a, st)), unquote(build_ast(b, st))) ==
            unquote(pos)
      )

    test(t, gen_goals(gs, st), st)
  end

  defp gen_goals([{:tord, op, a, b} | gs], st) do
    t =
      quote(
        do:
          PrologEx.Jit.Runtime.tord(
            unquote(op),
            unquote(build_ast(a, st)),
            unquote(build_ast(b, st))
          )
      )

    test(t, gen_goals(gs, st), st)
  end

  defp gen_goals([{:bi, name, ins, outs} | gs], st) do
    args = Enum.map(ins, &build_ast(&1, st))
    tmps = for {_, j} <- Enum.with_index(outs), do: Macro.var(:"o#{j}", __MODULE__)

    rest =
      outs
      |> Enum.zip(tmps)
      |> Enum.reverse()
      |> Enum.reduce(gen_goals(gs, st), fn {mp, tmp}, acc -> match_ast(tmp, mp, acc, st) end)

    code =
      counted(
        quote do
          case PrologEx.Jit.Runtime.unquote(:"b_#{name}")(unquote_splicing(args)) do
            {unquote_splicing(tmps)} -> unquote(rest)
            :no -> unquote(failure(st))
          end
        end
      )

    # bit_is_set/2 ist in Prolog ein Aufruf von '$bit_is_set'/2: zwei
    # Inferenzen wie im Interpreter
    if name == "bit_is_set", do: counted(code), else: code
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

  # Endaufruf: letztes Ziel der Klausel, Ausgaben die der Klausel, und
  # das Scheitern des Gerufenen (immer -b-1, siehe failure/1) ist auch
  # ihres – in der letzten Klausel oder nach einem Schnitt. Ohne den Rahmen
  # des case läuft eine Schleife in konstantem Speicher
  defp gen_goals([{:call, ck, ins, outs}, :end], %{local: false} = st)
       when st.last or st.cut do
    if Util.same_outs?(outs, st.hout) do
      args = Enum.map(ins, &build_ast(&1, st))
      counted(call_ast(st.targets[ck], args))
    else
      gen_call(ck, ins, outs, [:end], st)
    end
  end

  defp gen_goals([{:call, ck, ins, outs} | gs], st), do: gen_call(ck, ins, outs, gs, st)

  # letzter Aufruf eines nichtdeterministischen Prädikats: seine Lösungen
  # (step) und wie aus seinen Ausgaben die der Klausel werden (mapf: fn
  # Ausgaben, b -> {b, Ausgaben der Klausel} | b; nil, wenn sie dieselben
  # sind)
  defp gen_goals([{:tail_nd, ck, ins, outs} | _], st) do
    args = Enum.map(ins, &build_ast(&1, st))
    step = call_ast(st.targets[ck], args)

    if Util.same_outs?(outs, st.hout) do
      counted(quote(do: {:tail, unquote(step), nil}))
    else
      st2 = %{st | cut: false, local: true}
      tmps = for {_, j} <- Enum.with_index(outs), do: Macro.var(:"o#{j}", __MODULE__)
      houts = for {_, bt} <- st.hout, do: build_ast(bt, st)

      body =
        outs
        |> Enum.zip(tmps)
        |> Enum.reverse()
        |> Enum.reduce(quote(do: {b, unquote(houts)}), fn {mp, tmp}, acc ->
          match_ast(tmp, mp, acc, st2)
        end)

      counted(
        quote do
          {:tail, unquote(step), fn unquote(tmps), b -> unquote(body) end}
        end
      )
    end
  end

  # erste Lösung eines nichtdeterministisch übersetzten Gerufenen, deren
  # Ausgaben zu den Mustern passen (wie der Interpreter: er setzte in den
  # Gerufenen zurück, bis eine passt). Nur frische Variablen als Muster:
  # gleich die erste
  defp gen_goals([{:call1, ck, ins, outs} | gs], st) do
    args = Enum.map(ins, &build_ast(&1, st))
    tmps = for {_, j} <- Enum.with_index(outs), do: Macro.var(:"o#{j}", __MODULE__)
    step = call_ast(st.targets[ck], args)

    if Enum.all?(outs, &(&1 == :ignore or match?({:bind, _}, &1))) do
      rest =
        outs
        |> Enum.zip(tmps)
        |> Enum.reverse()
        |> Enum.reduce(gen_goals(gs, st), fn {mp, tmp}, acc -> match_ast(tmp, mp, acc, st) end)

      counted(
        quote do
          case unquote(step) do
            {:sol, b, unquote(tmps), _} -> unquote(rest)
            {:none, b} -> unquote(failure(st))
          end
        end
      )
    else
      st2 = %{st | cut: false, local: true}
      bound = outs |> pat_binds() |> Enum.uniq() |> Enum.sort()
      bvs = vs(bound, st)

      matched =
        outs
        |> Enum.zip(tmps)
        |> Enum.reverse()
        |> Enum.reduce(quote(do: {:ok, b, {unquote_splicing(bvs)}}), fn {mp, tmp}, acc ->
          match_ast(tmp, mp, acc, st2)
        end)

      counted(
        quote do
          case PrologEx.Jit.Runtime.nd_first(unquote(step), fn unquote(tmps), b ->
                 unquote(matched)
               end) do
            {:ok, b, {unquote_splicing(bvs)}} -> unquote(gen_goals(gs, st))
            {:none, b} -> unquote(failure(st))
          end
        end
      )
    end
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
    # danach nur noch das Ende: beide Zweige gleich zu Ende führen (nichts
    # doppelt, und ein Aufruf am Schluss eines Zweigs bleibt Endaufruf)
    dup =
      nvars == :dead or gs == [:end] or (not st.local and (Util.cut_in?(t) or Util.cut_in?(e)))

    {th, el} =
      if dup,
        do: {gen_goals(t ++ gs, st), gen_goals(e ++ gs, st)},
        else:
          {gen_goals(t ++ [{:yield, :join, nvars}], %{st | join: true}),
           gen_goals(e ++ [{:yield, :join, nvars}], %{st | join: true})}

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
          b when is_integer(b) and b >= 0 -> unquote(failure(st))
          r -> r
        end
      end
    end
  end

  defp gen_call(ck, ins, outs, gs, st) do
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

  # Variablen, die ein Muster bindet
  defp pat_binds({:bind, v}), do: [v]
  defp pat_binds(t) when is_tuple(t), do: pat_binds(Tuple.to_list(t))
  defp pat_binds(l) when is_list(l), do: Enum.flat_map(l, &pat_binds/1)
  defp pat_binds(_), do: []

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
        quote(do: PrologEx.Jit.Runtime.tt(unquote(t), unquote(st.vmap[x])) != false),
        gen_goals(gs, st),
        st
      )

  defp tt_code({:tt, t, x, :refine}, gs, st) do
    v = st.vmap[x]
    w = Macro.unique_var(:w, __MODULE__)

    quote do
      case PrologEx.Jit.Runtime.tt(unquote(t), unquote(v)) do
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
  # msb, lsb, popcount, \\ direkt (in Bitschleifen heiß; op1/2 sucht
  # sonst unter allen Funktoren: msb 100 → 25 ns)
  defp ex({:op1, op, a}, st) when op in ["msb", "lsb", "popcount"],
    do: quote(do: PrologEx.Arith.unquote(:"#{op}1")(unquote(ex(a, st))))

  defp ex({:op1, "\\", a}, st), do: quote(do: PrologEx.Arith.bnot1(unquote(ex(a, st))))

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
end
