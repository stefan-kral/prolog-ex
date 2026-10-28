defmodule PrologEx.Builtins.OS do
  @moduledoc """
  Grundlagen für `library(os)` und `library(process)` (priv/library/os.pl,
  process.pl, aus Scryer Prolog): die `$`-Prädikate, die dort die
  Scryer-Maschine liefert. Die Argumente sind schon geprüft (in Prolog).

  ## Prozesse

  Ein Prozess läuft über einen Port der BEAM: `/bin/sh -c 'exec "$@" ...'`
  mit den Umleitungen als Shell-Umleitungen, dann ersetzt das Programm die
  Shell (dieselbe Prozessnummer). `std` erbt die Ein-/Ausgabe der BEAM,
  `null` ist `/dev/null`, `file(P)` die Datei, `pipe(S)` eine benannte Pipe
  (mkfifo), deren anderes Ende S ist: schreibend ungepuffert, lesend über
  einen Port mit cat (`PrologEx.Stream.open_pipe_reader/1`), damit Daten
  ankommen, sobald sie da sind. Die Pipes werden in der Reihenfolge
  geöffnet, in der die Shell sie öffnet (stdin, stdout, stderr), und
  gelöscht, sobald beide Enden offen sind.

  Der Rückgabewert kommt als `exit_status` des Ports. Die BEAM meldet ein
  durch ein Signal beendetes Programm wie `exit(128 + Signal)`; nur wenn
  `process_kill/1` es beendet hat, heißt das Ergebnis `killed(9)` wie bei
  Scryer.

  Prozess-Handles sind `'$process'(N)`; die Tabelle liegt im
  Prozess-Wörterbuch der Sitzung (dort kommen auch die Nachrichten des
  Ports an).
  """
  use PrologEx.Builtin
  alias PrologEx.{Effects, Error}
  alias PrologEx.Stream, as: S

  # --- Hilfen ----------------------------------------------------------------

  defp text(t, s) do
    t
    |> PrologEx.Builtins.Lists.items(s)
    |> Enum.map_join(fn x ->
      {:atom, c} = PrologEx.walk(x, s)
      c
    end)
  end

  defp chars(text), do: list(for(<<c::utf8 <- text>>, do: a(<<c::utf8>>)))

  # --- library(os) -------------------------------------------------------

  # Namen mit "=" (Scryers Prüfung lässt es durch) gibt es nicht: getenv
  # scheitert, setenv/unsetenv: domain_error(env_var, Name) wie für andere
  # unzulässige Namen
  defbuiltin "$getenv", [k, v] do
    case env_name(k, subst()) do
      :invalid ->
        :fail

      name ->
        case System.get_env(name) do
          nil -> :fail
          value -> {:unify, [{v, chars(value)}]}
        end
    end
  end

  defbuiltin "$setenv", [k, v] do
    name = env_name!(k, subst())
    Effects.external!()
    System.put_env(name, text(v, subst()))
    :ok
  end

  defbuiltin "$unsetenv", [k] do
    name = env_name!(k, subst())
    Effects.external!()
    System.delete_env(name)
    :ok
  end

  defp env_name(k, s) do
    name = text(k, s)
    if String.contains?(name, "="), do: :invalid, else: name
  end

  defp env_name!(k, s) do
    case env_name(k, s) do
      :invalid ->
        Error.throw!(
          mk("error", [mk("domain_error", [a("env_var"), PrologEx.resolve(k, s)]), a("os")])
        )

      name ->
        name
    end
  end

  # wie Scryer: $SHELL -c Kommando (sonst /bin/sh), Ein-/Ausgabe geerbt;
  # Status der Rückgabewert (durch ein Signal beendet: 128 + Signal)
  defbuiltin "$shell", [cmd, status] do
    Effects.external!()
    shell = System.get_env("SHELL") || "/bin/sh"

    port =
      Port.open({:spawn_executable, shell}, [
        :nouse_stdio,
        :exit_status,
        args: ["-c", text(cmd, subst())]
      ])

    receive do
      {^port, {:exit_status, n}} -> {:unify, [{status, n}]}
    end
  end

  defbuiltin "$pid", [p] do
    {:unify, [{p, String.to_integer(System.pid())}]}
  end

  # Argumente wie Scryers raw_argv: Programmname, dann die Argumente
  defbuiltin "$argv", [l] do
    args = ["prolog_ex" | Application.get_env(:prolog_ex, :argv, System.argv())]
    {:unify, [{l, list(Enum.map(args, &chars/1))}]}
  end

  # --- library(process) ----------------------------------------------------

  @procs :prolog_ex_processes

  defp procs, do: Process.get(@procs, %{next: 0})
  defp put_procs(t), do: Process.put(@procs, t)

  # '$process_create'(Exe, Args, Stdin, Stdout, Stderr, Env, Cwd, Process)
  # Stdin usw.: [std] | [null] | [pipe, S] | [file, Pfad];
  # Env: [env | environment, [[Name, Wert], ...]]
  defbuiltin "$process_create", [exe, args, stdin, stdout, stderr, env, cwd, process] do
    Effects.external!()
    s = subst()
    exe = text(exe, s)
    args = for a <- PrologEx.Builtins.Lists.items(args, s), do: text(a, s)
    cwd = text(cwd, s)

    # wie Rust: kein Arbeitsverzeichnis oder kein Programm – Start scheitert
    unless cwd == "." or File.dir?(cwd), do: permission_create!()
    path = find_executable(exe, cwd) || permission_create!()

    specs = for {t, fd} <- [{stdin, 0}, {stdout, 1}, {stderr, 2}], do: spec(t, fd, s)

    for {:file, p, fd} <- specs, do: check_file!(p, fd, s)

    {pipes, redirs} =
      specs
      |> Enum.map(fn
        {:std, _} ->
          {nil, ""}

        {:null, fd} ->
          {nil, " #{redir(fd)}/dev/null"}

        {:file, p, fd} ->
          # relativ zum eigenen Arbeitsverzeichnis (wie Scryer), nicht cwd/1
          {nil, " #{redir(fd)}#{quote_sh(Path.expand(text(p, s)))}"}

        {:pipe, var, fd} ->
          fifo = make_fifo!()
          {{fifo, var, fd}, " #{redir(fd)}#{quote_sh(fifo)}"}
      end)
      |> Enum.unzip()

    opts =
      [
        :nouse_stdio,
        :exit_status,
        args: ["-c", "exec \"$@\"" <> Enum.join(redirs), "sh", path | args]
      ] ++
        env_opt(env, s) ++ if(cwd == ".", do: [], else: [cd: cwd])

    port =
      try do
        Port.open({:spawn_executable, "/bin/sh"}, opts)
      rescue
        _ -> permission_create!()
      end

    os_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, n} -> n
        _ -> nil
      end

    # die Pipes in der Reihenfolge der Shell öffnen
    streams =
      for {fifo, var, fd} <- Enum.reject(pipes, &is_nil/1) do
        id =
          if fd == 0 do
            {:ok, id} = S.open_file(fifo, :write, pipe: true)
            File.rm(fifo)
            id
          else
            S.open_pipe_reader(fifo)
          end

        {var, S.term(id)}
      end

    t = procs()
    n = t.next

    put_procs(
      %{t | next: n + 1}
      |> Map.put(n, %{port: port, os_pid: os_pid, status: nil, killed: false})
    )

    {:unify, [{process, mk("$process", [n])} | streams]}
  end

  defp spec(t, fd, s) do
    case PrologEx.Builtins.Lists.items(t, s) |> Enum.map(&PrologEx.walk(&1, s)) do
      [{:atom, "std"}] -> {:std, fd}
      [{:atom, "null"}] -> {:null, fd}
      [{:atom, "pipe"}, v] -> {:pipe, v, fd}
      [{:atom, "file"}, p] -> {:file, p, fd}
    end
  end

  defp redir(0), do: "<"
  defp redir(1), do: ">"
  defp redir(2), do: "2>"

  defp quote_sh(p), do: "'" <> String.replace(p, "'", "'\\''") <> "'"

  defp cwd_dir("."), do: File.cwd!()
  defp cwd_dir(d), do: Path.expand(d)

  # Datei für stdin lesbar bzw. für stdout/stderr beschreibbar? Sonst wie
  # Scryer permission_error(open, source_sink, Pfad)
  defp check_file!(p, fd, s) do
    path = text(p, s)
    ok = if fd == 0, do: File.regular?(path), else: writable?(path)
    unless ok, do: Error.permission!("open", "source_sink", PrologEx.resolve(p, s))
  end

  defp writable?(path) do
    case File.open(path, [:append]) do
      {:ok, f} ->
        File.close(f)
        true

      _ ->
        false
    end
  end

  defp make_fifo! do
    path = Path.join(System.tmp_dir!(), "prolog_ex_pipe_#{System.unique_integer([:positive])}")

    case System.cmd("mkfifo", [path], stderr_to_stdout: true) do
      {_, 0} -> path
      _ -> Error.permission!("open", "source_sink", a("anonymous_pipe"))
    end
  end

  defp find_executable(exe, cwd) do
    if String.contains?(exe, "/") do
      path = Path.expand(exe, cwd_dir(cwd))
      if executable?(path), do: path
    else
      System.find_executable(exe)
    end
  end

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _ -> false
    end
  end

  defp permission_create!,
    do: Error.permission!("create", "process", mk("/", [a("process_create"), 3]))

  # env: Umgebung leeren und setzen; environment: erben und überschreiben
  defp env_opt(env, s) do
    [kind, pairs] = PrologEx.Builtins.Lists.items(env, s) |> Enum.map(&PrologEx.walk(&1, s))

    set =
      for pair <- PrologEx.Builtins.Lists.items(pairs, s) do
        [n, v] = PrologEx.Builtins.Lists.items(pair, s)
        {String.to_charlist(text(n, s)), String.to_charlist(text(v, s))}
      end

    clear =
      if kind == {:atom, "env"},
        do: for({k, _} <- System.get_env(), do: {String.to_charlist(k), false}),
        else: []

    [env: clear ++ set]
  end

  # Handle → Eintrag; kein Handle: type_error(process, P); freigegeben:
  # existence_error(process, P)
  defp lookup!(p) do
    case PrologEx.unmark_top(p) do
      {:struct, "$process", [n]} when is_integer(n) ->
        case Map.fetch(procs(), n) do
          {:ok, e} -> {n, e}
          :error -> Error.existence!("process", p)
        end

      _ ->
        Error.type!("process", p)
    end
  end

  defbuiltin "$process_id", [p, pid] do
    {_, e} = lookup!(resolve(p))
    {:unify, [{pid, e.os_pid}]}
  end

  # '$process_wait'(P, Status, Timeout): Timeout infinite oder 0
  defbuiltin "$process_wait", [p, status, timeout] do
    {n, e} = lookup!(resolve(p))

    e =
      case {e.status, deref(timeout)} do
        {nil, {:atom, "infinite"}} -> receive_exit(e, :infinity)
        {nil, 0} -> receive_exit(e, 0)
        _ -> e
      end

    put_procs(Map.put(procs(), n, e))

    st =
      case e.status do
        nil -> a("timeout")
        137 when e.killed -> mk("killed", [9])
        code -> mk("exit", [code])
      end

    {:unify, [{status, st}]}
  end

  defp receive_exit(%{port: port} = e, timeout) do
    receive do
      {^port, {:exit_status, code}} -> %{e | status: code}
    after
      timeout -> e
    end
  end

  # SIGKILL; schon beendet: nichts zu tun (wie Rust)
  defbuiltin "$process_kill", [p] do
    Effects.external!()
    {n, e} = lookup!(resolve(p))

    if e.status == nil and e.os_pid do
      System.cmd("kill", ["-9", Integer.to_string(e.os_pid)], stderr_to_stdout: true)
      put_procs(Map.put(procs(), n, %{e | killed: true}))
    end

    :ok
  end

  defbuiltin "$process_release", [p] do
    {n, _} = lookup!(resolve(p))
    put_procs(Map.delete(procs(), n))
    :ok
  end
end
