defmodule PrologEx.Builtins.Rlimit do
  @moduledoc """
  `library(rlimit)` wie SWI: `rlimit(+Resource, -Old, +New)` liest und
  setzt die POSIX-Grenzen (setrlimit) des eigenen Betriebssystemprozesses –
  der ganzen BEAM, nicht einer Anfrage. Die BEAM kennt kein setrlimit;
  PrologEx ruft dafür `prlimit` (util-linux) mit der eigenen PID auf, also
  nur unter Linux mit installiertem prlimit (sonst
  `existence_error(program, prlimit)`).

    * Resource: `as`, `core`, `cpu`, `data`, `fsize`, `locks`, `memlock`,
      `msgqueue`, `nice`, `nofile`, `nproc`, `rss`, `rtprio`, `rttime`,
      `sigpending`, `stack` (Größen in Bytes, `cpu` in Sekunden, `rttime`
      in Mikrosekunden – wie setrlimit).
    * Old: die weiche Grenze, eine Zahl oder `unlimited`.
    * New: die neue weiche Grenze (Zahl ≥ 0 oder `unlimited`); die harte
      bleibt. Ungebunden oder gleich Old: nur lesen (`rlimit(nofile, L, L)`).
      Über der harten Grenze: `permission_error(modify, rlimit, Resource)`.

  Achtung, was das für die BEAM heißt: Reißt `as` oder `data`, bekommt die
  BEAM keinen Speicher mehr und beendet sich (keine fangbare Ausnahme);
  `cpu` beendet den Prozess per Signal, `fsize` ebenso beim Schreiben über
  die Grenze. Sauber verhalten sich `nofile` (open/3 scheitert mit einem
  Fehler) und `core`. Grenzen je Anfrage: `library(time)`
  (`call_with_time_limit/2`).
  """
  use PrologEx.Builtin, module: "rlimit"
  alias PrologEx.Error

  @resources ~w(as core cpu data fsize locks memlock msgqueue nice nofile nproc rss rtprio
                rttime sigpending stack)

  defbuiltin "rlimit", [res, old, new] do
    s = subst()

    r =
      case deref(res) do
        {:var, _} -> Error.instantiation!()
        {:atom, r} when r in @resources -> r
        {:atom, _} = other -> Error.domain!("rlimit", other)
        other -> Error.type!("atom", resolve(other))
      end

    current = get!(r)

    case PrologEx.Store.walk(new, s) do
      {:var, _} = v ->
        {:unify, [{old, current}, {v, current}]}

      ^current ->
        {:unify, [{old, current}]}

      value ->
        arg = value_arg!(value, s)
        PrologEx.Effects.external!()
        set!(r, arg, res)
        {:unify, [{old, current}]}
    end
  end

  defp value_arg!({:atom, "unlimited"}, _s), do: "unlimited"
  defp value_arg!(n, _s) when is_integer(n) and n >= 0, do: Integer.to_string(n)
  defp value_arg!(n, _s) when is_integer(n), do: Error.domain!("not_less_than_zero", n)
  defp value_arg!(other, s), do: Error.type!("integer", PrologEx.resolve(other, s))

  defp get!(r) do
    case prlimit(["--#{r}", "--output", "SOFT", "--raw", "--noheadings"]) do
      {out, 0} ->
        case String.trim(out) do
          "unlimited" -> a("unlimited")
          n -> String.to_integer(n)
        end

      {_out, _} ->
        Error.permission!("access", "rlimit", a(r))
    end
  end

  # nur die weiche Grenze (soft:), die harte bleibt
  defp set!(r, arg, res) do
    case prlimit(["--#{r}=#{arg}:"]) do
      {_, 0} -> :ok
      {_, _} -> Error.permission!("modify", "rlimit", PrologEx.Store.walk(res, %{}))
    end
  end

  defp prlimit(args) do
    case System.find_executable("prlimit") do
      nil ->
        Error.existence!("program", a("prlimit"))

      exe ->
        try do
          System.cmd(exe, ["--pid", System.pid() | args], stderr_to_stdout: true)
        catch
          # keine Dateideskriptoren mehr (etwa nach rlimit(nofile, _, 3)):
          # prlimit lässt sich nicht starten. catch statt rescue: rescue
          # normalisiert über das Modul Exception, und auch Module laden
          # braucht Deskriptoren
          :error, :emfile -> Error.resource!("file_descriptors")
        end
    end
  end
end
