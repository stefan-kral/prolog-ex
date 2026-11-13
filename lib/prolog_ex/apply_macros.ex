defmodule PrologEx.ApplyMacros do
  @moduledoc """
  Metaprädikate aus `library(apply)` mit beim Laden bekannter Closure als
  eigene Hilfsprädikate (wie SWIs `library(apply_macros)`): aus

      p(L, M) :- maplist(succ, L, M).

  wird

      p(L, M) :- '$apply_maplist_3_…'(L, M).
      '$apply_maplist_3_…'([], []).
      '$apply_maplist_3_…'([X|Xs], [Y|Ys]) :- succ(X, Y), '$apply_maplist_3_…'(Xs, Ys).

  Kein `call/N` mehr zur Laufzeit – schneller im Interpreter, und der JIT
  übersetzt das Hilfsprädikat (und damit den Rufer) wie jedes andere.

    * `maplist/2..8`, `foldl/4..6`, `include/3`, `exclude/3`,
      `partition/4` – wenn sie im Modul die aus `library(apply)` sind (nicht
      selbst definiert, auch nicht weiter vorn in derselben Datei).
    * Die Closure: ein Atom oder eine Struktur, auch `M:G` – ihre Variablen
      werden durchgereicht (dieselben bei jedem Aufruf, wie `call/N`).
    * Ein Lambda aus `library(lambda)` (`\\X^…^Rumpf`, `Free+\\X^…^Rumpf`)
      verschwindet ganz: sein Rumpf steht im Hilfsprädikat, die Parameter
      im Kopf. Nur wenn das dieselbe Bedeutung hat: jede Variable des
      Lambdas, die nicht in `Free` steht, kommt in der Klausel nur im
      Lambda vor (das Lambda kopiert bei jedem Aufruf – eine solche
      Variable ist ohnehin jedes Mal frisch); und es hat nicht mehr
      Parameter als Argumente. Sonst bleibt es ein Aufruf des Lambdas.
    * Expandiert wird im Rumpf und in `,`, `;`, `->`, `*->`, `\\+`.

  Abschalten: `set_prolog_flag(apply_macros, false)` vor dem Laden.
  Hilfsprädikate gleicher Art und gleicher Closure (bis auf Variablennamen)
  teilen sich ein Prädikat.
  """
  import PrologEx, only: [a: 1, mk: 2]

  @metas %{
    {"maplist", 2} => :maplist,
    {"maplist", 3} => :maplist,
    {"maplist", 4} => :maplist,
    {"maplist", 5} => :maplist,
    {"maplist", 6} => :maplist,
    {"maplist", 7} => :maplist,
    {"maplist", 8} => :maplist,
    {"foldl", 4} => :foldl,
    {"foldl", 5} => :foldl,
    {"foldl", 6} => :foldl,
    {"include", 3} => :include,
    {"exclude", 3} => :exclude,
    {"partition", 4} => :partition
  }

  @doc """
  Rumpf einer Klausel (Kopf und Rumpf unmarkiert) expandieren: `{rumpf,
  [{name, arity, klauseln}]}` – die Hilfsprädikate in module. `local?`:
  ist name/arity in module (weiter vorn) definiert?
  """
  def expand(head, body, db, module, local?) do
    if PrologEx.Flags.get("apply_macros") == {:atom, "false"} do
      {body, []}
    else
      {head, body} = {PrologEx.unmark(head), PrologEx.unmark(body)}
      ctx = %{db: db, module: module, local?: local?, clause: mk(":-", [head, body])}
      walk(body, ctx, [])
    end
  end

  defp walk({:struct, op, [x, y]}, ctx, acc) when op in [",", ";", "->", "*->"] do
    {x, acc} = walk(x, ctx, acc)
    {y, acc} = walk(y, ctx, acc)
    {{:struct, op, [x, y]}, acc}
  end

  defp walk({:struct, "\\+", [x]}, ctx, acc) do
    {x, acc} = walk(x, ctx, acc)
    {{:struct, "\\+", [x]}, acc}
  end

  defp walk({:struct, name, args} = g, ctx, acc) do
    with kind when kind != nil <- Map.get(@metas, {name, length(args)}),
         true <- library?(ctx, name, length(args)),
         {:ok, call, aux} <- macro(kind, args, ctx) do
      {call, [aux | acc]}
    else
      _ -> {g, acc}
    end
  end

  defp walk(g, _ctx, acc), do: {g, acc}

  # das Metaprädikat ist im Modul das aus library(apply)
  defp library?(ctx, name, ar) do
    not ctx.local?.(name, ar) and
      match?({:builtin, "apply", _}, PrologEx.locate(ctx.db, ctx.module, name, ar))
  end

  # --- die Closure ---------------------------------------------------------

  # {:ok, cvars, fun} – fun.(elemente) gibt {kopf-muster der elemente,
  # ziel}; oder :no
  defp closure(c, nargs, ctx) do
    case c do
      {:var, _} ->
        :no

      {:struct, "\\", [lam]} ->
        lambda(c, [], lam, nargs, ctx) || plain(c)

      {:struct, "+\\", [free, lam]} ->
        lambda(c, vars(free), lam, nargs, ctx) || plain(c)

      _ ->
        plain(c)
    end
  end

  # Atom, Struktur, M:G – die Elemente als zusätzliche Argumente
  defp plain(c) do
    case callable_skel(c) do
      true ->
        {:ok, vars(c), fn es -> {es, add_args(c, es)} end}

      false ->
        :no
    end
  end

  defp callable_skel({:atom, _}), do: true
  defp callable_skel({:struct, ":", [{:atom, _}, g]}), do: callable_skel(g)
  defp callable_skel({:struct, _, _}), do: true
  defp callable_skel(_), do: false

  defp add_args({:atom, f}, []), do: {:atom, f}
  defp add_args({:atom, f}, es), do: {:struct, f, es}
  defp add_args({:struct, ":", [m, g]}, es), do: {:struct, ":", [m, add_args(g, es)]}
  defp add_args({:struct, f, as}, es), do: {:struct, f, as ++ es}
  defp add_args({:var, _} = v, []), do: mk("call", [v])
  defp add_args({:var, _} = v, es), do: mk("call", [v | es])

  # \X1^…^Rumpf (free: die Variablen von Free): inline, wenn library(lambda)
  # sichtbar ist, alle übrigen Variablen nur im Lambda vorkommen und die
  # Argumente für alle Parameter reichen
  defp lambda(whole, free, lam, nargs, ctx) do
    {params, body} = params(lam, nargs, [])
    free_set = MapSet.new(free)

    cond do
      not lambda_lib?(ctx, whole) ->
        nil

      match?({:struct, "^", [_, _]}, body) and length(params) == nargs ->
        # mehr Parameter als Argumente: der Aufruf meldet das (Fehler)
        nil

      not Enum.all?(vars(lam), &(&1 in free_set or local?(&1, whole, ctx.clause))) ->
        nil

      true ->
        {:ok, free,
         fn es ->
           {_, rest} = Enum.split(es, length(params))
           {params ++ rest, add_args(body, rest)}
         end}
    end
  end

  defp params({:struct, "^", [p, r]}, n, acc) when n > 0, do: params(r, n - 1, [p | acc])
  defp params(body, _n, acc), do: {Enum.reverse(acc), body}

  defp lambda_lib?(ctx, {:struct, f, args}) do
    case PrologEx.locate(ctx.db, ctx.module, f, length(args) + 1) do
      {:builtin, "lambda", _} -> true
      {:db, "lambda_pl", _} -> true
      _ -> false
    end
  end

  # kommt v in der Klausel nur innerhalb von t vor?
  defp local?(v, t, clause), do: count(v, clause) == count(v, t)

  defp count(v, v), do: 1
  defp count(v, {:struct, _, as}), do: Enum.reduce(as, 0, &(count(v, &1) + &2))
  defp count(v, {:gstruct, _, as}), do: Enum.reduce(as, 0, &(count(v, &1) + &2))
  defp count(v, [h | t]), do: count(v, h) + count(v, t)
  defp count(_, _), do: 0

  # Variablen in Reihenfolge des ersten Auftretens
  defp vars(t), do: t |> vars([]) |> Enum.reverse()

  defp vars({:var, _} = v, acc), do: if(v in acc, do: acc, else: [v | acc])
  defp vars({:struct, _, as}, acc), do: Enum.reduce(as, acc, &vars/2)
  defp vars([h | t], acc), do: vars(t, vars(h, acc))
  defp vars(_, acc), do: acc

  # --- die Hilfsprädikate ----------------------------------------------------

  defp macro(kind, [c | rest], ctx) do
    nl =
      case kind do
        :maplist -> length(rest)
        :foldl -> length(rest) - 2
        _ -> 1
      end

    with {:ok, cv, f} <- closure(c, closure_arity(kind, nl), ctx) do
      {lists, extra} = Enum.split(rest, nl)
      name = aux_name(kind, length(rest) + 1, c, ctx.module)
      clauses = clauses(kind, name, nl, cv, f)
      arity = nl + length(cv) + length(extra)
      {:ok, mk(name, lists ++ cv ++ extra), {name, arity, clauses}}
    else
      _ -> :no
    end
  end

  defp closure_arity(:foldl, nl), do: nl + 2
  defp closure_arity(:maplist, nl), do: nl
  defp closure_arity(_, _), do: 1

  defp fresh(base), do: {:var, {base, System.unique_integer([:positive])}}

  defp clauses(:maplist, name, nl, cv, f) do
    es = for i <- 1..nl, do: fresh("E#{i}")
    ts = for i <- 1..nl, do: fresh("T#{i}")
    {pats, goal} = f.(es)

    [
      {mk(name, List.duplicate([], nl) ++ cv), a("true")},
      {mk(name, Enum.zip_with(pats, ts, &[&1 | &2]) ++ cv), mk(",", [goal, mk(name, ts ++ cv)])}
    ]
  end

  defp clauses(:foldl, name, nl, cv, f) do
    es = for i <- 1..nl, do: fresh("E#{i}")
    ts = for i <- 1..nl, do: fresh("T#{i}")
    [v0, v1, v] = [fresh("V0"), fresh("V1"), fresh("V")]
    {pats, goal} = f.(es ++ [v0, v1])
    {epats, _} = Enum.split(pats, nl)
    # Muster für V0/V1 (ein Lambda mit Parametern dort): im Kopf bzw. Ziel
    [p0, p1] = Enum.drop(pats, nl)

    [
      {mk(name, List.duplicate([], nl) ++ cv ++ [v, v]), a("true")},
      {mk(name, Enum.zip_with(epats, ts, &[&1 | &2]) ++ cv ++ [p0, v]),
       mk(",", [goal, mk(name, ts ++ cv ++ [p1, v])])}
    ]
  end

  defp clauses(kind, name, 1, cv, f) when kind in [:include, :exclude] do
    [t, i, i1] = [fresh("T"), fresh("I"), fresh("I1")]
    {e, test} = elem_test(f)
    {yes, no} = {mk("=", [i, [e | i1]]), mk("=", [i, i1])}
    {th, el} = if kind == :include, do: {yes, no}, else: {no, yes}

    [
      {mk(name, [[]] ++ cv ++ [[]]), a("true")},
      {mk(name, [[e | t]] ++ cv ++ [i]),
       mk(",", [mk(";", [mk("->", [test, th]), el]), mk(name, [t] ++ cv ++ [i1])])}
    ]
  end

  defp clauses(:partition, name, 1, cv, f) do
    [t, i, i1, x, x1] = Enum.map(~w(T I I1 X X1), &fresh/1)
    {e, test} = elem_test(f)
    th = mk(",", [mk("=", [i, [e | i1]]), mk("=", [x, x1])])
    el = mk(",", [mk("=", [i, i1]), mk("=", [x, [e | x1]])])

    [
      {mk(name, [[]] ++ cv ++ [[], []]), a("true")},
      {mk(name, [[e | t]] ++ cv ++ [i, x]),
       mk(",", [mk(";", [mk("->", [test, th]), el]), mk(name, [t] ++ cv ++ [i1, x1])])}
    ]
  end

  # das Element (kommt auch in die Ergebnisliste) und der Test: ein
  # Lambda-Parameter, der eine Variable ist, steht für das Element selbst;
  # ein anderes Muster wird mit ihm unifiziert, wie beim Aufruf des Lambdas
  defp elem_test(f) do
    e = fresh("E")

    case f.([e]) do
      {[^e], goal} -> {e, goal}
      {[{:var, _} = p], goal} -> {p, goal}
      {[p], goal} -> {e, mk(",", [mk("=", [p, e]), goal])}
    end
  end

  # gleiche Art, gleiche Closure bis auf Variablennamen, gleiches Modul:
  # dasselbe Hilfsprädikat
  defp aux_name(kind, ar, c, module) do
    h = :erlang.phash2({kind, ar, module, skel(c, %{}) |> elem(0)}, 4_294_967_296)
    "$apply_#{kind}_#{ar}_#{Integer.to_string(h, 36)}"
  end

  defp skel({:var, _} = v, m) do
    case m do
      %{^v => i} -> {{:v, i}, m}
      _ -> {{:v, map_size(m)}, Map.put(m, v, map_size(m))}
    end
  end

  defp skel({:struct, f, as}, m) do
    {as, m} = Enum.map_reduce(as, m, &skel/2)
    {{:s, f, as}, m}
  end

  defp skel([h | t], m) do
    {h, m} = skel(h, m)
    {t, m} = skel(t, m)
    {[h | t], m}
  end

  defp skel(x, m), do: {x, m}
end
