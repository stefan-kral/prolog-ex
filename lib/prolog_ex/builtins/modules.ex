defmodule PrologEx.Builtins.Modules do
  @moduledoc """
  Module: use_module/1,2, ensure_loaded/1, consult/1, current_module/1,
  strip_module/3, meta_predicate/1, dazu Hilfsfunktionen für
  Prädikatsindikatoren mit Modul (`M:Name/Arity`).

  Bibliotheksmodule (`library(lists)`, `library(apply)`) sind eingebaut;
  `use_module` importiert nur ihre Exporte. Andere Dateien werden geladen
  (einmal; consult/1 lädt neu) und ihre Exporte (aus `:- module/2`) in
  das Kontextmodul importiert.
  """
  use PrologEx.Builtin
  alias PrologEx.{Compiler, Consult}

  defbuiltin "use_module", [spec] do
    use_module(deref(spec), :all, context_module(), subst())
  end

  defbuiltin "use_module", [spec, imports] do
    keys = for {_m, n, ar} <- indicators(resolve(imports), "user"), do: {n, ar}
    use_module(deref(spec), keys, context_module(), subst())
  end

  defbuiltin "ensure_loaded", [spec] do
    use_module(deref(spec), :all, context_module(), subst())
  end

  defbuiltin "consult", [spec] do
    for f <- files(resolve(spec)), do: Consult.load_file(f, into: context_module())
    :ok
  end

  defbuiltin "current_module", [m], nondet: true do
    case deref(m) do
      {:atom, name} -> if name in modules(), do: [:ok], else: []
      {:var, _} -> for name <- modules(), do: {:unify, [{m, a(name)}]}
      other -> PrologEx.Error.type!("atom", other)
    end
  end

  defbuiltin "strip_module", [t, m, plain] do
    {mod, p} = strip(deref(t), context_module(), subst())
    {:unify, [{m, a(mod)}, {plain, p}]}
  end

  defbuiltin "meta_predicate", [spec] do
    PrologEx.put_db(declare_meta(PrologEx.current_db(), resolve(spec), context_module()))
    :ok
  end

  # predicate_property(Kopf, Eigenschaft) wie SICStus. Kopf darf M:Kopf
  # sein (M auch ungebunden), sonst gilt das Kontextmodul; ist Kopf
  # ungebunden, werden alle dort sichtbaren Prädikate aufgezählt
  # (definierte, importierte, system). Eigenschaften:
  #   built_in | compiled | interpreted      (genau eine; dynamische
  #                                           Prädikate sind interpreted)
  #   dynamic
  #   exported | imported_from(M)            (höchstens eine)
  #   meta_predicate(Kopf)                   (mit den Angaben der Deklaration)
  #   number_of_clauses(N)                   (Erweiterung wie SWI; nur für
  #                                           Prädikate der Datenbank)
  defbuiltin "predicate_property", [head, prop], nondet: true do
    s = subst()
    db = db()

    {mod_t, h} =
      case PrologEx.walk(head, s) do
        {tag, ":", [m, inner]} when tag in [:struct, :gstruct] ->
          {PrologEx.walk(m, s), PrologEx.walk(inner, s)}

        other ->
          {a(context_module()), other}
      end

    mods =
      case mod_t do
        {:atom, m} -> [m]
        {:var, _} -> modules()
        other -> PrologEx.Error.type!("atom", other)
      end

    for m <- mods,
        {n, ar} <- candidate_keys(db, m, h),
        p <- properties(db, m, n, ar),
        do: {:unify, [{mod_t, a(m)}, {h, general(n, ar)}, {prop, p}]}
  end

  defp candidate_keys(db, m, {:var, _}) do
    local = for {^m, n, ar} <- Map.keys(db), do: {n, ar}
    imported = for {:import, ^m, n, ar} <- Map.keys(db), do: {n, ar}
    lib = PrologEx.Builtins.keys(m)
    Enum.uniq(local ++ imported ++ lib ++ PrologEx.Builtins.system_keys())
  end

  defp candidate_keys(_db, _m, h) do
    case PrologEx.unmark_top(h) do
      n when is_number(n) -> PrologEx.Error.type!("callable", n)
      t -> [Compiler.key(t)]
    end
  end

  defp general(n, 0), do: a(n)
  defp general(n, ar), do: mk(n, for(_ <- 1..ar, do: fresh_var()))

  @doc false
  def properties(db, m, n, ar) do
    origin = fn dm ->
      cond do
        dm != m -> [mk("imported_from", [a(dm)])]
        exported?(db, dm, n, ar) -> [a("exported")]
        true -> []
      end
    end

    case PrologEx.locate(db, m, n, ar) do
      {:db, dm, pred} ->
        dyn = PrologEx.dynamic?(db, {dm, n, ar})
        impl = if dyn, do: [a("interpreted"), a("dynamic")], else: [a("compiled")]
        clauses = [mk("number_of_clauses", [length(PrologEx.pred_entries(pred))])]
        impl ++ origin.(dm) ++ meta_prop(Map.get(db, {:meta, dm, n, ar}), n) ++ clauses

      {:builtin, "system", _} ->
        [a("built_in")]

      {:builtin, lib, _} ->
        [a("compiled")] ++ origin.(lib) ++ meta_prop(PrologEx.Builtins.meta(lib, n, ar), n)

      :none ->
        if PrologEx.Builtins.system?({n, ar}), do: [a("built_in")], else: []
    end
  end

  defp exported?(db, m, n, ar) do
    case Map.fetch(db, {:module, m}) do
      {:ok, %{exports: ex}} ->
        MapSet.member?(ex, {n, ar})

      :error ->
        case PrologEx.Builtins.exports(m) do
          nil -> false
          ex -> MapSet.member?(ex, {n, ar})
        end
    end
  end

  defp meta_prop(nil, _n), do: []

  defp meta_prop(specs, n) do
    args = Enum.map(specs, fn s -> if is_integer(s), do: s, else: a(s) end)
    [mk("meta_predicate", [mk(n, args)])]
  end

  # --- use_module --------------------------------------------------------

  defp use_module({:var, _}, _keys, _ctx, _s), do: PrologEx.Error.instantiation!()

  defp use_module({tag, "library", [lib]}, keys, ctx, s) when tag in [:struct, :gstruct] do
    name = lib_name(PrologEx.walk(lib, s))

    case {PrologEx.Builtins.exports(name), PrologEx.Builtins.library_file(name)} do
      {nil, nil} ->
        PrologEx.Error.existence!("source_sink", mk("library", [a(name)]))

      {nil, path} ->
        use_file(path, keys, ctx)

      {exports, _} ->
        for {p, type, op} <- PrologEx.Builtins.ops(name),
            do: PrologEx.Reader.op(PrologEx.Reader.current(), p, type, op)

        import(name, select(exports, keys, name), ctx)
    end

    :ok
  end

  defp use_module(spec, keys, ctx, _s) do
    for f <- files(spec), do: use_file(f, keys, ctx)
    :ok
  end

  defp use_file(f, keys, ctx) do
    module =
      case Consult.loaded(f) do
        {:ok, m} -> m
        :error -> elem(Consult.load_file(f, into: nil), 1)
      end

    if module do
      exports = PrologEx.current_db() |> Map.fetch!({:module, module}) |> Map.fetch!(:exports)
      import(module, select(exports, keys, module), ctx)
    end
  end

  defp lib_name({:atom, n}), do: n
  # library(clpfd/foo) u. ä.: Pfad als Name
  defp lib_name(other), do: file_name(other)

  defp select(exports, :all, _m), do: Enum.to_list(exports)

  defp select(exports, keys, m) do
    for k <- keys do
      if MapSet.member?(exports, k),
        do: k,
        else: PrologEx.Error.permission!("import", "private_procedure", qualified(m, k))
    end
  end

  # Import in ctx; lokale Definitionen und frühere Importe aus einem
  # anderen Modul gehen vor (wie SWI; dann eine Warnung auf stderr)
  defp import(m, keys, ctx) do
    PrologEx.update_db(fn db ->
      Enum.reduce(keys, db, fn {n, ar}, db ->
        # Re-Export: aus dem Quellmodul
        m = if PrologEx.Builtins.exports(m), do: PrologEx.Builtins.source(m, n, ar), else: m

        case import_check(db, m, ctx, n, ar) do
          :ok ->
            Map.put(db, {:import, ctx, n, ar}, m)

          :same ->
            db

          {:warn, text} ->
            IO.puts(:stderr, "Warnung: " <> text)
            db
        end
      end)
    end)
  end

  @doc false
  def import_check(db, m, ctx, n, ar) do
    cond do
      m == ctx ->
        :same

      Map.has_key?(db, {ctx, n, ar}) ->
        {:warn, "#{ctx}:#{n}/#{ar} ist lokal definiert, Import aus #{m} ignoriert"}

      true ->
        case Map.fetch(db, {:import, ctx, n, ar}) do
          :error ->
            :ok

          {:ok, ^m} ->
            :same

          {:ok, other} ->
            {:warn, "#{n}/#{ar} ist schon aus #{other} in #{ctx} importiert, #{m} ignoriert"}
        end
    end
  end

  defp qualified(m, {n, ar}), do: mk(":", [a(m), PrologEx.Error.indicator(n, ar)])

  defp modules do
    db = PrologEx.current_db()
    loaded = for {:module, m} <- Map.keys(db), do: m
    (["user", "system"] ++ PrologEx.Builtins.library_modules() ++ loaded) |> Enum.uniq()
  end

  # --- Dateinamen --------------------------------------------------------

  # Eine Liste ist eine Liste von Dateien; eine Liste darin ist ein Name als
  # Zeichen- oder Codeliste ("datei.pl" mit double_quotes=chars/codes, wie
  # Strings in SWI): consult(["a.pl", b]).
  # Ganz außen ist eine Liste von Codes oder von Einzelzeichen mit "." oder
  # "/" ein Name (consult("a.pl")), sonst eine Liste von Dateien
  # (consult([a, b])).
  @doc false
  def files({:glist, _} = l), do: files(PrologEx.unmark(l))

  def files(l) when is_list(l) do
    items = prolog_items(l)
    if text?(items), do: [file_name(l)], else: Enum.map(items, &file_name/1)
  end

  def files(t), do: [file_name(t)]

  defp text?([]), do: false

  defp text?(items) do
    Enum.all?(items, &(is_integer(&1) and &1 >= 0)) or
      (Enum.all?(items, &match?({:atom, <<_::utf8>>}, &1)) and
         Enum.any?(items, &(&1 in [{:atom, "."}, {:atom, "/"}])))
  end

  defp prolog_items([]), do: []
  defp prolog_items([h | t]), do: [h | prolog_items(t)]
  defp prolog_items(other), do: PrologEx.Error.type!("list", other)

  @doc false
  def file_name({:glist, _} = l), do: file_name(PrologEx.unmark(l))

  def file_name([_ | _] = l) do
    l
    |> prolog_items()
    |> Enum.map(fn
      {:atom, <<c::utf8>>} -> c
      c when is_integer(c) and c >= 0 -> c
      _ -> PrologEx.Error.type!("atom", l)
    end)
    |> List.to_string()
  end

  def file_name({:atom, name}), do: name

  def file_name({tag, "/", [x, y]}) when tag in [:struct, :gstruct],
    do: file_name(x) <> "/" <> file_name(y)

  def file_name({:var, _}), do: PrologEx.Error.instantiation!()
  def file_name(other), do: PrologEx.Error.type!("atom", other)

  # --- Hilfsfunktionen für andere Builtins --------------------------------

  @doc """
  `M:T` abstreifen: `{modul, t}` (verschachtelt: das innerste Modul gilt).
  """
  def strip(t, mod, s) do
    case PrologEx.walk(t, s) do
      {tag, ":", [m, inner]} when tag in [:struct, :gstruct] ->
        case PrologEx.walk(m, s) do
          {:atom, name} -> strip(inner, name, s)
          {:var, _} -> PrologEx.Error.instantiation!()
          other -> PrologEx.Error.type!("module", other)
        end

      other ->
        {mod, other}
    end
  end

  @doc """
  Prädikatsindikatoren aus `foo/1`, `(foo/1, bar/2)`, `[foo/1]`, `m:foo/1`,
  `m:(foo/1, bar/2)` als `[{modul, name, arity}]`.
  """
  def indicators(spec, mod) do
    case PrologEx.unmark_top(spec) do
      {:struct, ":", [{:atom, m}, inner]} -> indicators(inner, m)
      {:struct, ",", [x, y]} -> indicators(x, mod) ++ indicators(y, mod)
      [] -> []
      [h | t] -> indicators(h, mod) ++ indicators(t, mod)
      {:glist, _} = l -> indicators(PrologEx.unmark(l), mod)
      {:struct, "/", [{:atom, n}, ar]} when is_integer(ar) -> [{mod, n, ar}]
      {:struct, "//", [{:atom, n}, ar]} when is_integer(ar) -> [{mod, n, ar + 2}]
      {:var, _} -> PrologEx.Error.instantiation!()
      other -> PrologEx.Error.type!("predicate_indicator", other)
    end
  end

  @doc "meta_predicate-Deklarationen eintragen: `{:meta, m, name, arity} => specs`"
  def declare_meta(db, spec, mod) do
    spec
    |> conj_list()
    |> Enum.reduce(db, fn head, db ->
      {m, h} = strip(head, mod, %{})
      {name, arity} = Compiler.key(h)
      Map.put(db, {:meta, m, name, arity}, Enum.map(Compiler.args_of(h), &meta_arg/1))
    end)
  end

  defp conj_list(t) do
    case PrologEx.unmark_top(t) do
      {:struct, ",", [x, y]} -> conj_list(x) ++ conj_list(y)
      [h | rest] -> [h | conj_list_rest(rest)]
      x -> [x]
    end
  end

  defp conj_list_rest([]), do: []
  defp conj_list_rest([h | t]), do: [h | conj_list_rest(t)]

  defp meta_arg(n) when is_integer(n), do: n
  defp meta_arg({:atom, name}), do: name
  defp meta_arg(other), do: PrologEx.Error.domain!("meta_argument_specifier", other)
end
