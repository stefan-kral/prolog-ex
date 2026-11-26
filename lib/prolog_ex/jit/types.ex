defmodule PrologEx.Jit.Types do
  @moduledoc false
  # Typen (Fixpunkt über eine Komponente), Datenfluss je Klausel (die
  # Zwischenform für PrologEx.Jit.Codegen) und nichtdeterministische
  # Prädikate.

  alias PrologEx.Jit.Util

  # library(bytes), was der übersetzte Code direkt ruft (b_bytes_*/n; wie
  # in PrologEx.Jit.Parse)
  @bytes_bis ~w(bytes_length bytes_at bytes_bit bytes_next_bit bytes_integer)

  @raise_key :prolog_ex_jit_raise
  @soft_key :prolog_ex_jit_soft
  # wo need/2 gerade prüft (Prädikat, Klausel), für die Meldung
  @where_key :prolog_ex_jit_where
  # klausellokale Eingaben der Klausel, die flow/2 gerade ansieht:
  # {key, i, MapSet von k} (local_args/2, raise_req/2)
  @local_key :prolog_ex_jit_local

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

  def types(scc, parsed, modes, other, num, nd) do
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

    types_fix(scc, parsed, modes, {other, num, nd}, reqs0, outs0, 24)
  end

  defp types_fix(_, _, _, _, _, _, 0), do: Util.no!("Typen kommen zu keinem Fixpunkt")

  defp types_fix(scc, parsed, modes, {other, num, nd} = on, reqs, outs, n) do
    sig = fn ck ->
      if ck in scc do
        ar = parsed[ck].arity

        %{
          modes: Map.new(0..(ar - 1), &{&1, modes[{ck, &1}]}),
          req: for(k <- 0..(ar - 1), modes[{ck, k}] == :in, into: %{}, do: {k, reqs[{ck, k}]}),
          out: for(k <- 0..(ar - 1), modes[{ck, k}] == :out, into: %{}, do: {k, outs[{ck, k}]}),
          nd: nd
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
          ctx = %{key: key, sig: sig, reqs: reqs, num: MapSet.member?(num, key), nd: nd}
          pre = if length(scc) > 1, do: "#{Util.pi(key)}, ", else: ""
          poly = poly_args(parsed[key].clauses, sig.(key).modes)

          {key,
           parsed[key].clauses
           |> Enum.with_index(1)
           |> Enum.map(fn {c, i} ->
             Process.put(@where_key, "#{pre}Klausel #{i}: ")
             locals = local_args(c, poly)
             Process.put(@local_key, {key, i, locals})

             # in dieser Klausel gilt für eine klausellokale Eingabe ihre
             # eigene Anforderung
             creqs =
               Enum.reduce(locals, reqs, fn k, acc ->
                 Map.put(acc, {key, k}, Map.get(reqs, {:local, key, i, k}, :any))
               end)

             try do
               flow(c, %{ctx | reqs: creqs})
             catch
               {:no, r} -> Util.no!("#{pre}Klausel #{i}: #{r}")
             end
           end)}
        end)
      catch
        {:no, _} = e ->
          Process.delete(@raise_key)
          Process.delete(@soft_key)
          Process.delete(@local_key)
          throw(e)
      end

    reqs2 = Process.delete(@raise_key)
    soft = Process.delete(@soft_key)
    Process.delete(@where_key)
    Process.delete(@local_key)

    outs2 =
      for {{key, k}, _} <- outs, into: %{} do
        o =
          irs[key]
          |> Enum.flat_map(fn c -> Map.get(c.otypes, k, []) end)
          |> Enum.map(&out_sig(&1, key, reqs2))
          |> Enum.reduce({:bot, []}, &oj/2)

        {{key, k}, o}
      end

    # Steigen die Anforderungen, fangen die Ausgaben wieder bei :bot an: sie
    # hängen von ihnen ab (ein Element einer Eingabe, die :nlist wird, ist
    # eine Zahl), und die Vereinigung käme von einem zu groben Typ der
    # früheren Runde nicht mehr herunter (partition/4: Ausgaben :list statt
    # :nlist, qsort/3 bekam dann :list, wo :nlist gebraucht wird)
    cond do
      reqs2 != reqs ->
        types_fix(
          scc,
          parsed,
          modes,
          on,
          reqs2,
          Map.new(outs, fn {k, _} -> {k, {:bot, []}} end),
          n - 1
        )

      outs2 != outs ->
        types_fix(scc, parsed, modes, on, reqs2, outs2, n - 1)

      soft ->
        Util.no!(soft)

      true ->
        {reqs, outs, irs}
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
  defp rj(a, b), do: Util.no!("ein Argument müsste #{Util.tname(a)} und #{Util.tname(b)} sein")

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
      do:
        Process.put(
          @soft_key,
          "#{Process.get(@where_key)}#{Util.tname(t)}, wo #{Util.tname(r)} gebraucht wird"
        )

    Enum.each(os, &raise_req(&1, r))
  end

  # Eine klausellokale Eingabe (local_args/2), die eine Zahl sein muss: nur
  # in dieser Klausel ({:local, key, i, k}; dort am Anfang zur Zahl gelesen,
  # flow/2) – nicht beim Eintritt, andere Klauseln zerlegen sie
  # Ein Muster für Listen ([], [H|T]) braucht nur, dass der Wert eine
  # Liste sein kann: gelesen wird erst beim Zerlegen (Runtime.list/1 – ein
  # anderer Term passt nicht, eine ungebundene Variable: aufgeben). Keine
  # Anforderung an die Eingabe – sie schlösse beim Eintritt aus, was die
  # Klausel scheitern ließe (cons(X) :- nonvar(X), X = [_|_] mit einer
  # Variablen: unify) oder was andere Klauseln nehmen
  defp need_type(r, {t, _}) do
    unless sat?(t, r) or t == :any or Process.get(@soft_key),
      do:
        Process.put(
          @soft_key,
          "#{Process.get(@where_key)}#{Util.tname(t)}, wo #{Util.tname(r)} gebraucht wird"
        )
  end

  defp raise_req({:arg, key, k} = o, r) do
    reqs = Process.get(@raise_key)

    case Process.get(@local_key) do
      {^key, i, locals} when r == :num ->
        if MapSet.member?(locals, k) do
          lo = {:local, key, i, k}
          Process.put(@raise_key, Map.put(reqs, lo, rj(Map.get(reqs, lo, :any), r)))
        else
          raise_arg(reqs, o, r)
        end

      _ ->
        raise_arg(reqs, o, r)
    end
  end

  defp raise_req({:elem, key, k}, :num), do: raise_req({:arg, key, k}, :nlist)
  defp raise_req({:elem, _, _}, r), do: Util.no!("ein Listenelement müsste #{Util.tname(r)} sein")

  # ein Argument einer Struktur: gelesen erst beim Zerlegen (match_pat/4)
  defp raise_req({:sub, _, _, _} = o, r) do
    reqs = Process.get(@raise_key)
    Process.put(@raise_key, Map.put(reqs, o, rj(Map.get(reqs, o, :any), r)))
  end

  defp raise_arg(reqs, {:arg, key, k}, r),
    do: Process.put(@raise_key, Map.put(reqs, {key, k}, rj(Map.fetch!(reqs, {key, k}), r)))

  # Klausellokal sind Eingaben, die eine Klausel zerlegt (Struktur, Liste,
  # Atom) und eine andere als Variable nimmt: rechnet diese damit
  # (`poly_add(C1, C2, C) :- C is C1 + C2` hinter Klauseln für
  # `poly(Var, Terms)`), muss das Argument nur dort eine Zahl sein. Beim
  # Eintritt verlangt, schlösse es die anderen Klauseln aus (SICStus-
  # Benchmark poly: jeder Aufruf mit einem Polynom abgewiesen)
  defp poly_args(clauses, modes) do
    for {k, :in} <- modes,
        Enum.any?(clauses, fn {ps, _} -> structural?(Enum.at(ps, k)) end),
        into: MapSet.new(),
        do: k
  end

  defp structural?({:st, _, _}), do: true
  defp structural?({:cons, _, _}), do: true
  defp structural?(:nl), do: true
  defp structural?({:atom, _}), do: true
  defp structural?(_), do: false

  # die klausellokalen Eingaben einer Klausel: polymorph und hier eine
  # Variable
  defp local_args({ps, _}, poly) do
    for k <- poly,
        match?({:var, _}, Enum.at(ps, k)),
        not Util.anon?(Enum.at(ps, k)),
        into: MapSet.new(),
        do: k
  end

  # Typ, den der Wert jetzt hat (nach den Anforderungen dieser Runde)
  defp eff({t, os}, reqs), do: Enum.reduce(os, t, &tj(origin_t(&1, reqs), &2))

  defp origin_t({:arg, key, k}, reqs), do: Map.fetch!(reqs, {key, k})

  defp origin_t({:elem, key, k}, reqs),
    do: if(Map.fetch!(reqs, {key, k}) == :nlist, do: :num, else: :any)

  defp origin_t({:sub, _, _, _} = o, reqs), do: Map.get(reqs, o, :any)

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
        vt = {:bot, [{:arg, ctx.key, k}]}
        {mp, d} = match_pat(a, vt, d, ctx)

        # klausellokal eine Zahl (raise_req/2): hier zur Zahl lesen – keine
        # Zahl: aufgeben, der Interpreter meldet den Fehler
        mp =
          case {mp, Process.get(@local_key)} do
            {{:bind, _}, {_, i, locals}} ->
              if MapSet.member?(locals, k) and
                   Map.get(ctx.reqs, {:local, ctx.key, i, k}) == :num,
                 do: {:num, mp},
                 else: mp

            _ ->
              mp
          end

        {{k, mp}, d}
      end)

    {irs, d} = flow_seq(goals, d, ctx)

    {hout, otypes} =
      for {a, k} <- Enum.with_index(head), modes[k] == :out, reduce: {[], %{}} do
        {hout, ot} ->
          if Util.anon?(a), do: Util.no!("Ausgabe _")
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
      do: Util.no!("#{Util.vname(v)} ist nur in einem Zweig eines If-then-else bestimmt")

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

  # Muster gegen einen bekannten Wert vom Typ vt. Eine Konstante: auf einer
  # gelesenen Zahl mit === ({:const, c}); sonst zur Laufzeit gelesen
  # ({:constrt, c}, PrologEx.Jit.Runtime.eqc/2) – ohne den Wert zur Zahl zu machen:
  # dieselbe Stelle kann in einer anderen Klausel eine Struktur sein
  # (add(0, Y, Y) neben add(s(X), Y, s(Z)))
  defp match_pat(n, vt, d, ctx) when is_number(n) do
    {if(eff(vt, ctx.reqs) == :num, do: {:const, n}, else: {:constrt, n}), d}
  end

  defp match_pat({:atom, _} = a, _vt, d, _ctx), do: {{:constrt, a}, d}

  # Struktur: erst beim Zerlegen gelesen (PrologEx.Jit.Runtime.st/3); ihre
  # Argumente haben die Herkunft {:sub, Herkunft, {f, n}, i} – rechnet der
  # Code mit einem, wird es dort zur Zahl gelesen (wie Listenelemente). Mit
  # dem Funktor: in d(U ^ N, …) :- N1 is N - 1 muss nur das zweite Argument
  # von ^/2 eine Zahl sein, nicht auch V in d(U + V, …) (sonst gab der Code
  # dort auf, sobald V keine Zahl war: deriv)
  defp match_pat({:st, f, ps}, {_, os}, d, ctx) do
    fa = {f, length(ps)}

    {mps, d} =
      ps
      |> Enum.with_index()
      |> Enum.map_reduce(d, fn {p, i}, d ->
        at = if os == [], do: {:any, []}, else: {:bot, for(o <- os, do: {:sub, o, fa, i})}
        {m, d} = match_pat(p, at, d, ctx)
        m = if eff(at, ctx.reqs) == :num and m != :ignore, do: {:num, m}, else: m
        {m, d}
      end)

    {{:st, f, mps}, d}
  end

  defp match_pat({:var, _} = v, vt, d, ctx) do
    cond do
      Util.anon?(v) ->
        {:ignore, d}

      # schon bestimmt: zwei Zahlen mit ===, sonst zur Laufzeit wie die
      # Unifikation (PrologEx.Jit.Runtime.ueq/2: d(X, X, 1) in deriv)
      defd?(d, v) ->
        if eff(vt, ctx.reqs) == :num and eff(d[v], ctx.reqs) == :num,
          do: {{:eq, v}, d},
          else: {{:eqrt, v}, d}

      true ->
        {{:bind, v}, add(d, v, vt)}
    end
  end

  defp match_pat(:nl, vt, d, _ctx) do
    need_type(:list, vt)
    {:nl, d}
  end

  # Elemente einer Liste von Zahlen: erst zur Zahl machen (aus der Eingabe
  # kommen sie ungelesen, PrologEx.Jit.Runtime.num/1)
  defp match_pat({:cons, h, t}, vt, d, ctx) do
    need_type(:list, vt)
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
      do: Util.no!("Gleichheit von Listen")

    need(:num, a)
    need(:num, b)
  end

  # Bau aus bekannten Werten: {bau, typ}. Eine Liste aus Zahlen ist
  # :nlist, sonst :list; ein Rest, der keine Liste ist, macht sie beliebig;
  # ein Rest unbekannten Typs gibt seine Herkunft weiter
  defp build!(n, _d, _ctx) when is_number(n), do: {n, {:num, []}}

  defp build!({:var, _} = v, d, _ctx) do
    if Util.anon?(v) or not defd?(d, v), do: Util.no!("#{Util.vname(v)} ist hier nicht bestimmt")
    {v, if(d == :all, do: {:bot, []}, else: Map.fetch!(d, v))}
  end

  defp build!(:nl, _d, _ctx), do: {:nl, {:nlist, []}}
  defp build!({:atom, _} = a, _d, _ctx), do: {a, {:any, []}}

  defp build!({:st, f, ps}, d, ctx),
    do: {{:st, f, Enum.map(ps, &elem(build!(&1, d, ctx), 0))}, {:any, []}}

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

  defp desc_p({:var, _} = v), do: Util.vname(v)
  defp desc_p(:nl), do: "[]"
  defp desc_p({:cons, _, _}), do: "[...]"
  defp desc_p({:st, f, ps}), do: "#{f}(...)/#{length(ps)}"
  defp desc_p({:atom, a}), do: a
  defp desc_p(n), do: inspect(n)

  defp goal_flow(:cut, d, _), do: {:cut, d}
  defp goal_flow(true, d, _), do: {true, d}
  defp goal_flow(:fail, _d, _), do: {:fail, :all}
  defp goal_flow(:fail0, _d, _), do: {:fail0, :all}

  defp goal_flow({:cmp, op, a, b}, d, _) do
    nums!(Util.vars(a) ++ Util.vars(b), d)
    {{:cmp, op, a, b}, d}
  end

  defp goal_flow({:is, l, r}, d, ctx) do
    nums!(Util.vars(r), d)

    cond do
      is_number(l) ->
        {{:is_eq, l, r}, d}

      Util.anon?(l) ->
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
          Util.no!("#{desc_p(a)} = #{desc_p(b)}: beide Seiten nicht bestimmt")
      end

    {{:u, bt, mp}, d}
  end

  # Aufruf: Eingaben bauen (Anforderungen des Gerufenen), Ausgaben als
  # Muster gegen die Ergebnisse (Typ am Aufrufort eingesetzt)
  # nur die erste Lösung zählt: ein nichtdeterministischer Gerufener gibt
  # seine erste ({:call1, ...}), ein deterministischer wie sonst
  defp goal_flow({:callo, ck, as}, d, ctx) do
    sig = ctx.sig.(ck)

    cond do
      # member(X, L) mit bestimmtem X, erste Lösung: wie memberchk(X, L)
      # (dieselbe Lösung, dieselbe Inferenz; ohne Lösungen aufzuzählen)
      ck == {"member", 2} and Map.get(sig, :builtin, false) and build_ok?(hd(as), d, ctx) ->
        goal_flow({:bi, "memberchk", as, []}, d, ctx)

      Map.get(sig, :nd, false) ->
        {{:call, _, ins, outs}, d} = call_flow(ck, as, d, ctx)
        {{:call1, ck, ins, outs}, d}

      true ->
        call_flow(ck, as, d, ctx)
    end
  end

  defp goal_flow({:call, ck, as}, d, ctx) do
    # nichtdeterministisch übersetzt: nur aus ebensolchen, als letztes Ziel
    # (nd_irs!/3), sonst nur für die erste Lösung ({:callo, ...})
    if Map.get(ctx.sig.(ck), :nd, false) and not ctx.nd,
      do: Util.no!("ruft #{Util.pi(ck)}, das nichtdeterministisch ist")

    call_flow(ck, as, d, ctx)
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
    if dc == :all, do: Util.no!("Bedingung scheitert immer")
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
  # zur Laufzeit (PrologEx.Jit.Runtime.tt/2); integer/1 (float/1, number/1 im Code
  # mit Floats) macht den Wert danach zur Zahl
  defp goal_flow({:tt, t, x}, d, ctx) do
    how =
      cond do
        is_number(x) -> t != "is_list" and PrologEx.type_test(t, x)
        Util.anon?(x) or not defd?(d, x) -> t == "var"
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
        Util.anon?(x) or not defd?(d, x) -> false
        how in [:rt, :refine] -> :rt
        true -> true
      end

    {{:idx, ir, bound}, d2}
  end

  # ==, \==: beide Seiten bestimmt; Zahlen mit ===, sonst zur Laufzeit
  # (PrologEx.Jit.Runtime.teq/2, wie der Interpreter)
  defp goal_flow({:teq, pos, a, b}, d, ctx) do
    {ba, ta} = build!(a, d, ctx)
    {bb, tb} = build!(b, d, ctx)
    how = if eff(ta, ctx.reqs) == :num and eff(tb, ctx.reqs) == :num, do: :num, else: :rt
    {{:teq, pos, ba, bb, how}, d}
  end

  # @<, @>, @=<, @>=: zur Laufzeit (PrologEx.Jit.Runtime.tord/3); zwei Zahlen
  # vergleicht die Standardordnung wie die Arithmetik, nur 1 und 1.0 nicht
  # gleich – auch das zur Laufzeit
  defp goal_flow({:tord, op, a, b}, d, ctx) do
    {ba, _} = build!(a, d, ctx)
    {bb, _} = build!(b, d, ctx)
    {{:tord, op, ba, bb}, d}
  end

  # arg/3, functor/3, =../2, compare/3: Eingaben bestimmt (zerlegt wird nur;
  # eine ungebundene Eingabe – functor/3 zum Bauen – oder ein Fehler: zur
  # Laufzeit aufgeben, der Interpreter rechnet), Ergebnisse als Muster
  # gegen Werte ihres Typs
  defp goal_flow({:bi, name, ins, outs}, d, ctx) do
    bins = Enum.map(ins, fn a -> elem(build!(a, d, ctx), 0) end)

    # compare/3 auf eine schon bestimmte Ordnung: der Interpreter prüft
    # deren Typ (Fehler), der Code verglich nur – ebenso das Ergebnis von
    # length/2, sort/2, msort/2 (type_error, wo der Code nur verglich)
    with true <- name != "append",
         [{:var, _} = o] <- outs,
         true <- not Util.anon?(o) and defd?(d, o),
         do: Util.no!("#{name} mit bestimmtem Ergebnis")

    # length/2: höchstens eine Zahl als Ergebnis; sort/2, msort/2: nur
    # eine frische Variable (sonst prüft der Interpreter die Form)
    case {name, outs} do
      {"length", [{:var, _}]} ->
        :ok

      {"length", [n]} when is_number(n) ->
        :ok

      {n, [{:var, _}]} when n in ["sort", "msort"] ->
        :ok

      {n, [o]} when n in ["length", "sort", "msort"] ->
        Util.no!("#{n}/2 mit Ergebnis #{desc_p(o)}")

      _ ->
        :ok
    end

    {mps, d} =
      outs
      |> Enum.zip(bi_types(name))
      |> Enum.map_reduce(d, fn {p, t}, d -> match_pat(p, {t, []}, d, ctx) end)

    {{:bi, name, bins, mps}, d}
  end

  defp call_flow(ck, as, d, ctx) do
    sig = ctx.sig.(ck)

    indexed = Enum.with_index(as)

    # Ausgaben eines übersetzten Prädikats: nur frische Variablen, je eine.
    # Der Code rechnet die Ausgabe und vergleicht erst danach; der
    # Interpreter prüft sie, wo sie gebunden wird – schon im Kopf, und
    # scheitert die Klausel dort, nimmt er die nächste: tab(a, 1) :- !.
    # tab(_, 2). gerufen als tab(a, 2) gelingt dort, im Code schlüge der
    # Vergleich 1 = 2 fehl. Ausgenommen: eingebaute (between/3 prüft
    # selbst) und nichtdeterministisch übersetzte ohne Schnitt – deren
    # Lösungen der Reihe nach gefiltert sind dieselben (mem(K-V, L)).
    if not (Map.get(sig, :builtin, false) or
              (Map.get(sig, :nd, false) and not Map.get(sig, :cut, true))) do
      os = for {a, k} <- indexed, sig.modes[k] == :out, not Util.anon?(a), do: a

      for a <- os,
          not match?({:var, _}, a) or defd?(d, a),
          do: Util.no!("ruft #{Util.pi(ck)} mit bestimmter Ausgabe #{out_desc(a)}")

      if length(Enum.uniq(os)) != length(os),
        do: Util.no!("ruft #{Util.pi(ck)} mit derselben Variablen an zwei Ausgaben")
    end

    ins =
      for {a, k} <- indexed, sig.modes[k] == :in do
        {bt, vt} = build!(a, d, ctx)
        {k, arg_check(sig.req[k], bt, vt, ctx), vt}
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

  # Ein Argument für eine Eingabe mit Anforderung r. Eine Liste verlangt
  # beim Eintritt nur: keine ungebundene Variable (die Elemente liest der
  # Gerufene selbst zur Zahl, PrologEx.Jit.Runtime.list/1, num/1). Hat der
  # Wert keine Herkunft, deren Anforderung steigen könnte (aus arg/3, einer
  # Struktur, einer Ausgabe), prüft das der Code hier ({:nv, Bau},
  # Runtime.nv/1: sonst aufgeben) – statt das Prädikat nicht zu übersetzen
  # (size_args/5 im SICStus-Benchmark unify: `arg(I, T, A), size(A)`)
  defp arg_check(r, bt, {_, []} = vt, ctx) when r in [:list, :nlist] do
    case eff(vt, ctx.reqs) do
      t when t in [:list, :nlist] -> bt
      :any -> {:nv, bt}
      _ -> need(r, vt) && bt
    end
  end

  defp arg_check(r, bt, vt, _ctx) do
    need(r, vt)
    bt
  end

  # ein Schnitt irgendwo im Rumpf (auch in Zweigen)
  def has_cut?(:cut), do: true
  def has_cut?(gs) when is_list(gs), do: Enum.any?(gs, &has_cut?/1)
  def has_cut?({:ite, c, t, e}), do: has_cut?(c) or has_cut?(t) or has_cut?(e)
  def has_cut?({:not, g}), do: has_cut?(g)
  def has_cut?(_), do: false

  defp out_desc({:var, _} = v), do: Util.vname(v)
  defp out_desc(p) when is_tuple(p) or p == :nl, do: desc_p(p)
  defp out_desc(p), do: inspect(p)

  defp bi_types("arg"), do: [:any]
  defp bi_types("functor"), do: [:any, :num]
  defp bi_types("univ"), do: [:list]
  defp bi_types("compare"), do: [:any]
  defp bi_types("append"), do: [:any]
  defp bi_types("bit_is_set"), do: []
  defp bi_types("memberchk"), do: []
  defp bi_types("length"), do: [:num]
  defp bi_types(s) when s in ["sort", "msort"], do: [:list]
  defp bi_types(s) when s in @bytes_bis, do: [:num]
  defp bi_types("lfsr_next"), do: [:num, :any]
  defp bi_types("lfsr_done"), do: []

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
      if not defd?(d, v), do: Util.no!("#{Util.vname(v)} ist hier nicht bestimmt")
      need(:num, Map.get(d, v, {:bot, []}))
    end
  end

  # --- Nichtdeterministisch ("Blatt") ---------------------------------------
  #
  # Klauseln, die sich nicht ausschließen: jede Klausel ein Rumpf wie sonst
  # (deterministisch), höchstens als letztes Ziel ein Aufruf eines
  # nichtdeterministischen Prädikats (auch sich selbst) – {:tail_nd, ...}:
  # dessen Lösungen sind (über die Ausgabemuster) die der Klausel. Ein
  # Schnitt nur auf oberster Ebene des Rumpfs (danach keine weiteren
  # Klauseln); nichtdeterministische Aufrufe sonst nirgends.

  #
  # Ein rekursiver letzter Aufruf nur ohne Hülle: in der letzten Klausel
  # (oder nach einem Schnitt) und mit denselben Ausgaben wie die Klausel –
  # sonst liefe jede Lösung aus Tiefe k durch k Hüllen (select/3 baut
  # [H|R] auf jeder Stufe neu: über 3000 Elemente 45-mal langsamer als der
  # Interpreter, der die Zellen einmal baut und nur bindet)
  def nd_irs!(cs, scc, other) do
    nd? = fn ck -> ck in scc or Map.get(other.(ck), :nd, false) end
    n = length(cs)

    cs
    |> Enum.with_index(1)
    |> Enum.map(fn {c, i} ->
      try do
        goals = c.ir.goals

        if Enum.any?(goals, &(match?({:ite, _, _, _, _, _}, &1) and Util.cut_in?([&1]))),
          do: Util.no!("Schnitt in einem Zweig")

        {pre, last} =
          case Enum.reverse(goals) do
            [{:call, ck, ins, outs} | r] ->
              if nd?.(ck), do: {Enum.reverse(r), {:tail_nd, ck, ins, outs}}, else: {goals, nil}

            _ ->
              {goals, nil}
          end

        if nd_call_in?(pre, nd?),
          do: Util.no!("nichtdeterministischer Aufruf nicht als letztes Ziel")

        # member/2, between/3: ihre weiteren Lösungen liefert der
        # Interpreter billiger (lazy Liste) als ein Choice Point des Codes
        with {:tail_nd, ck, _, _} <- last,
             false <- ck in scc,
             true <- Map.get(other.(ck), :builtin, false),
             do: Util.no!("#{Util.pi(ck)} als letztes Ziel: eingebaut, im Interpreter schneller")

        with {:tail_nd, ck, _, outs} <- last, true <- ck in scc do
          if not (i == n or :cut in pre), do: Util.no!("rekursiver Aufruf vor weiteren Klauseln")
          # (kein schwächerer Modus danach: rule1([H|X], [H|Y]) :- rule1(X, Y)
          # mit beiden Stellen als Eingabe passte, nützte aber keinem Aufruf)
          if not Util.same_outs?(outs, c.ir.hout),
            do: throw({:nd_stop, "Klausel #{i}: rekursiver Aufruf mit anderen Ausgaben"})
        end

        %{c | ir: %{c.ir | goals: if(last, do: pre ++ [last], else: pre)}}
      catch
        {:no, r} -> Util.no!("Klausel #{i}: #{r}")
      end
    end)
  end

  # die Ausgaben des Aufrufs sind die der Klausel (dieselben Variablen,
  # in derselben Reihenfolge)
  defp nd_call_in?(gs, nd?) do
    Enum.any?(gs, fn
      {:call, ck, _, _} -> nd?.(ck)
      {:ite, c, _, t, e, _} -> nd_call_in?(c, nd?) or nd_call_in?(t, nd?) or nd_call_in?(e, nd?)
      {:not, g} -> nd_call_in?(g, nd?)
      _ -> false
    end)
  end
end
