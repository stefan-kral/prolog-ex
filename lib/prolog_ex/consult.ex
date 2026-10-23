defmodule PrologEx.Consult do
  @moduledoc """
  Lädt gelesene Terme (siehe `PrologEx.Reader`) in eine Datenbank.

    * Klauseln (`H :- B`, Fakten) und DCG-Regeln (`H --> B`) werden pro
      Prädikat gesammelt. Ein Prädikat, das in einem Ladevorgang vorkommt,
      ERSETZT seine bisherige Definition (Reconsult); alle Klauseln
      desselben Ladevorgangs werden zusammengefasst.
    * Klauseln gehören zum aktuellen Quellmodul (`user`, oder das Modul aus
      `:- module(M, Exporte)`). `M:Kopf :- Rumpf` definiert in M; der Rumpf
      läuft dann im Quellmodul (wie SWI).
    * Direktiven `:- G` werden an ihrer Stelle im Quellmodul ausgeführt;
      vorher wird kompiliert, was bis dahin geladen ist. Besonders
      behandelt: `module/2`, `dynamic/1`, `meta_predicate/1`,
      `initialization/1`, `op/3` (das Einlesen hat gprolog schon erledigt),
      `discontiguous/1`, `multifile/1`.
    * `initialization(G)` läuft am Ende des Ladevorgangs.

  Optionen: `file:` (Pfad, für Meldungen und module/2), `into:` (Modul,
  in das geladen wird und das die Exporte eines Moduls importiert;
  Standard `"user"`; `nil`: in user laden, nichts importieren).

  Ergebnis: `{db, meldungen}`; Meldungen sind Strings (Warnungen/Fehler).
  """

  alias PrologEx.{Compiler, DCG, Reader}
  import PrologEx, only: [a: 1, mk: 2]

  def load(db, items, opts \\ []) do
    {db, msgs, _module} = load_info(db, items, opts)
    {db, msgs}
  end

  @doc "Wie load/3, liefert zusätzlich das mit module/2 deklarierte Modul (oder nil)."
  def load_info(db, items, opts \\ []),
    do: run_load(db, opts, fn st -> Enum.reduce(items, st, &item/2) end)

  # feed: liest die Terme ein (alle auf einmal oder schrittweise)
  defp run_load(db, opts, feed) do
    into = Keyword.get(opts, :into, "user")

    st = %{
      db: db,
      pending: %{},
      # seit dem letzten flush geänderte Prädikate
      dirty: MapSet.new(),
      msgs: [],
      init: [],
      module: into || "user",
      into: into,
      declared: nil,
      file: Keyword.get(opts, :file)
    }

    st = st |> feed.() |> flush()

    st =
      Enum.reduce(Enum.reverse(st.init), st, fn {g, m}, st ->
        run_directive(g, %{st | module: m}, "initialization")
      end)

    {st.db, Enum.reverse(st.msgs), st.declared}
  end

  @doc """
  Datei laden (consult/1, use_module/1, [datei]): `path` ohne oder mit
  `.pl`. Arbeitet auf der Sitzungsdatenbank und gibt Meldungen auf stderr
  aus. Ergebnis: `{:ok, modul_oder_nil}`; fehlt die Datei:
  existence_error(source_sink, Pfad).
  """
  def load_file(path, opts \\ []) do
    path = resolve_path(path)

    full = Path.expand(path)
    reader = Reader.current()

    # schrittweise lesen: nach jeder Direktive (use_module, op, ...) gilt
    # die geänderte Syntax schon für den Rest der Datei
    case File.regular?(full) and Reader.open_file(reader, full) do
      :ok ->
        # relative Pfade in der Datei (use_module, consult) gelten ab ihrem Ordner
        outer = Process.put(:prolog_ex_load_dir, Path.dirname(full))

        {db, msgs, module} =
          try do
            run_load(PrologEx.current_db(), [file: full] ++ opts, &read_chunks(reader, &1))
          after
            Process.put(:prolog_ex_load_dir, outer)
          end

        PrologEx.put_db(Map.put(db, {:file, full}, module))
        Enum.each(msgs, &IO.puts(:stderr, "#{path}: #{&1}"))
        {:ok, module}

      _ ->
        PrologEx.Error.existence!("source_sink", a(path))
    end
  end

  defp read_chunks(reader, st) do
    {items, status} = Reader.next_chunk(reader)
    st = Enum.reduce(items, st, &item/2)
    if status == :pause, do: read_chunks(reader, st), else: st
  end

  @doc "Ist die Datei schon geladen? Dann `{:ok, modul_oder_nil}`, sonst :error."
  def loaded(path) do
    Map.fetch(PrologEx.current_db(), {:file, Path.expand(resolve_path(path))})
  end

  defp resolve_path(path) do
    path =
      case Process.get(:prolog_ex_load_dir) do
        dir when is_binary(dir) -> Path.expand(path, dir)
        _ -> path
      end

    if File.exists?(path) or Path.extname(path) != "", do: path, else: path <> ".pl"
  end

  # ---------------------------------------------------------------------

  defp item({:error, msg}, st), do: msg(st, msg)

  defp item({:term, t, _names}, st) do
    case PrologEx.unmark_top(t) do
      {:struct, ":-", [d]} -> directive(PrologEx.unmark(d), st)
      {:struct, "?-", [d]} -> directive(PrologEx.unmark(d), st)
      {:struct, "-->", [h, b]} -> add_clause(DCG.rule(h, b), st)
      {:struct, ":-", [h, b]} -> add_clause({h, b}, st)
      fact -> add_clause({fact, a("true")}, st)
    end
  rescue
    e in [RuntimeError, PrologEx.Error] -> msg(st, "Fehler: #{Exception.message(e)}")
  end

  defp add_clause({head, body}, st) do
    # M:Kopf – Klausel für Modul M, Rumpf läuft im Quellmodul
    {m, head, body} =
      case PrologEx.unmark(head) do
        {:struct, ":", [{:atom, m}, h]} when m != st.module ->
          {m, h, mk(":", [a(st.module), body])}

        {:struct, ":", [{:atom, _}, h]} ->
          {st.module, h, body}

        h ->
          {st.module, h, body}
      end

    {name, arity} = key = Compiler.key(head)

    if PrologEx.Builtins.protected?(key) do
      PrologEx.Error.permission!(
        "modify",
        "static_procedure",
        PrologEx.Error.indicator(name, arity)
      )
    end

    pkey = {m, name, arity}

    %{
      st
      | pending: Map.update(st.pending, pkey, [{head, body}], &[{head, body} | &1]),
        dirty: MapSet.put(st.dirty, pkey)
    }
  end

  # Alles bisher Gesammelte kompilieren (pending bleibt erhalten, damit
  # spätere Klauseln desselben Prädikats angehängt statt ersetzt werden).
  # Eine lokale Definition ersetzt einen Import (wie SWI).
  defp flush(st) do
    db =
      st.dirty
      |> Enum.map(&{&1, Map.fetch!(st.pending, &1)})
      |> Enum.group_by(fn {{m, _, _}, _} -> m end)
      |> Enum.reduce(st.db, fn {m, preds}, db ->
        clauses = Enum.flat_map(preds, fn {_, cls} -> Enum.reverse(cls) end)
        db = PrologEx.consult(db, clauses, m)
        Enum.reduce(preds, db, fn {{m, n, ar}, _}, db -> Map.delete(db, {:import, m, n, ar}) end)
      end)

    %{st | db: db, dirty: MapSet.new()}
  end

  defp directive({:struct, "module", [{:atom, m}, exports]}, st) do
    st = flush(st)
    keys = export_keys(exports)
    db = Map.put(st.db, {:module, m}, %{exports: MapSet.new(keys), file: st.file})
    st = %{st | db: db, module: m, declared: m}
    import_into(st, m, keys, st.into)
  end

  defp directive({:struct, "dynamic", [spec]}, st) do
    Enum.reduce(PrologEx.Builtins.Modules.indicators(spec, st.module), st, fn key, st ->
      %{st | db: PrologEx.declare(st.db, key)}
    end)
  end

  defp directive({:struct, "meta_predicate", [spec]}, st) do
    %{st | db: PrologEx.Builtins.Modules.declare_meta(st.db, spec, st.module)}
  end

  defp directive({:struct, "initialization", [g | _]}, st),
    do: %{st | init: [{g, st.module} | st.init]}

  defp directive({:struct, "op", [_, _, _]}, st), do: st
  defp directive({:struct, "discontiguous", [_]}, st), do: st
  defp directive({:struct, "multifile", [_]}, st), do: st
  defp directive(g, st), do: run_directive(g, flush(st), "Direktive")

  defp run_directive(g, st, what) do
    # Direktiven sehen und ändern die Datenbank (assert, use_module, ...)
    PrologEx.put_db(st.db)
    result = Enum.take(PrologEx.query(st.db, g, module: st.module), 1)
    st = %{st | db: PrologEx.current_db()}

    case result do
      [_] -> st
      [] -> msg(st, "Warnung: #{what} gescheitert: #{PrologEx.format(g)}")
    end
  rescue
    e in [RuntimeError, PrologEx.Error] ->
      msg(st, "Fehler in #{what} #{PrologEx.format(g)}: #{Exception.message(e)}")
  end

  # Exporte von m in das Modul into importieren (lokale Definitionen dort
  # gehen vor: dann eine Warnung, wie SWI)
  defp import_into(st, _m, _keys, nil), do: st
  defp import_into(st, m, _keys, m), do: st

  defp import_into(st, m, keys, into) do
    Enum.reduce(keys, st, fn {n, ar}, st ->
      case PrologEx.Builtins.Modules.import_check(st.db, m, into, n, ar) do
        :ok -> %{st | db: Map.put(st.db, {:import, into, n, ar}, m)}
        :same -> st
        {:warn, text} -> msg(st, "Warnung: " <> text)
      end
    end)
  end

  # [name/arity, name//arity, op(P, T, N), ...]
  defp export_keys(list) do
    for e <- prolog_list(list), k = export_key(e), k != nil, do: k
  end

  defp export_key({:struct, "/", [{:atom, n}, ar]}) when is_integer(ar), do: {n, ar}
  defp export_key({:struct, "//", [{:atom, n}, ar]}) when is_integer(ar), do: {n, ar + 2}
  defp export_key({:struct, "op", [_, _, _]}), do: nil
  defp export_key(other), do: PrologEx.Error.type!("predicate_indicator", other)

  defp prolog_list([]), do: []
  defp prolog_list([h | t]), do: [h | prolog_list(t)]
  defp prolog_list(other), do: PrologEx.Error.type!("list", other)

  defp msg(st, m), do: %{st | msgs: [m | st.msgs]}
end
