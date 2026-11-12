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
    * Heimat-Bibliotheken (`@homes`: `iso_ext`, `between`, `terms`, `fastrw`, `swi`)
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
    PrologEx.Builtins.ListSicstus,
    PrologEx.Builtins.Order,
    PrologEx.Builtins.System,
    PrologEx.Builtins.Database,
    PrologEx.Builtins.Modules,
    PrologEx.Builtins.Coroutining,
    PrologEx.Builtins.Random,
    PrologEx.Builtins.Atts,
    PrologEx.Builtins.Atoms,
    PrologEx.Builtins.Swi,
    PrologEx.Builtins.Rlimit,
    PrologEx.Builtins.Blackboard,
    PrologEx.Builtins.Gensym,
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
    PrologEx.Builtins.BytesLazy,
    PrologEx.Builtins.Files,
    PrologEx.Builtins.Charsio,
    PrologEx.Builtins.ScryerPrims,
    PrologEx.Builtins.Http,
    PrologEx.Builtins.AggregatePrims,
    PrologEx.Builtins.Ordsets,
    PrologEx.Builtins.Assoc,
    PrologEx.Builtins.Bytes,
    PrologEx.Builtins.Ugraphs,
    PrologEx.Builtins.Wgraphs,
    PrologEx.Builtins.Heaps,
    PrologEx.Builtins.RbtreePrims,
    PrologEx.Builtins.ClpbPrims,
    PrologEx.Builtins.ClpzPrims,
    PrologEx.Builtins.Pcre,
    PrologEx.Builtins.Memo,
    PrologEx.Builtins.Tabling,
    PrologEx.Builtins.SideEffects,
    PrologEx.Builtins.Concurrent,
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

  # -->/2 ist kein Prädikat, aber reserviert (wie die Steuerkonstrukte):
  # asserta((a-->b)) gibt permission_error(modify, static_procedure, ...),
  # clause/2 permission_error(access, private_procedure, ...) – der Aufruf
  # existence_error (Neumerkels phrase-Tabelle, #24–26)
  @reserved [{"-->", 2}]

  # Heimat eingebauter Prädikate, die nicht zu ISO gehören und die auch
  # SICStus nicht eingebaut hat: sichtbar erst nach dem Import der Bibliothek
  # (in den Modulen des Systems und mit dem Flag swi_compat immer). Die
  # Implementierung bleibt in system bzw. in der Maschine. library(swi) ist
  # der Übergang für das, was (noch) keine inhaltliche Heimat hat.
  @homes (for {lib, keys} <- [
                {"iso_ext", ~w(forall/2 succ/2 setup_call_cleanup/3 call_nth/2 countall/2
                    call_with_inference_limit/3 atomic_concat/3 evaluable_property/2
                    cached_is/2)},
                {"between", ~w(between/3 repeat/1)},
                {"terms", ~w(term_hash/2 term_hash/4 term_size/2)},
                {"fastrw", ~w(fast_read/1 fast_read/2 fast_write/1 fast_write/2)},
                {"swi", ~w(ignore/1 not/1 *->/2 plus/3 atomic_list_concat/2 atomic_list_concat/3
                    atom_number/2 term_to_atom/2 read_term_from_atom/3 =@=/2 \\=@=/2
                    term_attvars/2 findnsols/4 findnsols/5 call_with_depth_limit/3
                    exists_file/1 exists_directory/1 delete_file/1 fast_term_serialized/2
                    time/1 statistics/0 style_check/1 expand_goal/2 dcg_translate_rule/2
                    strip_module/3 upcase_atom/2 downcase_atom/2 writeln/1 writeln/2 tab/1
                    tab/2 with_output_to/2 select/4 selectchk/3 selectchk/4 flatten/2
                    predsort/3 sort/4 code_type/2 nb_setval/2 nb_getval/2 b_setval/2
                    b_getval/2 nb_current/2 term_variables/3 string/1 garbage_collect/0
                    get_time/1 cyclic_term/1)}
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

  # Builtins mit Wirkung (für call_with_no_side_effects/1, super-strikt):
  # Kategorie je {Modul, Name, Stelligkeit}. Lesen von Zustand ohne ihn zu
  # ändern ist keine Wirkung (clause/2, current_op/3, Flags lesen, get_time/1,
  # Dateien abfragen); Lesen aus einem Stream schon (es verbraucht Eingabe),
  # ebenso jeder Stream-Verkehr, auch mit Speicher-Streams (with_output_to/2,
  # format/3). Steuerkonstrukte, die ihren Zustand selbst wieder abräumen
  # (Grenzen, call_residue_vars/2), und interne Caches zählen nicht.
  @effect_names %{
    "database" =>
      ~w(abolish/1 assert/1 asserta/1 assertz/1 retract/1 retractall/1 consult/1 dynamic/1
         ensure_loaded/1 use_module/1 use_module/2 meta_predicate/1 $expansion_hooks/0
         $expansion_hooks/2),
    "state" => ~w(b_setval/2 nb_setval/2 char_conversion/2 op/3 set_prolog_flag/2 style_check/1),
    "io" => ~w(at_end_of_stream/0 at_end_of_stream/1 close/1 close/2 flush_output/0 flush_output/1
         format/1 format/2 format/3 get_byte/1 get_byte/2 get_char/1 get_char/2 get_code/1
         get_code/2 peek_byte/1 peek_byte/2 peek_char/1 peek_char/2 peek_code/1 peek_code/2
         put_byte/1 put_byte/2 put_char/1 put_char/2 put_code/1 put_code/2 nl/0 nl/1 print/1
         print/2 read/1 read/2 read_term/2 read_term/3 open/3 open/4 set_input/1 set_output/1
         set_stream_position/2 tab/1 tab/2 write/1 write/2 write_canonical/1 write_canonical/2
         write_term/2 write_term/3 writeln/1 writeln/2 writeq/1 writeq/2 listing/0 listing/1
         statistics/0 with_output_to/2 fast_read/1 fast_read/2 fast_write/1 fast_write/2
         $get_n_chars/3 $chars_input/2 $lazy_block/5 $lazy_position/4 $lazy_start/2
         $wot_close/3 $wot_open/2 $wot_restore/2 $wot_sink/1 $http_put_byte_chars/2),
    "external" => ~w(halt/0 halt/1 delete_file/1 $shell/2 $setenv/2 $unsetenv/1 $process_create/8
         $process_kill/1 $process_release/1 $process_wait/3 $http_accept/7 $http_answer/4
         $http_answer/5 $http_listen/5 $http_listen_stop/1 $http_open/7 $http_send_file/4),
    "memo" => ~w($memo_lookup/3 $memo_store/2 $memo_drop/1 $memo_abolish/1),
    "tabling" => ~w($tbl_lookup/4 $tbl_abolish/1),
    "random" => ~w($clpb_random_bindings/2)
  }

  @effect_modules %{
    "files" =>
      {"external",
       ~w(delete_directory/1 delete_file/1 file_copy/2 make_directory/1 make_directory_path/1
          rename_file/2 working_directory/2)},
    "sockets" =>
      {"external",
       ~w(socket_client_open/3 socket_select/7 socket_server_accept/4 socket_server_close/1
          socket_server_open/2 socket_server_open/3)},
    "random" =>
      {"random", ~w(maybe/0 random/1 random/3 random_between/3 random_integer/3 random_member/2
          random_permutation/2 random_select/3 random_subseq/3 randseq/3 randset/3
          set_random/1 setrand/1)},
    "gensym" => {"state", ~w(gensym/2 reset_gensym/0 reset_gensym/1)},
    "blackboard" => {"state", ~w(bb_b_put/2 bb_delete/2 bb_put/2 bb_update/3)},
    "rlimit" => {"external", ~w(rlimit/3)},
    "bytes" => {"io", ~w(read_file_to_bytes/2 write_bytes/2 get_bytes/3)}
  }

  pi = fn s ->
    [n, a] = String.split(s, ~r{/(?=\d+$)})
    {n, String.to_integer(a)}
  end

  @effects Map.new(
             for({cat, names} <- @effect_names, s <- names, do: {{"system", pi.(s)}, cat}) ++
               for({m, {cat, names}} <- @effect_modules, s <- names, do: {{m, pi.(s)}, cat})
           )
           |> Map.new(fn {{m, {n, a}}, cat} -> {{m, n, a}, cat} end)

  for {{m, n, a}, _} <- @effects,
      not (Map.has_key?(@table, {m, n, a}) or Map.has_key?(@library, {m, n, a})),
      do: raise("Wirkung für unbekanntes Builtin #{m}:#{n}/#{a}")

  # Builtins mit Wirkung: Art {:fx, :det | :nondet, Kategorie} (die Maschine
  # prüft vor dem Aufruf, siehe PrologEx.Effects.nse_check!/5)
  @all (for {k, e} <- Map.merge(@table, @library), into: %{} do
          case {e, Map.get(@effects, k)} do
            {{kind, fun, prot}, cat} when kind in [:det, :nondet] and cat != nil ->
              {k, {{:fx, kind, cat}, fun, prot}}

            _ ->
              {k, e}
          end
        end)

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
             |> MapSet.union(MapSet.new(@engine ++ @reserved))
             |> MapSet.difference(MapSet.new(Map.keys(@homes)))

  @system_keys (for({"system", n, a} <- Map.keys(@all), do: {n, a}) ++ @engine ++ @reserved)
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

  @doc """
  `{:det | :nondet, fun, protected?}`, `{{:fx, :det | :nondet, Kategorie}, fun,
  protected?}` (mit Wirkung), `{:prolog, pred, protected?}` oder nil
  """
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
  # (auch in Unterverzeichnissen: library(http/http_server) heißt http_server)
  @pl_libraries Path.wildcard(Path.join([__DIR__, "..", "..", "priv", "library", "**", "*.pl"]))
                |> Enum.map(&Path.basename(&1, ".pl"))

  # dazu die Modulnamen aus :- module(Name, ...) (library(dcg/bytes) heißt
  # dcg_bytes)
  @pl_module_names for f <-
                         Path.wildcard(
                           Path.join([__DIR__, "..", "..", "priv", "library", "**", "*.pl"])
                         ),
                       [_, m] <- [
                         Regex.run(~r/^:-\s*module\(\s*([a-z][a-zA-Z0-9_]*)/m, File.read!(f))
                       ],
                       do: m

  @system_modules MapSet.new(["system" | Map.keys(@exports)] ++ @pl_libraries ++ @pl_module_names)

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
        {"bb_get", 2} => "blackboard",
        {"bb_put", 2} => "blackboard",
        {"bb_b_put", 2} => "blackboard"
      }),
    # Übergang: alles, was bisher ohne Import sichtbar war
    "swi" =>
      @home_reexports
      |> Map.values()
      |> Enum.reduce(&Map.merge/2),
    "lists" =>
      Map.new(
        for(n <- 2..8, do: {{"maplist", n}, "apply"}) ++
          for(n <- 4..6, do: {{"foldl", n}, "apply"}) ++
          [{{"include", 3}, "apply"}, {{"exclude", 3}, "apply"}, {{"partition", 4}, "apply"}]
      ),
    # wie SICStus' library(fastrw) (die Prädikate sind eingebaut, wie in SWI)
    "fastrw" => @home_reexports["fastrw"],
    # wie Scryers library(terms) (eingebaut), dazu term_hash/2,4 und
    # term_size/2 wie SWI
    "terms" => Map.put(@home_reexports["terms"], {"numbervars", 3}, "system"),
    "freeze" => %{{"freeze", 2} => "system"},
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
