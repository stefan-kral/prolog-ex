defmodule PrologEx.JitListing do
  @moduledoc """
  jit_listing/0,1: welche Prädikate eines Moduls PrologEx.Jit übersetzt
  hat – mit Modi und Typen –, und für die übrigen, warum nicht.

      % fib/2       übersetzt          fib(+int, -int)
      % app/3       übersetzt          app(+list, +any, -)
      % sq/2        nur für Rufer      sq(+int, -int)
      % klasse/2    nein               Klausel 2: Ziel is_list/1

  Status: „übersetzt“ (Code geladen), „analysiert“ (übersetzt ab dem n-ten
  Aufruf, Flag jit_threshold), „nur für Rufer“ (übersetzt, aber der Interpreter tritt nicht ein:
  ein Fakt), „wäre übersetzbar“ (beim Laden war das Flag jit aus), „nein“
  mit Grund. Typen: int/num (Zahl; Ganzzahl im ganzzahligen Code), list,
  list(int), list(num), any (nur durchgereicht); eine Ausgabe ohne Typ
  hängt von den Eingaben ab.
  """

  @doc "Text für das Modul (spec: :all, ein Name oder Name/Stelligkeit)"
  def listing(db, spec, module) do
    preds =
      for {{^module, n, a}, p} <- db,
          is_binary(n),
          pick?(spec, n, a),
          p = PrologEx.materialize(p),
          match?({:pred, [_ | _], _, _, _}, p),
          do: {{n, a}, p}

    # die nicht übersetzten zusammen analysieren (wie ein Ladeschritt)
    rest =
      for {k, p} <- preds, status(db, module, k, p) == nil, do: {k, p}

    why =
      if rest == [] do
        %{}
      else
        plain =
          for {k, p} <- rest, do: {k, {:pred, elem(p, 1), nil, nil, PrologEx.pred_entries(p)}}

        {src, ext, dyn} = PrologEx.jit_input(plain, db, module)
        PrologEx.Jit.explain(src, ext, dyn)
      end

    rows =
      preds
      |> Enum.sort()
      |> Enum.map(fn {{n, a} = k, p} ->
        {what, detail} =
          case status(db, module, k, p) do
            {st, info} ->
              {st, signature(n, a, info)}

            nil ->
              case why[k] do
                {:ok, _} -> {"wäre übersetzbar", "beim Laden war das Flag jit aus"}
                {:no, r} -> {"nein", r}
                nil -> {"nein", "?"}
              end
          end

        {"#{n}/#{a}", what, detail}
      end)

    w1 = rows |> Enum.map(&String.length(elem(&1, 0))) |> Enum.max(fn -> 0 end)
    w2 = rows |> Enum.map(&String.length(elem(&1, 1))) |> Enum.max(fn -> 0 end)

    lines =
      for {pi, what, detail} <- rows,
          do: "% #{String.pad_trailing(pi, w1)}  #{String.pad_trailing(what, w2)}  #{detail}\n"

    done = Enum.count(rows, fn {_, w, _} -> w in ["übersetzt", "analysiert", "nur für Rufer"] end)
    Enum.join(lines) <> "% #{done} von #{length(rows)} übersetzt\n"
  end

  defp pick?(:all, _, _), do: true
  defp pick?({:atom, n}, n, _), do: true
  defp pick?({:struct, "/", [{:atom, n}, a]}, n, a), do: true
  defp pick?(_, _, _), do: false

  # übersetzt? {status, info} oder nil
  defp status(db, module, {n, a}, p) do
    case p do
      {:pred, _, _, {:jit, info, _, _, _, _}, _} ->
        {loaded(info), info}

      _ ->
        case db do
          %{{:jit_info, ^module, ^n, ^a} => info} -> {"nur für Rufer", info}
          _ -> nil
        end
    end
  end

  defp loaded({mod, _, _, _, _}),
    do: if(:erlang.module_loaded(mod), do: "übersetzt", else: "analysiert")

  defp signature(n, a, {_, _, _, _, sig}) do
    args =
      for k <- 0..(a - 1) do
        case sig.modes[k] do
          :in ->
            "+" <> tdesc(sig.req[k], sig.num)

          :out ->
            case sig.out[k] do
              {t, []} -> "-" <> tdesc(t, sig.num)
              _ -> "-"
            end
        end
      end

    "#{n}(#{Enum.join(args, ", ")})"
  end

  defp tdesc(:num, false), do: "int"
  defp tdesc(:num, true), do: "num"
  defp tdesc(:nlist, false), do: "list(int)"
  defp tdesc(:nlist, true), do: "list(num)"
  defp tdesc(:list, _), do: "list"
  defp tdesc(:any, _), do: "any"
  defp tdesc(_, _), do: ""
end
