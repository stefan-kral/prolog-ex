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

  # --- use_module --------------------------------------------------------

  defp use_module({:var, _}, _keys, _ctx, _s), do: PrologEx.Error.instantiation!()

  defp use_module({tag, "library", [lib]}, keys, ctx, s) when tag in [:struct, :gstruct] do
    name = lib_name(PrologEx.walk(lib, s))

    case PrologEx.Builtins.exports(name) do
      nil -> PrologEx.Error.existence!("source_sink", mk("library", [a(name)]))
      exports -> import(name, select(exports, keys, name), ctx)
    end

    :ok
  end

  defp use_module(spec, keys, ctx, _s) do
    for f <- files(spec) do
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

    :ok
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

  @doc false
  def files([]), do: []
  def files([h | t]), do: files(h) ++ files(t)
  def files({:glist, _} = l), do: files(PrologEx.unmark(l))
  def files(t), do: [file_name(t)]

  defp file_name({:atom, name}), do: name

  defp file_name({tag, "/", [x, y]}) when tag in [:struct, :gstruct],
    do: file_name(x) <> "/" <> file_name(y)

  defp file_name({:var, _}), do: PrologEx.Error.instantiation!()
  defp file_name(other), do: PrologEx.Error.type!("atom", other)

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
