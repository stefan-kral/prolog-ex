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
      `initialization/1`, `discontiguous/1`, `multifile/1`. `op/3` wirkt
      schon beim Einlesen (gprolog), Fehler meldet die Direktive.
    * `initialization(G)` läuft am Ende des Ladevorgangs.
    * Expansion (siehe `PrologEx.Builtins.Expansion`): gibt es im Quellmodul
      oder in `user` einen Hook `term_expansion/2`, geht jeder gelesene Term
      (und zum Schluss `end_of_file`) erst durch ihn; `goal_expansion/2`
      expandiert danach jeden Klauselrumpf und jede Direktive. Ein Hook
      gilt ab der Klausel nach seiner Definition.

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
      # multifile: Klauseln aus anderen Dateien, die beim ersten Auftreten
      # in dieser Datei schon da waren – sie bleiben vor den neuen stehen
      mf_base: %{},
      # bedingte Übersetzung: Stapel aus :on, :off (Bedingung noch offen),
      # :done (ein Zweig war schon dran), :dead (umgebender Zweig aus)
      cond: [],
      msgs: [],
      init: [],
      module: into || "user",
      into: into,
      declared: nil,
      file: Keyword.get(opts, :file)
    }

    st = st |> feed.() |> eof_expansion() |> flush()

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

  defp item({:error, _msg}, %{cond: [top | _]} = st) when top != :on, do: st
  defp item({:error, msg}, st), do: msg(st, msg)

  defp item({:term, t, _names} = it, st) do
    case conditional(PrologEx.unmark_top(t), st) do
      {:handled, st} -> st
      :skip -> st
      :go -> expand_item(it, st)
    end
  end

  # :- if(C), :- elif(C), :- else, :- endif (wie SWI, SICStus, GNU):
  # zuerst ausgewertet, vor term_expansion; in einem inaktiven Zweig wird
  # alles übersprungen, auch Direktiven
  defp conditional({:struct, ":-", [d]}, st) do
    active = Enum.all?(st.cond, &(&1 == :on))

    case PrologEx.unmark_top(d) do
      {:struct, "if", [c]} ->
        top =
          cond do
            not active -> :dead
            condition?(c, st) -> :on
            true -> :off
          end

        {:handled, %{st | cond: [top | st.cond]}}

      {:struct, "elif", [c]} ->
        case st.cond do
          [top | rest] ->
            top =
              cond do
                top in [:on, :done] -> :done
                top == :dead -> :dead
                condition?(c, %{st | cond: rest}) -> :on
                true -> :off
              end

            {:handled, %{st | cond: [top | rest]}}

          [] ->
            {:handled, msg(st, "Fehler: elif ohne if")}
        end

      {:atom, "else"} ->
        case st.cond do
          [top | rest] ->
            top = %{off: :on, on: :done, done: :done, dead: :dead}[top]
            {:handled, %{st | cond: [top | rest]}}

          [] ->
            {:handled, msg(st, "Fehler: else ohne if")}
        end

      {:atom, "endif"} ->
        case st.cond do
          [_ | rest] -> {:handled, %{st | cond: rest}}
          [] -> {:handled, msg(st, "Fehler: endif ohne if")}
        end

      _ ->
        if active, do: :go, else: :skip
    end
  end

  defp conditional(_t, st), do: if(Enum.all?(st.cond, &(&1 == :on)), do: :go, else: :skip)

  # Bedingung als Anfrage (sieht das bisher Geladene); Fehler: Meldung, falsch
  defp condition?(c, st) do
    st = flush(st)
    PrologEx.put_db(st.db)
    [_] = Enum.take(PrologEx.query(st.db, c, module: st.module), 1)
    true
  rescue
    _ -> false
  end

  defp expand_item({:term, t, _names}, st) do
    {st, hook?} = hook?(st, "term_expansion")

    if hook? do
      case expand(st, "$term_hook", [PrologEx.unmark(t), a(st.module)], "term_expansion") do
        {st, nil} -> plain_item(t, st)
        {st, x} -> x |> expansion_items() |> Enum.reduce(st, &plain_item/2)
      end
    else
      plain_item(t, st)
    end
  end

  # Ergebnis von term_expansion: Liste von Termen oder ein Term
  defp expansion_items(x) do
    case PrologEx.unmark(x) do
      l when is_list(l) -> prolog_list(l)
      t -> [t]
    end
  end

  # zum Schluss: term_expansion(end_of_file, X) (wie SWI); X ohne end_of_file
  defp eof_expansion(st) do
    {st, hook?} = hook?(st, "term_expansion")

    with true <- hook?,
         {st, x} when x != nil <-
           expand(st, "$term_hook", [a("end_of_file"), a(st.module)], "term_expansion") do
      x
      |> expansion_items()
      |> Enum.reject(&(&1 == a("end_of_file")))
      |> Enum.reduce(st, &plain_item/2)
    else
      false -> st
      {st, nil} -> st
    end
  end

  # Ist ein Hook name/2 im Quellmodul oder in user definiert? Steht er noch
  # ungeladen in pending, wird vorher geladen (damit er schon für den
  # nächsten Term gilt).
  defp hook?(st, name) do
    keys = Enum.uniq([{st.module, name, 2}, {"user", name, 2}])

    st = if Enum.any?(keys, &MapSet.member?(st.dirty, &1)), do: flush(st), else: st
    {st, Enum.any?(keys, &Map.has_key?(st.db, &1))}
  end

  # Expansion als Anfrage: helper(Args..., X); Ergebnis X (frische
  # Variablen umbenannt) oder nil, wenn kein Hook gelingt. Fehler werden
  # gemeldet, der Term bleibt dann unverändert.
  defp expand(st, helper, args, what) do
    out = {:var, "$expansion"}
    PrologEx.put_db(st.db)

    result =
      try do
        case Enum.take(PrologEx.query(st.db, mk(helper, args ++ [out]), module: st.module), 1) do
          [ans] -> {:ok, rename_fresh(Map.fetch!(ans, "$expansion"))}
          [] -> {:ok, nil}
        end
      rescue
        e in [RuntimeError, PrologEx.Error] -> {:error, Exception.message(e)}
      end

    st = %{st | db: PrologEx.current_db()}

    case result do
      {:ok, x} -> {st, x}
      {:error, m} -> {msg(st, "Fehler in #{what}: #{m}"), nil}
    end
  end

  # frische Variablen einer Antwort ({:var, 0}, ...) eindeutig benennen
  defp rename_fresh(t) do
    {t, _} = rename(t, %{})
    t
  end

  defp rename({:var, n}, m) when is_integer(n) do
    case m do
      %{^n => v} ->
        {v, m}

      _ ->
        v = {:var, "_X#{System.unique_integer([:positive])}"}
        {v, Map.put(m, n, v)}
    end
  end

  defp rename({:struct, f, args}, m) do
    {args, m} = Enum.map_reduce(args, m, &rename/2)
    {{:struct, f, args}, m}
  end

  defp rename([h | t], m) do
    {h, m} = rename(h, m)
    {t, m} = rename(t, m)
    {[h | t], m}
  end

  defp rename(t, m), do: {t, m}

  defp plain_item(t, st) do
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
    {st, hook?} = hook?(st, "goal_expansion")

    {head, body, st} =
      if hook? do
        case expand(
               st,
               "$expand_clause",
               [mk(":-", [PrologEx.unmark(head), PrologEx.unmark(body)]), a(st.module)],
               "goal_expansion"
             ) do
          {st, {:struct, ":-", [h, b]}} -> {h, b, st}
          {st, _} -> {head, body, st}
        end
      else
        {head, body, st}
      end

    store_clause({head, body}, st)
  end

  defp store_clause({head, body}, st) do
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
    st = if PrologEx.has_property?(st.db, pkey, :multifile), do: remember_base(st, pkey), else: st

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
        clauses =
          Enum.flat_map(preds, fn {key, cls} ->
            Map.get(st.mf_base, key, []) ++ Enum.reverse(cls)
          end)

        db = PrologEx.consult(db, clauses, m)
        Enum.reduce(preds, db, fn {{m, n, ar}, _}, db -> Map.delete(db, {:import, m, n, ar}) end)
      end)

    %{st | db: db, dirty: MapSet.new()}
  end

  # multifile: beim ersten Auftreten in dieser Datei die vorhandenen
  # Klauseln merken (aus anderen Dateien), damit flush sie nicht ersetzt
  defp remember_base(st, key) do
    if Map.has_key?(st.mf_base, key) or Map.has_key?(st.pending, key) do
      st
    else
      base =
        case Map.fetch(st.db, key) do
          {:ok, {:pred, _, _, _, _} = pred} -> PrologEx.pred_source(pred)
          {:ok, pred} when not is_nil(pred) -> PrologEx.pred_source(pred)
          _ -> []
        end

      %{st | mf_base: Map.put(st.mf_base, key, base)}
    end
  end

  defp directive({:struct, "module", [{:atom, m}, exports]}, st) do
    st = flush(st)

    # op(P, T, N) in der Exportliste: gprolog hat sie beim Lesen gesetzt,
    # der Writer braucht sie auch
    for {:struct, "op", [p, t, n]} <- prolog_list(exports) |> Enum.map(&PrologEx.unmark/1),
        do: PrologEx.Builtins.Operators.mirror(p, t, n)

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

  defp directive({:struct, "attribute", [spec]}, st) do
    %{st | db: PrologEx.Builtins.Atts.declare(st.db, st.module, spec)}
  end

  defp directive({:struct, "meta_predicate", [spec]}, st) do
    %{st | db: PrologEx.Builtins.Modules.declare_meta(st.db, spec, st.module)}
  end

  # :- include(F): die Terme von F stehen an dieser Stelle (relativ zur
  # ladenden Datei, .pl darf fehlen)
  defp directive({:struct, "include", [f]}, st) do
    path = resolve_path(PrologEx.Builtins.Modules.file_name(f))

    case File.read(path) do
      {:ok, text} ->
        items = Reader.read_terms(Reader.current(), text)
        outer = Process.put(:prolog_ex_load_dir, Path.dirname(Path.expand(path)))

        try do
          Enum.reduce(items, st, &item/2)
        after
          Process.put(:prolog_ex_load_dir, outer)
        end

      {:error, _} ->
        msg(st, "Fehler: include(#{PrologEx.format(f, quoted: true)}): Datei nicht gefunden")
    end
  end

  defp directive({:struct, "initialization", [g | _]}, st),
    do: %{st | init: [{g, st.module} | st.init]}

  # op/3 hat gprolog beim Lesen schon ausgeführt (für die folgenden
  # Terme); hier noch einmal über op/3, damit Fehler gemeldet werden
  defp directive({:struct, kind, [spec]}, st) when kind in ["discontiguous", "multifile"] do
    k = String.to_atom(kind)

    Enum.reduce(PrologEx.Builtins.Modules.indicators(spec, st.module), st, fn key, st ->
      st = if k == :multifile, do: remember_base(st, key), else: st
      %{st | db: PrologEx.declare_property(st.db, key, k)}
    end)
  end

  defp directive(g, st) do
    st = flush(st)
    {st, hook?} = hook?(st, "goal_expansion")

    {st, g} =
      if hook? do
        case expand(st, "$expand_directive", [g, a(st.module)], "goal_expansion") do
          {st, nil} -> {st, g}
          {st, g2} -> {st, g2}
        end
      else
        {st, g}
      end

    run_directive(g, st, "Direktive")
  end

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
