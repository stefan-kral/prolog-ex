defmodule PrologEx.Compiler do
  @moduledoc """
  Übersetzt Klauseln beim Laden in eine WAM-artige Zwischendarstellung.

  ## Variablenklassifikation

  Jede benannte Klauselvariable wird anhand ihres ersten Vorkommens
  (Tiefensuche, links nach rechts – dieselbe Reihenfolge wie beim Matchen)
  eingeordnet:

    * kommt sie nur einmal in der ganzen Klausel vor (oder heißt `_`) und
      steht im Kopf  -> `:void`, wird komplett ignoriert
    * erstes Vorkommen im Kopf -> bekommt einen Slot im Environment-Tupel;
      das erste Vorkommen ist `{:first, slot}`, alle weiteren `{:val, slot}`
    * erstes Vorkommen im Rumpf -> "frische" Variable `{:t_fresh, j}`;
      wird erst beim Instanziieren des Rumpfs als `{:var, base + j}` angelegt

  `{:first, slot}` speichert den Argumentterm einfach im Slot – keine
  Umbenennung, kein Eintrag in der Substitution.

  ## Kopf-Muster (Read-/Write-Modus)

      :void                       passt auf alles
      {:first, slot}              Slot := Argument
      {:val, slot}                allgemeine Unifikation mit Slot-Inhalt
      {:const, c}                 atomarer Wert
      {:ground, t}                variablenfreier zusammengesetzter Term
      {:list, ph, pt}             [H | T]
      {:struct, f, n, [p, ...]}   f(...) mit Stelligkeit n

  Trifft ein `:list`/`:struct`-Muster auf eine ungebundene Variable, wird der
  Term im Write-Modus gebaut (`PrologEx.build/3`) und an die Variable
  gebunden; variablenfreie Teile werden dabei als Literal geteilt.

  ## Rumpf-Templates

      {:t_slot, slot} | {:t_fresh, j} | {:t_lit, term}
      {:t_list, h, t} | {:t_struct, f, [args]}

  Arithmetik: ein Ziel `X is Ausdruck` oder ein Vergleich (`=:=`, `<`, ...)
  auf oberster Ebene des Rumpfs wird zu

      {:t_arith, :is, out_template, code, [leaf_templates]}
      {:t_arith, :cmp, nil, {:cmp, op, code_a, code_b}, [leaf_templates]}

  mit einem Codebaum für den Ausdruck (siehe `PrologEx.Arith.run/3`); zur
  Laufzeit wird dann nur das Ziel `'$is'(X, Code, Blätter...)` bzw.
  `'$cmp'(Code, Blätter...)` gebaut, nicht der Ausdruck. Teilausdrücke
  ohne Blätter werden beim Übersetzen ausgerechnet, wenn das fehlerfrei geht
  und sie nichts Unreines (`random`, `cputime`, ...) enthalten.

  Der Rumpf wird erst instanziiert, wenn der Kopf gepasst hat.
  Konjunktionen auf oberster Ebene sind bereits zu einer Zielliste
  abgeflacht, `true` entfällt.

  Eine kompilierte Klausel ist
  `{:clause, index_key, nslots, head_patterns, nfresh, body_templates}`.

  Variablenfreie Teilterme (`:ground`, `:t_lit`) werden vollständig als
  gstruct/glist markiert; Write-Modus und Instanziierung markieren über
  `PrologEx.mk_struct/2` und `PrologEx.cons/2`.
  """

  def compile_clause({head, body}) do
    counts = count_vars(body, count_vars(head, %{}))
    st = %{slots: %{}, fresh: %{}, counts: counts}

    {pats, st} = Enum.map_reduce(args_of(head), st, &head_pat/2)
    {tmpls, st} = Enum.map_reduce(flatten_conj(body), st, &goal_tmpl/2)

    {:clause, index_key_of(pats), map_size(st.slots), pats, map_size(st.fresh), tmpls}
  end

  @doc "Funktor/Stelligkeit eines aufrufbaren Terms"
  def key({:struct, f, args}), do: {f, length(args)}
  def key({:gstruct, f, args}), do: {f, length(args)}
  def key({:glist, _}), do: {".", 2}
  def key({:atom, f}), do: {f, 0}
  def key([]), do: {"[]", 0}
  def key([_ | _]), do: {".", 2}
  def key(t), do: PrologEx.Error.type!("callable", t)

  def args_of({:struct, _, args}), do: args
  def args_of({:gstruct, _, args}), do: args
  def args_of([h | t]), do: [h, t]

  def args_of({:glist, _} = l) do
    {:cons, h, t} = PrologEx.uncons(l)
    [h, t]
  end

  def args_of(_), do: []

  # ---------------------------------------------------------------------

  defp count_vars({:var, "_"}, c), do: c
  defp count_vars({:var, n}, c), do: Map.update(c, n, 1, &(&1 + 1))
  defp count_vars({:struct, _, args}, c), do: Enum.reduce(args, c, &count_vars/2)
  defp count_vars([h | t], c), do: count_vars(t, count_vars(h, c))
  defp count_vars(_, c), do: c

  defp flatten_conj({tag, ",", [a, b]}) when tag in [:struct, :gstruct],
    do: flatten_conj(a) ++ flatten_conj(b)

  defp flatten_conj({:atom, "true"}), do: []
  defp flatten_conj(g), do: [g]

  def ground?({:var, _}), do: false
  def ground?({:struct, _, args}), do: Enum.all?(args, &ground?/1)
  def ground?([h | t]), do: ground?(h) and ground?(t)
  def ground?(_), do: true

  defp compound?([_ | _]), do: true
  defp compound?({:struct, _, _}), do: true
  defp compound?({:gstruct, _, _}), do: true
  defp compound?({:glist, _}), do: true
  defp compound?(_), do: false

  # --- Kopf -------------------------------------------------------------

  defp head_pat({:var, "_"}, st), do: {:void, st}

  defp head_pat({:var, n}, st) do
    case Map.fetch(st.slots, n) do
      {:ok, i} ->
        {{:val, i}, st}

      :error ->
        if st.counts[n] == 1 do
          {:void, st}
        else
          i = map_size(st.slots)
          {{:first, i}, %{st | slots: Map.put(st.slots, n, i)}}
        end
    end
  end

  defp head_pat(t, st) do
    cond do
      not compound?(t) -> {{:const, t}, st}
      ground?(t) -> {{:ground, PrologEx.mark(t)}, st}
      true -> compound_pat(t, st)
    end
  end

  defp compound_pat([h | t], st) do
    {ph, st} = head_pat(h, st)
    {pt, st} = head_pat(t, st)
    {{:list, ph, pt}, st}
  end

  defp compound_pat({:struct, f, args}, st) do
    {ps, st} = Enum.map_reduce(args, st, &head_pat/2)
    {{:struct, f, length(args), ps}, st}
  end

  defp index_key_of([]), do: :any
  defp index_key_of([:void | _]), do: :any
  defp index_key_of([{:first, _} | _]), do: :any
  defp index_key_of([{:val, _} | _]), do: :any
  defp index_key_of([{:const, c} | _]), do: PrologEx.index_key(c)
  defp index_key_of([{:ground, t} | _]), do: PrologEx.index_key(t)
  defp index_key_of([{:list, _, _} | _]), do: {".", 2}
  defp index_key_of([{:struct, f, n, _} | _]), do: {f, n}

  # --- Rumpf ------------------------------------------------------------

  @cmp_ops ~w(=:= =\\= < > =< >=)

  # Ziel auf oberster Ebene: Arithmetik übersetzen, sonst Template
  defp goal_tmpl({:struct, "is", [out, expr]} = g, st) do
    {code, {leaves, st1}} = acode(expr, {[], st})

    if trivial?(code) do
      body_tmpl(g, st)
    else
      {out_t, st1} = body_tmpl(out, st1)
      {{:t_arith, :is, out_t, fold(code), Enum.reverse(leaves)}, st1}
    end
  end

  defp goal_tmpl({:struct, op, [a, b]} = g, st) when op in @cmp_ops do
    {ca, acc} = acode(a, {[], st})
    {cb, {leaves, st1}} = acode(b, acc)

    # keine Seite mit Operator: wie bisher (nichts zu gewinnen)
    if trivial?(ca) and trivial?(cb),
      do: body_tmpl(g, st),
      else: {{:t_arith, :cmp, nil, fold({:cmp, op, ca, cb}), Enum.reverse(leaves)}, st1}
  end

  defp goal_tmpl(g, st), do: body_tmpl(g, st)

  defp trivial?({:leaf, _}), do: true
  defp trivial?({:num, _}), do: true
  defp trivial?(_), do: false

  # Codebaum eines Ausdrucks; acc = {Blatt-Templates umgekehrt, st}
  defp acode(n, acc) when is_number(n), do: {{:num, n}, acc}
  # markierte (ground) Teilterme, z. B. aus assertz
  defp acode({:gstruct, f, args}, acc), do: acode({:struct, f, args}, acc)

  defp acode({:struct, op, [a, b]} = t, acc) do
    if PrologEx.Arith.op?(op, 2) do
      {ca, acc} = acode(a, acc)
      {cb, acc} = acode(b, acc)
      {{:op2, op, ca, cb}, acc}
    else
      leaf(t, acc)
    end
  end

  defp acode({:struct, op, [a]} = t, acc) do
    if PrologEx.Arith.op?(op, 1) do
      {ca, acc} = acode(a, acc)
      {{:op1, op, ca}, acc}
    else
      leaf(t, acc)
    end
  end

  defp acode({:atom, name} = t, acc) do
    if PrologEx.Arith.op?(name, 0), do: {{:op0, name}, acc}, else: leaf(t, acc)
  end

  defp acode(t, acc), do: leaf(t, acc)

  # Blatt: zur Laufzeit mit eval/2 (Variable, unbekannter Funktor, Liste, ...)
  defp leaf(t, {leaves, st}) do
    {tmpl, st} = body_tmpl(t, st)
    {{:leaf, length(leaves)}, {[tmpl | leaves], st}}
  end

  # Teilbäume ohne Blätter ausrechnen, wenn das fehlerfrei geht
  defp fold({:op2, op, a, b}), do: try_fold({:op2, op, fold(a), fold(b)})
  defp fold({:op1, op, a}), do: try_fold({:op1, op, fold(a)})
  defp fold({:op0, _} = c), do: try_fold(c)
  defp fold({:cmp, op, a, b}), do: {:cmp, op, fold(a), fold(b)}
  defp fold(c), do: c

  defp try_fold(code) do
    if pure_const?(code) do
      try do
        {:num, PrologEx.Arith.run(code, {}, %{})}
      rescue
        _ -> code
      end
    else
      code
    end
  end

  defp pure_const?({:num, _}), do: true
  defp pure_const?({:op0, name}), do: not PrologEx.Arith.impure?(name)
  defp pure_const?({:op1, op, a}), do: not PrologEx.Arith.impure?(op) and pure_const?(a)
  # Potenzen und Schieben nur mit kleinem rechten Operanden (sonst kann
  # schon das Laden lange dauern – die Klausel läuft vielleicht nie)
  defp pure_const?({:op2, op, a, {:num, n}}) when op in ["**", "^", "<<"],
    do: abs(n) <= 64 and pure_const?(a)

  defp pure_const?({:op2, op, _a, _b}) when op in ["**", "^", "<<"], do: false
  defp pure_const?({:op2, _, a, b}), do: pure_const?(a) and pure_const?(b)
  defp pure_const?(_), do: false

  defp body_tmpl({:var, "_"}, st), do: new_fresh({:anon, map_size(st.fresh)}, st)

  defp body_tmpl({:var, n}, st) do
    case Map.fetch(st.slots, n) do
      {:ok, i} ->
        {{:t_slot, i}, st}

      :error ->
        case Map.fetch(st.fresh, n) do
          {:ok, j} -> {{:t_fresh, j}, st}
          :error -> new_fresh(n, st)
        end
    end
  end

  defp body_tmpl(t, st) do
    cond do
      not compound?(t) or ground?(t) -> {{:t_lit, PrologEx.mark(t)}, st}
      true -> compound_tmpl(t, st)
    end
  end

  defp compound_tmpl([h | t], st) do
    {th, st} = body_tmpl(h, st)
    {tt, st} = body_tmpl(t, st)
    {{:t_list, th, tt}, st}
  end

  defp compound_tmpl({:struct, f, args}, st) do
    {ts, st} = Enum.map_reduce(args, st, &body_tmpl/2)
    {{:t_struct, f, ts}, st}
  end

  defp new_fresh(name, st) do
    j = map_size(st.fresh)
    {{:t_fresh, j}, %{st | fresh: Map.put(st.fresh, name, j)}}
  end
end
