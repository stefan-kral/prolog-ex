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
  Bibliothek beim Laden selbst importiert, steht unter ihr.
  """

  @depth :prolog_ex_load_depth

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
        t0 = System.monotonic_time(:microsecond)

        r =
          try do
            f.()
          after
            Process.put(@depth, d)
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

        say("#{into} ← #{from}: #{what}")

        if lvl == :full do
          items =
            Enum.map(Enum.sort(keys), fn {name, ar} -> "#{quote_atom(name)}/#{ar}" end) ++
              Enum.map(ops, fn {p, type, name} ->
                "op(#{p}, #{plain(type)}, #{quote_atom(plain(name))})"
              end)

          for line <- wrap(items, 72), do: say("    " <> line)
        end

        :ok
    end
  end

  defp say(text) do
    pad = String.duplicate("  ", Process.get(@depth, 0))
    IO.puts(:stderr, "% " <> pad <> text)
  end

  # (Operatoren aus Dateien: Atome als Terme)
  defp plain({:atom, a}), do: a
  defp plain(a) when is_atom(a), do: Atom.to_string(a)
  defp plain(a), do: a

  defp quote_atom(name), do: PrologEx.Writer.format({:atom, name}, quoted: true)

  defp format_time(us) when us < 1_000_000, do: "#{div(us, 1000)} ms"
  defp format_time(us), do: :io_lib.format("~.2f s", [us / 1_000_000]) |> to_string()

  # Einträge mit ", " zu Zeilen von höchstens width Zeichen
  defp wrap(items, width) do
    {lines, cur} =
      Enum.reduce(items, {[], ""}, fn it, {lines, cur} ->
        cond do
          cur == "" -> {lines, it}
          String.length(cur) + 2 + String.length(it) > width -> {[cur <> "," | lines], it}
          true -> {lines, cur <> ", " <> it}
        end
      end)

    Enum.reverse(if cur == "", do: lines, else: [cur | lines])
  end
end
