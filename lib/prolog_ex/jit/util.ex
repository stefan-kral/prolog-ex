defmodule PrologEx.Jit.Util do
  @moduledoc false
  # Hilfen, die mehrere Teile von PrologEx.Jit brauchen

  # Sind die Ausgaben des letzten Aufrufs die der Klausel (verschiedene
  # Variablen, in dieser Reihenfolge)?
  def same_outs?(outs, hout) do
    length(outs) == length(hout) and length(Enum.uniq(outs)) == length(outs) and
      Enum.all?(Enum.zip(outs, hout), fn
        {{:bind, v}, {_, {:var, _} = w}} -> v == w
        _ -> false
      end)
  end

  # ein Schnitt in den Zielen (auch in Zweigen von ( -> ; ))?
  def cut_in?(gs) do
    Enum.any?(gs, fn
      :cut -> true
      {:ite, _, _, t, e, _} -> cut_in?(t) or cut_in?(e)
      _ -> false
    end)
  end

  # die stark zusammenhängenden Komponenten, Gerufene zuerst
  def sccs(parsed) do
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

  @why_key :prolog_ex_jit_why

  # Grund, warum key nicht übersetzt wird (der erste zählt)
  def why(key, reason),
    do: Process.put(@why_key, Map.put_new(Process.get(@why_key), key, reason))

  def no!(reason), do: throw({:no, reason})

  def pi({n, a}), do: "#{n}/#{a}"

  def vname({:var, {n, _}}) when is_binary(n), do: n

  def vname({:var, n}) when is_binary(n), do: n

  def vname(_), do: "_"

  # ein Term oder Ziel, kurz
  def desc({:atom, a}), do: a

  def desc({:struct, f, a}), do: "#{f}/#{length(a)}"

  def desc({:var, _} = v), do: "Variable #{vname(v)}"

  def desc(t) when is_binary(t), do: "Zeichenkette"

  def desc(t) when is_list(t), do: "Liste"

  def desc(t), do: inspect(t)

  def tname(:num), do: "Zahl"

  def tname(:list), do: "Liste"

  def tname(:nlist), do: "Liste von Zahlen"

  def tname(:any), do: "beliebiger Term"

  def tname(:bot), do: "?"

  # Variablen eines Terms (Listen auch mit Variablen als Rest)
  def raw_vars({:var, _} = v, acc), do: [v | acc]

  def raw_vars([h | t], acc), do: raw_vars(t, raw_vars(h, acc))

  def raw_vars(t, acc) when is_tuple(t), do: Enum.reduce(Tuple.to_list(t), acc, &raw_vars/2)

  def raw_vars(_, acc), do: acc

  def args({:struct, _, a}), do: a

  # Terme ohne Ground-Markierung
  def plain({tag, f, a}) when tag in [:struct, :gstruct], do: {:struct, f, Enum.map(a, &plain/1)}

  def plain({:glist, l}), do: plain(l)

  def plain([h | t]), do: [plain(h) | plain(t)]

  def plain(t), do: t

  def vars({:var, _} = v), do: [v]

  def vars({:op2, _, a, b}), do: vars(a) ++ vars(b)

  def vars({:op1, _, a}), do: vars(a)

  def vars({:cons, a, b}), do: vars(a) ++ vars(b)

  def vars({:st, _, ps}), do: Enum.flat_map(ps, &vars/1)
  def vars({:nv, b}), do: vars(b)

  def vars(_), do: []

  def anon?({:var, {"_", _}}), do: true

  def anon?({:var, "_"}), do: true

  def anon?(_), do: false
end
