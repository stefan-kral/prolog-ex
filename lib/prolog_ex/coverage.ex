defmodule PrologEx.Coverage do
  @moduledoc """
  Abdeckung der Prolog-Bibliotheken messen (`bench/coverage/prolog.exs`):
  das Skript schreibt Bibliotheken vorübergehend so um, dass jede Klausel
  zuerst `'$coverage'(Id)` ruft; das zählt hier, je Id, in einer ETS-Tabelle
  – auch aus Kindern von library(concurrent). Gemessen wird nur, wenn die
  Umgebungsvariable `PROLOG_EX_COVERAGE` eine Datei nennt: dorthin schreibt
  der Lauf am Ende die Zähler (`Id Anzahl` je Zeile). Sonst tut
  `'$coverage'/1` nichts.
  """

  @table :prolog_ex_coverage

  @doc "Einen Treffer für id zählen (ohne Messung: nichts)"
  def hit(id) do
    case table() do
      nil -> :ok
      t -> :ets.update_counter(t, id, 1, {id, 0})
    end

    :ok
  end

  defp table do
    case :ets.whereis(@table) do
      :undefined ->
        case System.get_env("PROLOG_EX_COVERAGE") do
          nil -> nil
          "" -> nil
          file -> start(file)
        end

      t ->
        t
    end
  end

  # die Tabelle gehört einem eigenen Prozess (sie überlebt Kinder und
  # Testprozesse); am Ende des Laufs schreibt ein Haken die Zähler
  defp start(file) do
    me = self()

    :global.trans({__MODULE__, self()}, fn ->
      if :ets.whereis(@table) == :undefined do
        spawn(fn ->
          :ets.new(@table, [:named_table, :public, write_concurrency: true])
          send(me, :ready)
          Process.sleep(:infinity)
        end)

        receive do
          :ready -> :ok
        end

        System.at_exit(fn _ -> dump(file) end)
      end
    end)

    :ets.whereis(@table)
  end

  defp dump(file) do
    rows = for {id, n} <- :ets.tab2list(@table), do: "#{id} #{n}\n"
    File.write!(file, rows)
  end
end
