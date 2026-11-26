defmodule PrologEx.Builtins.IsDirectives do
  @moduledoc """
  `:- Spec is Annotation.` wie in SICStus (library(is_directives)):
  deklariert, wie oft ein Prädikat gelingt. Erkannt beim Laden, auch ohne
  `use_module(library(is_directives))`, wenn Annotation eine von `det`,
  `semidet`, `multi`, `nondet`, `failing`, `throwing` ist – sonst bleibt
  `is/2` die Arithmetik.

      :- foo/2 is det.
      :- bar(+, ?) is semidet.          % nur für Aufrufe mit nichtvariablem 1. Argument
      :- parent_of(+Parent, -Child) is nondet.
      :- dolist(+, -, det) is det.      % je nach Determinismus der Closure

  Spec: `Name/Arity` oder ein Skelett (`+` beim Aufruf keine Variable, `-`
  eine Variable, `?`/`*` gleich; `+X` zählt wie `+`), mit `M:` davor auch
  für ein anderes Modul. Wie in SICStus nur Hinweise: nichts wird geprüft.

  Abfragen (library(is_directives)):

    * `current_is_directive(?Skel, ?M, ?Annotation, ?Spec, ?Directive, ?Context)` –
      Skel: Name mit anonymen Argumenten, M: Modul des Prädikats, Spec: das
      erste Argument von is/2 ohne Modul, Directive: die Direktive ohne
      `:-`, Context: das Modul, in dem sie stand
    * `current_is_directive(:MSkel, ?Annotation, ?Spec)` – M aus MSkel (sonst
      das Kontextmodul)

  Reihenfolge (SICStus legt keine fest): wie im Quelltext, Dateien in der
  Reihenfolge, in der sie zuerst geladen wurden; mehrere Deklarationen je
  Prädikat bleiben alle. Lädt eine Datei neu, ersetzen ihre Deklarationen
  die alten aus ihr, an derselben Stelle.

  PrologEx.Jit nimmt die Aufrufmuster von `det`/`semidet`-Deklarationen als
  Hinweise auf die Modi (vor denen der Aufrufstellen; `+` Eingabe, `-`
  Ausgabe), nie den Determinismus selbst: deterministisch übersetzt wird
  nur, was er selbst nachweist. jit_listing/0 vermerkt, wo eine solche
  Deklaration und das Ergebnis auseinandergehen.
  """
  use PrologEx.Builtin, module: "is_directives"

  @anns ~w(det semidet multi nondet failing throwing)

  @doc "Die Annotationen, an denen die Direktive erkannt wird"
  def annotations, do: @anns

  @doc """
  Eine Direktive (ohne `:-`) als Deklaration: `{:ok, rec}` oder `:no`
  (dann ist sie ein gewöhnliches Ziel)
  """
  def parse(g, ctx_module) do
    case PrologEx.unmark(g) do
      {:struct, "is", [spec, {:atom, ann}]} = d when ann in @anns ->
        {m, s} = strip(spec, ctx_module)

        case key(s) do
          {n, a} ->
            {:ok,
             %{module: m, name: n, arity: a, ann: ann, spec: s, directive: d, context: ctx_module}}

          nil ->
            :no
        end

      _ ->
        :no
    end
  end

  defp strip({:struct, ":", [{:atom, m}, t]}, _), do: strip(t, m)
  defp strip(t, m), do: {m, t}

  defp key({:struct, "/", [{:atom, n}, a]}) when is_integer(a) and a >= 0, do: {n, a}
  defp key({:atom, n}), do: {n, 0}
  defp key({:struct, n, as}), do: {n, length(as)}
  defp key(_), do: nil

  # --- Speicher (in der Datenbank) ------------------------------------------

  @doc false
  def record(db, file, rec) do
    files = Map.get(db, {:is_directive_files}, [])
    files = if file in files, do: files, else: files ++ [file]

    db
    |> Map.put({:is_directive_files}, files)
    |> Map.update({:is_directives, file}, [rec], &(&1 ++ [rec]))
  end

  @doc false
  # vor dem (erneuten) Laden einer Datei: ihre Deklarationen vergessen
  def reset(db, nil), do: db
  def reset(db, file), do: Map.delete(db, {:is_directives, file})

  @doc "Alle Deklarationen, in Ladereihenfolge"
  def all(db) do
    for f <- Map.get(db, {:is_directive_files}, []),
        rec <- Map.get(db, {:is_directives, f}, []),
        do: rec
  end

  @doc """
  Für PrologEx.Jit: Modi aus den Aufrufmustern der det/semidet-Deklarationen
  der Prädikate von `module`, `%{{name, arity} => %{k => :in | :out}}` (je
  Prädikat die erste Deklaration mit `+` oder `-`)
  """
  def jit_modes(db, module) do
    for rec <- all(db), rec.module == module, rec.ann in ["det", "semidet"], reduce: %{} do
      acc ->
        ms = pattern_modes(rec.spec)
        k = {rec.name, rec.arity}
        if ms == %{} or Map.has_key?(acc, k), do: acc, else: Map.put(acc, k, ms)
    end
  end

  @doc "Die Modi eines Skeletts: %{k => :in | :out} (`+`, `-`; sonst keiner)"
  def pattern_modes({:struct, "/", [{:atom, _}, a]}) when is_integer(a), do: %{}

  def pattern_modes({:struct, _, as}) do
    for {x, k} <- Enum.with_index(as), m = mode(x), m != nil, into: %{}, do: {k, m}
  end

  def pattern_modes(_), do: %{}

  defp mode({:atom, "+"}), do: :in
  defp mode({:atom, "-"}), do: :out
  defp mode({:struct, "+", [_]}), do: :in
  defp mode({:struct, "-", [_]}), do: :out
  defp mode(_), do: nil

  @doc "Für jit_listing: die Deklarationen je {name, arity} von `module`"
  def of_module(db, module) do
    for rec <- all(db), rec.module == module, reduce: %{} do
      acc -> Map.update(acc, {rec.name, rec.arity}, [rec], &(&1 ++ [rec]))
    end
  end

  # --- Abfragen ------------------------------------------------------------------

  defbuiltin "current_is_directive", [skel, m, ann, spec, dir, cm], nondet: true do
    for rec <- all(PrologEx.current_db()) do
      [sk, sp, d] = fresh([skeleton(rec), rec.spec, rec.directive])

      {:unify,
       [
         {skel, sk},
         {m, a(rec.module)},
         {ann, a(rec.ann)},
         {spec, sp},
         {dir, d},
         {cm, a(rec.context)}
       ]}
    end
  end

  defbuiltin "current_is_directive", [mskel, ann, spec], nondet: true do
    {mt, sk} =
      case deref(mskel) do
        {:struct, ":", [mm, ss]} -> {mm, ss}
        other -> {a(context_module()), other}
      end

    for rec <- all(PrologEx.current_db()) do
      [s, sp] = fresh([skeleton(rec), rec.spec])
      {:unify, [{mt, a(rec.module)}, {sk, s}, {ann, a(rec.ann)}, {spec, sp}]}
    end
  end

  defp skeleton(%{name: n, arity: 0}), do: a(n)
  defp skeleton(%{name: n, arity: k}), do: {:struct, n, Enum.map(1..k, fn _ -> {:var, :_} end)}

  # eine Kopie mit frischen Variablen (gemeinsame bleiben gemeinsam; die
  # Platzhalter {:var, :_} des Skeletts je eine neue)
  defp fresh(ts) do
    ts = Enum.map(ts, &anon/1)
    {{:struct, "t", cs}, _} = PrologEx.copy_mapped({:struct, "t", ts}, %{})
    cs
  end

  defp anon({:var, :_}), do: fresh_var()
  defp anon({:struct, f, as}), do: {:struct, f, Enum.map(as, &anon/1)}
  defp anon(t), do: t
end
