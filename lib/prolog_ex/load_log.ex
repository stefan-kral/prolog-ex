defmodule PrologEx.LoadLog do
  @moduledoc """
  Meldungen beim Laden (Flag `verbose_load`, Name wie SWI):

    * `silent`: keine
    * `normal`: je geladener Datei/Bibliothek eine Zeile, je Import eine
      Zeile mit der Zahl der Prädikate:
      `% user ← lists: 26 Prädikate`
    * `full` (Vorgabe; SWI: silent): dazu die importierten Prädikate (und
      Operatoren) einzeln

  Auf stderr, als Kommentare (`% ...`), eingerückt nach Ladetiefe: was eine
  Bibliothek beim Laden selbst importiert, steht unter ihr. Dieselbe Liste
  (gleiches Modul, gleiche Prädikate und Operatoren) steht während eines
  Ladevorgangs nur einmal, danach `… : 11 Prädikate (wie oben)`.
  """

  @depth :prolog_ex_load_depth
  # schon einzeln gezeigte Importlisten des laufenden Ladevorgangs
  @listed :prolog_ex_load_listed

  @doc "`:silent`, `:normal` oder `:full`"
  # (nicht gesetzt: die Vorgabe des Flags, full – außer die Anwendung sagt
  # anderes, etwa die Tests: Application-Umgebung :verbose_load)
  def level do
    value =
      PrologEx.Flags.explicit("verbose_load") ||
        case Application.get_env(:prolog_ex, :verbose_load) do
          nil -> PrologEx.Flags.get("verbose_load")
          v -> {:atom, Atom.to_string(v)}
        end

    case value do
      {:atom, "normal"} -> :normal
      {:atom, "full"} -> :full
      _ -> :silent
    end
  end

  @doc """
  Eine Datei/Bibliothek laden (f, Ergebnis wie `Consult.load_file/2`;
  label: `library(clpz)` o. ä.): davor und danach eine Zeile, was sie
  selbst lädt und importiert, eine Stufe tiefer eingerückt
  """
  def loading(label, f) do
    case level() do
      :silent ->
        f.()

      _ ->
        say("lade #{label} ...")
        d = Process.get(@depth, 0)
        Process.put(@depth, d + 1)
        if d == 0, do: Process.put(@listed, %{})
        t0 = System.monotonic_time(:microsecond)

        r =
          try do
            f.()
          after
            Process.put(@depth, d)
            if d == 0, do: Process.delete(@listed)
          end

        us = System.monotonic_time(:microsecond) - t0
        mod = with {_, m} when is_binary(m) <- r, do: "Modul #{m}, ", else: (_ -> "")
        say("#{label} geladen (#{mod}#{format_time(us)})")
        r
    end
  end

  @doc """
  Importe in `into` aus `from`: keys die neu importierten `{name, arity}`,
  ops die Operatoren (`{p, typ, name}`), die mitkommen
  """
  def imported(into, from, keys, ops \\ []) do
    case level() do
      :silent ->
        :ok

      lvl when keys == [] and ops == [] and lvl != :full ->
        :ok

      lvl ->
        n = length(keys)

        what =
          case n do
            0 -> "nichts Neues"
            1 -> "1 Prädikat"
            _ -> "#{n} Prädikate"
          end

        what =
          case length(ops) do
            0 -> what
            1 -> what <> ", 1 Operator"
            k -> what <> ", #{k} Operatoren"
          end

        listed = Process.get(@listed)
        key = {from, Enum.sort(keys), ops}
        again = lvl == :full and is_map(listed) and is_map_key(listed, key)

        cond do
          again ->
            say("#{into} ← #{from}: #{what} (wie oben)")

          lvl == :full and (keys != [] or ops != []) ->
            if is_map(listed), do: Process.put(@listed, Map.put(listed, key, true))

            items =
              Enum.map(Enum.sort(keys), fn {name, ar} -> "#{quote_atom(name)}/#{ar}" end) ++
                Enum.map(ops, fn {p, type, name} ->
                  "op(#{p}, #{plain(type)}, #{quote_atom(plain(name))})"
                end)

            # die Liste gleich hinter der Zeile, in Klammern, weiter
            # eingerückt umbrochen
            for line <- wrap("#{into} ← #{from}: #{what} (", items, width()), do: say(line)

          true ->
            say("#{into} ← #{from}: #{what}")
        end

        :ok
    end
  end

  @doc "Autoload beim Laden (PrologEx.Autoload): `% user ← lists: member/2 (autoload)`"
  def autoloaded(into, from, keys) do
    if level() != :silent do
      items = Enum.map_join(keys, ", ", fn {name, ar} -> "#{quote_atom(name)}/#{ar}" end)
      say("#{into} ← #{from}: #{items} (autoload)")
    end

    :ok
  end

  # Zeilenlänge: die Breite des Terminals (beim Ausgeben gemessen, also auch
  # nach Ändern der Fenstergröße) abzüglich "% ", Einrückung und dem Komma
  # bzw. der Klammer am Zeilenende (sonst bricht das Terminal eine genau
  # volle Zeile davor um); ohne Terminal (umgeleitet) 78 Spalten
  defp width do
    cols =
      case :io.columns() do
        {:ok, c} -> c
        _ -> 78
      end

    max(cols - 3 - 2 * Process.get(@depth, 0), 40)
  end

  defp say(text) do
    pad = String.duplicate("  ", Process.get(@depth, 0))
    IO.puts(:stderr, PrologEx.Terminal.paint(:comment, "% " <> pad <> text))
  end

  # (Operatoren aus Dateien: Atome als Terme)
  defp plain({:atom, a}), do: a
  defp plain(a) when is_atom(a), do: Atom.to_string(a)
  defp plain(a), do: a

  defp quote_atom(name), do: PrologEx.Writer.format({:atom, name}, quoted: true)

  defp format_time(us) when us < 1_000_000, do: "#{div(us, 1000)} ms"
  defp format_time(us), do: :io_lib.format("~.2f s", [us / 1_000_000]) |> to_string()

  # head (endet mit "(") und die Einträge mit ", " zu Zeilen von höchstens
  # width Zeichen (ohne das Komma am Ende); Folgezeilen mit "    "
  # eingerückt, am Ende ")". Passt schon der erste Eintrag nicht mehr hinter
  # head, beginnt die Liste in der nächsten Zeile
  defp wrap(head, items, width) do
    {lines, cur, _} =
      Enum.reduce(items, {[], head, false}, fn it, {lines, cur, has?} ->
        sep = if has?, do: ", ", else: ""

        cond do
          String.length(cur) + String.length(sep) + String.length(it) <= width ->
            {lines, cur <> sep <> it, true}

          has? ->
            {[cur <> "," | lines], "    " <> it, true}

          cur == head ->
            {[cur | lines], "    " <> it, true}

          true ->
            {lines, cur <> it, true}
        end
      end)

    Enum.reverse([cur <> ")" | lines])
  end
end
