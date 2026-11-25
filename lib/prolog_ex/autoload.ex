defmodule PrologEx.Autoload do
  @moduledoc """
  Autoload: Prädikate, die ein Ziel aufruft, die im Modul nicht sichtbar
  sind, aber eindeutig in einer Bibliothek liegen
  (`PrologEx.LibraryIndex.choice/2`), in das Modul importieren – nur sie
  (`use_module/2` mit Liste).

  Genutzt vom Toplevel (Flag `toplevel_autoload`: vor jeder Anfrage) und
  beim Laden (Flag `autoload`: am Ende eines Ladevorgangs für die
  Klauselrümpfe, vor jeder Direktive für sie; `PrologEx.Consult`).

  Durchgesehen werden die Steuerkonstrukte und die Meta-Argumente
  (`maplist(foo, ...)` → `foo/N`); nach einem Import noch einmal (die
  Meta-Argumente einer eben importierten Bibliothek). Was erst zur
  Laufzeit entsteht (`call(G)` mit gebautem `G`), bleibt beim Fehler mit
  Hinweis.
  """

  @doc """
  Die fehlenden Prädikate der Ziele im Modul m: `[{bibliothek, [{name,
  stelligkeit}]}]`, nach Bibliothek sortiert
  """
  def missing(goals, db, m) do
    goals
    |> Enum.reduce([], &scan(&1, db, m, &2))
    |> Enum.reverse()
    |> Enum.uniq()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort()
  end

  @doc """
  Importiert die Prädikate keys aus library(lib) nach m – still (ohne die
  Meldungen von verbose_load) und am Tracer vorbei: der Import gehört
  nicht zur Anfrage. `{:ok, db}` oder `:error`
  """
  def import(db, m, lib, keys) do
    {:term, spec, _} = PrologEx.Parser.read_one("library(#{lib}).")
    pis = for {n, a} <- keys, do: {:struct, "/", [{:atom, n}, a]}
    goal = {:struct, "use_module", [PrologEx.unmark(spec), pis]}

    trace = Process.delete(:prolog_ex_trace)
    load = PrologEx.Flags.explicit("verbose_load")
    PrologEx.Flags.set("verbose_load", {:atom, "silent"})

    try do
      PrologEx.put_db(db)

      case Enum.take(PrologEx.query(db, goal, module: m), 1) do
        [_] -> {:ok, PrologEx.current_db()}
        [] -> :error
      end
    rescue
      PrologEx.Error -> :error
    after
      if load,
        do: PrologEx.Flags.set("verbose_load", load),
        else: PrologEx.Flags.unset("verbose_load")

      if trace, do: Process.put(:prolog_ex_trace, trace)
    end
  end

  @doc """
  Bis zu `rounds` Runden: fehlende suchen, importieren (je Import
  `report.(lib, keys)`), dann noch einmal. Liefert die Datenbank
  """
  def run(goals, db, m, report, rounds \\ 3)
  def run(_goals, db, _m, _report, 0), do: db

  def run(goals, db, m, report, rounds) do
    case missing(goals, db, m) do
      [] ->
        db

      libs ->
        {db, any?} =
          Enum.reduce(libs, {db, false}, fn {lib, keys}, {db, any?} ->
            case import(db, m, lib, keys) do
              {:ok, db} ->
                report.(lib, keys)
                {db, true}

              :error ->
                {db, any?}
            end
          end)

        if any?, do: run(goals, db, m, report, rounds - 1), else: db
    end
  end

  # Steuerkonstrukte und eingebaute Meta-Prädikate ohne eigene Angabe
  @control_meta %{
    {"findall", 3} => ["?", 0, "?"],
    {"findall", 4} => ["?", 0, "?", "?"],
    {"once", 1} => [0],
    {"ignore", 1} => [0],
    {"catch", 3} => [0, "?", 0],
    {"phrase", 2} => ["//", "?"],
    {"phrase", 3} => ["//", "?", "?"]
  }

  defp scan({:var, _}, _db, _m, acc), do: acc
  defp scan({:struct, ":", [_, _]}, _db, _m, acc), do: acc

  defp scan({:struct, f, [a, b]}, db, m, acc) when f in [",", ";", "->", "*->"],
    do: scan(b, db, m, scan(a, db, m, acc))

  defp scan({:struct, "\\+", [a]}, db, m, acc), do: scan(a, db, m, acc)

  defp scan({:struct, "call", [c | extra]}, db, m, acc),
    do: closure(c, length(extra), db, m, acc)

  defp scan({:atom, n}, db, m, acc), do: pred(n, [], db, m, acc)
  defp scan({:struct, n, args}, db, m, acc), do: pred(n, args, db, m, acc)
  defp scan(_, _db, _m, acc), do: acc

  defp pred(n, args, db, m, acc) do
    a = length(args)

    # schon importiert gilt als sichtbar, auch wo locate/4 es nicht findet
    # (trace/0: eingebaut mit Heimat traces) – sonst käme der Import bei
    # jeder Anfrage wieder
    found =
      if Map.has_key?(db, {:import, m, n, a}),
        do: :imported,
        else: PrologEx.locate(db, m, n, a)

    {acc, meta} =
      case found do
        :imported ->
          # die Angabe aus dem Modul, aus dem importiert wurde (eine
          # Bibliothek in Prolog: erst nach dem Laden bekannt – darum die
          # zweite Runde von run/5: limit(4, permutationd(…)))
          src = Map.get(db, {:import, m, n, a})

          {acc,
           Map.get(db, {:meta, src, n, a}) || PrologEx.Builtins.meta(src, n, a) ||
             Map.get(@control_meta, {n, a})}

        :none ->
          case PrologEx.LibraryIndex.choice(n, a) do
            nil ->
              {acc, Map.get(@control_meta, {n, a})}

            lib ->
              {[{lib, {n, a}} | acc],
               PrologEx.Builtins.meta(PrologEx.Builtins.source(lib, n, a), n, a)}
          end

        {:db, dm, _} ->
          {acc, Map.get(db, {:meta, dm, n, a})}

        {:builtin, bm, _} ->
          {acc, PrologEx.Builtins.meta(bm, n, a) || Map.get(@control_meta, {n, a})}
      end

    case meta do
      specs when is_list(specs) and length(specs) == a ->
        Enum.zip(args, specs)
        |> Enum.reduce(acc, fn
          {g, 0}, acc -> scan(g, db, m, acc)
          {c, k}, acc when is_integer(k) -> closure(c, k, db, m, acc)
          {g, "^"}, acc -> scan(strip_caret(g), db, m, acc)
          {c, "//"}, acc -> closure(c, 2, db, m, acc)
          _, acc -> acc
        end)

      _ ->
        acc
    end
  end

  # ein Closure mit k weiteren Argumenten
  defp closure({:atom, n}, k, db, m, acc), do: pred(n, List.duplicate({:var, 0}, k), db, m, acc)

  # Lambdas aus library(yall): [X1,...]>>Rumpf mit k Argumenten – der
  # Rumpf bekommt die nach den Parametern; Free/Rumpf: der Rumpf alle k
  defp closure({:struct, ">>", [ps, body] = args}, k, db, m, acc) do
    acc = pred(">>", args ++ List.duplicate({:var, 0}, k), db, m, acc)

    case yall_params(ps) do
      n when is_integer(n) and n <= k -> body_closure(body, k - n, db, m, acc)
      _ -> acc
    end
  end

  defp closure({:struct, "/", [_free, body] = args}, k, db, m, acc) do
    acc = pred("/", args ++ List.duplicate({:var, 0}, k), db, m, acc)
    body_closure(body, k, db, m, acc)
  end

  defp closure({:struct, n, args}, k, db, m, acc) when n != ":",
    do: pred(n, args ++ List.duplicate({:var, 0}, k), db, m, acc)

  defp closure(_, _k, _db, _m, acc), do: acc

  # ohne weitere Argumente ein Ziel (Konjunktion, ...), sonst ein Closure
  defp body_closure(body, 0, db, m, acc), do: scan(body, db, m, acc)
  defp body_closure(body, k, db, m, acc), do: closure(body, k, db, m, acc)

  defp yall_params({:struct, "/", [_, ps]}), do: yall_params(ps)
  defp yall_params(ps), do: yall_length(ps, 0)

  defp yall_length([], n), do: n
  defp yall_length([_ | t], n), do: yall_length(t, n + 1)
  defp yall_length(_, _), do: nil

  defp strip_caret({:struct, "^", [_, g]}), do: strip_caret(g)
  defp strip_caret(g), do: g
end
