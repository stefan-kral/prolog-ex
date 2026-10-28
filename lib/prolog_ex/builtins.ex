defmodule PrologEx.Builtins do
  @moduledoc """
  Registry aller Builtins, nach Prolog-Modul.

  Neue Elixir-Module mit `use PrologEx.Builtin` (optional
  `module: "lists"`, Standard `"system"`) hier in `@modules` eintragen;
  einzelne Builtins können mit `defbuiltin ..., module: "..."` abweichen.
  Bibliotheksprädikate in Prolog liefert ein Modul über `library/0`
  (Liste von Klauseln, im Modul des Elixir-Moduls) oder als
  `%{"modul" => klauseln}`; sie werden beim Übersetzen kompiliert.
  `meta/0` liefert meta_predicate-Deklarationen `{modul, name, specs}`,
  `ops/0` Operatoren, die `use_module` eines Bibliotheksmoduls (global)
  setzt: `{modul, priorität, typ, name}`.

  Bibliotheken können auch Prolog-Quelltext sein: `priv/library/NAME.pl`
  mit `:- module(NAME, ...)`. `use_module(library(NAME))` lädt sie dann
  wie eine Datei (einmal), wenn es kein eingebautes Modul NAME gibt.

  ## Module

    * `system` – Steuerkonstrukte und eingebaute Prädikate; überall
      sichtbar. Geschützt (außer `protected: false`): kein Modul darf sie
      neu definieren.
    * Bibliotheksmodule (`lists`, `apply`, `random`) – exportieren alle ihre
      Prädikate außer `$...`-Hilfsprädikaten. Sichtbar nur nach `use_module(library(...))`
      (kein Autoload, wie SICStus). Eigene Definitionen im importierenden
      Modul gehen vor.
    * Heimat-Bibliotheken (`@homes`: `iso_ext`, `between`, `fastrw`, `swi`)
      – Builtins in `system`, die weder ISO noch SICStus eingebaut haben:
      sie liegen in `system`, sichtbar aber nur nach Import der Heimat
      (die sie aus `system` weitergibt), in Bibliotheksmodulen des Systems
      und mit dem Flag `swi_compat`. Nicht geschützt: eigene Definitionen
      sind erlaubt. Die Maschine prüft das für ihre Steuerkonstrukte
      (`not/1`, `*->/2`, ...) selbst (`PrologEx.home_visible?/1`).
  """

  @modules [
    PrologEx.Builtins.Core,
    PrologEx.Builtins.Terms,
    PrologEx.Builtins.Lists,
    PrologEx.Builtins.ListUtils,
    PrologEx.Builtins.ListMore,
    PrologEx.Builtins.Order,
    PrologEx.Builtins.System,
    PrologEx.Builtins.Database,
    PrologEx.Builtins.Modules,
    PrologEx.Builtins.Coroutining,
    PrologEx.Builtins.Random,
    PrologEx.Builtins.Atts,
    PrologEx.Builtins.Atoms,
    PrologEx.Builtins.Blackboard,
    PrologEx.Builtins.Mutables,
    PrologEx.Builtins.Statistics,
    PrologEx.Builtins.Lambda,
    PrologEx.Builtins.Operators,
    PrologEx.Builtins.Si,
    PrologEx.Builtins.Solutions,
    PrologEx.Builtins.IO,
    PrologEx.Builtins.Expansion,
    PrologEx.Builtins.Between,
    PrologEx.Builtins.Reif,
    PrologEx.Builtins.FastRW,
    PrologEx.Builtins.Format,
    PrologEx.Builtins.Pio,
    PrologEx.Builtins.Files,
    PrologEx.Builtins.Charsio,
    PrologEx.Builtins.ScryerPrims,
    PrologEx.Builtins.OS,
    PrologEx.Builtins.Sockets,
    PrologEx.Builtins.IsoExt
  ]

  # Steuerkonstrukte und schnelle Builtins, die die Maschine selbst
  # ausführt (siehe PrologEx.step/5); hier für den Schutz und die
  # meta_predicate-Angaben.
  @engine ~w(true/0 fail/0 false/0 !/0 ,/2 ;/2 ->/2 :/2 call/1 call/2 call/3 call/4 call/5 call/6
             call/7 call/8 call_nth/2 findall/3 findall/4 catch/3 throw/1
             findnsols/4 findnsols/5 countall/2 not/1 \\+/1 =/2 is/2 </2 >/2 >=/2 =</2 =:=/2 =\\=/2 time/1
             *->/2 if/3 call_with_inference_limit/3 call_with_depth_limit/3 setup_call_cleanup/3)
          |> Enum.map(fn s ->
            [n, a] = Regex.run(~r{^(.*)/(\d+)$}, s, capture: :all_but_first)
            {n, String.to_integer(a)}
          end)

  # Heimat eingebauter Prädikate, die nicht zu ISO gehören und die auch
  # SICStus nicht eingebaut hat: sichtbar erst nach dem Import der Bibliothek
  # (in den Modulen des Systems und mit dem Flag swi_compat immer). Die
  # Implementierung bleibt in system bzw. in der Maschine. library(swi) ist
  # der Übergang für das, was (noch) keine inhaltliche Heimat hat.
  @homes (for {lib, keys} <- [
                {"iso_ext", ~w(forall/2 succ/2 setup_call_cleanup/3 call_nth/2 countall/2
                    call_with_inference_limit/3)},
                {"between", ~w(between/3 repeat/1)},
                {"fastrw", ~w(fast_read/1 fast_read/2 fast_write/1 fast_write/2)},
                {"swi", ~w(ignore/1 not/1 *->/2 plus/3 atomic_list_concat/2 atomic_list_concat/3
                    atom_number/2 term_to_atom/2 read_term_from_atom/3 =@=/2 \\=@=/2
                    term_attvars/2 findnsols/4 findnsols/5 call_with_depth_limit/3
                    exists_file/1 exists_directory/1 delete_file/1 fast_term_serialized/2
                    time/1 statistics/0 style_check/1 expand_goal/2 dcg_translate_rule/2
                    strip_module/3)}
              ],
              k <- keys,
              into: %{} do
            [n, ar] = Regex.run(~r{^(.*)/(\d+)$}, k, capture: :all_but_first)
            {{n, String.to_integer(ar)}, lib}
          end)

  @table (for mod <- @modules,
              {key, kind, fun, protected, _helpers, pmod} <- mod.__builtins__(),
              into: %{} do
            {name, arity} = key
            {{pmod, name, arity}, {kind, fun, protected}}
          end)

  @helpers (for mod <- @modules,
                {{name, arity}, _, _, _, helpers, pmod} <- mod.__builtins__(),
                helpers != [],
                into: %{} do
              {{pmod, name, arity}, helpers}
            end)

  @library (for mod <- @modules,
                function_exported?(mod, :library, 0),
                {pmod, clauses} <-
                  (case mod.library() do
                     %{} = per_module -> per_module
                     clauses -> [{mod.__prolog_module__(), clauses}]
                   end),
                {{name, arity}, pred} <- PrologEx.build_preds(clauses),
                into: %{} do
              # in system sind nur die $-Hilfsprädikate geschützt
              {{pmod, name, arity},
               {:prolog, pred, pmod == "system" and String.starts_with?(name, "$")}}
            end)

  @all Map.merge(@table, @library)

  @meta (for mod <- @modules,
             function_exported?(mod, :meta, 0),
             {pmod, name, specs} <- mod.meta(),
             into: %{} do
           {{pmod, name, length(specs)}, specs}
         end)

  # system: geschützt sind die als geschützt markierten und die der Maschine
  # (ohne die mit einer Heimat-Bibliothek: Benutzer und Bibliotheken dürfen
  # eigene gleichen Namens haben)
  @protected for({{"system", n, a}, {_, _, true}} <- @all, into: MapSet.new(), do: {n, a})
             |> MapSet.union(MapSet.new(@engine))
             |> MapSet.difference(MapSet.new(Map.keys(@homes)))

  @system_keys (for({"system", n, a} <- Map.keys(@all), do: {n, a}) ++ @engine)
               |> MapSet.new()

  # Bibliotheksmodule und ihre Exporte (ohne $-Hilfsprädikate)
  @exports (for {{m, n, a}, _} <- @all,
                m != "system",
                not String.starts_with?(n, "$"),
                reduce: %{} do
              acc -> Map.update(acc, m, MapSet.new([{n, a}]), &MapSet.put(&1, {n, a}))
            end)

  # system-Builtins direkt nach {name, arity} (Schnellweg, ein Zugriff):
  # geschützte – kein Modul kann sie überdecken, die Auflösung ist immer
  # dieselbe – als {:protected, e}; die mit Heimat-Bibliothek (sichtbar
  # erst nach Import) als {:homed, e}
  @fast_entries for {{"system", n, ar}, {_, _, prot} = e} <- @all,
                    prot or is_map_key(@homes, {n, ar}),
                    into: %{},
                    do:
                      {{n, ar},
                       if(is_map_key(@homes, {n, ar}), do: {:homed, e}, else: {:protected, e})}

  @doc "`{:protected, eintrag}`, `{:homed, eintrag}` oder nil (siehe @fast_entries)"
  def fast_entry(name, arity), do: Map.get(@fast_entries, {name, arity})

  @doc "`{:det | :nondet, fun, protected?}`, `{:prolog, pred, protected?}` oder nil"
  def lookup(module, name, arity), do: Map.get(@all, {module, name, arity})

  @doc "Von einem Elixir-Builtin angegebene Hilfsprädikate (Option helpers:)"
  def helpers(module, name, arity), do: Map.get(@helpers, {module, name, arity}, [])

  @doc "Darf der Benutzer dieses Prädikat (in keinem Modul) definieren?"
  def protected?({name, arity}), do: MapSet.member?(@protected, {name, arity})

  @doc "Ist `{name, arity}` ein Prädikat von system (inkl. Steuerkonstrukte)?"
  def system?({name, arity}), do: MapSet.member?(@system_keys, {name, arity})

  @doc "Alle Prädikate von system (inkl. Steuerkonstrukte) als `{name, arity}`, sortiert"
  def system_keys, do: @system_keys |> Enum.sort()

  @doc "meta_predicate-Angaben eines Bibliotheksprädikats (oder nil)"
  def meta(module, name, arity), do: Map.get(@meta, {module, name, arity})

  @doc "Bibliotheksmodule"
  def library_modules, do: Map.keys(@exports) |> Enum.sort()

  # Bibliotheken in Prolog-Quelltext (priv/library/*.pl)
  @pl_libraries Path.wildcard(Path.join([__DIR__, "..", "..", "priv", "library", "*.pl"]))
                |> Enum.map(&Path.basename(&1, ".pl"))

  @system_modules MapSet.new(["system" | Map.keys(@exports)] ++ @pl_libraries)

  @doc """
  Gehört das Modul zum System (eingebaute Prädikate, Bibliotheken in Elixir
  oder in Prolog-Quelltext)? Für call_with_depth_limit/3: Klauseln solcher
  Module zählen nicht als Ebene.
  """
  def system_module?(m), do: MapSet.member?(@system_modules, m)

  @ops (for mod <- @modules,
            function_exported?(mod, :ops, 0),
            {pmod, p, type, name} <- mod.ops(),
            reduce: %{} do
          acc -> Map.update(acc, pmod, [{p, type, name}], &(&1 ++ [{p, type, name}]))
        end)

  @doc "Operatoren, die ein Bibliotheksmodul exportiert: [{prio, typ, name}]"
  def ops(module), do: Map.get(@ops, module, [])

  @doc "Pfad einer Bibliothek in Prolog-Quelltext (priv/library/NAME.pl) oder nil"
  def library_file(name) do
    path = Path.join([:code.priv_dir(:prolog_ex), "library", name <> ".pl"])
    if File.regular?(path), do: path
  end

  for {key, _} <- @homes do
    unless MapSet.member?(@system_keys, key), do: raise("Heimat: #{inspect(key)} nicht in system")
  end

  @doc "Heimat-Bibliothek eines eingebauten Prädikats außerhalb von ISO/SICStus (oder nil)"
  def home(name, arity), do: Map.get(@homes, {name, arity})

  @home_reexports (for {key, lib} <- @homes, reduce: %{} do
                     acc -> Map.update(acc, lib, %{key => "system"}, &Map.put(&1, key, "system"))
                   end)

  # Re-Exporte: Prädikate, die ein Bibliotheksmodul aus einem anderen
  # weitergibt (wie SICStus' library(lists), die maplist/N, include/3, ...
  # enthält). Importiert wird aus dem Quellmodul – lists und apply
  # zusammen ergeben also keinen Konflikt.
  @reexports %{
    # wie Scryers library(iso_ext)
    "iso_ext" =>
      Map.merge(@home_reexports["iso_ext"], %{
        {"call_cleanup", 2} => "system",
        {"call_residue_vars", 2} => "system",
        {"copy_term", 3} => "system",
        {"bb_get", 2} => "blackboard",
        {"bb_put", 2} => "blackboard"
      }),
    # Übergang: alles, was bisher ohne Import sichtbar war
    "swi" =>
      @home_reexports
      |> Map.values()
      |> Enum.reduce(&Map.merge/2),
    "lists" =>
      Map.new(
        for(n <- 2..8, do: {{"maplist", n}, "apply"}) ++
          [{{"include", 3}, "apply"}, {{"exclude", 3}, "apply"}, {{"partition", 4}, "apply"}]
      ),
    # wie SICStus' library(fastrw) (die Prädikate sind eingebaut, wie in SWI)
    "fastrw" => @home_reexports["fastrw"],
    # wie SICStus' library(between)
    "between" => %{
      {"between", 3} => "system",
      {"repeat", 1} => "system",
      {"numlist", 2} => "lists",
      {"numlist", 3} => "lists"
    }
  }

  for {m, re} <- @reexports, {key, src} <- re do
    known =
      if src == "system",
        do: MapSet.member?(@system_keys, key),
        else: MapSet.member?(Map.fetch!(@exports, src), key)

    unless known, do: raise("Re-Export #{m}: #{inspect(key)} nicht in #{src}")
  end

  # (auch Module, die nur weitergeben, z. B. fastrw)
  @exports_all Map.new(Enum.uniq(Map.keys(@exports) ++ Map.keys(@reexports)), fn m ->
                 {m,
                  MapSet.union(
                    Map.get(@exports, m, MapSet.new()),
                    MapSet.new(Map.keys(Map.get(@reexports, m, %{})))
                  )}
               end)

  @doc "Exporte eines Bibliotheksmoduls (MapSet von {name, arity}) oder nil"
  def exports(module), do: Map.get(@exports_all, module)

  @doc """
  Modul, aus dem `name/arity` beim Import aus `module` tatsächlich kommt:
  das Quellmodul eines Re-Exports, sonst `module`.
  """
  def source(module, name, arity),
    do: get_in(@reexports, [module, {name, arity}]) || module

  @doc "Alle Builtins eines Moduls als `{name, arity}`, sortiert"
  def keys(module),
    do: for({^module, n, a} <- Map.keys(@all), do: {n, a}) |> Enum.sort()
end
