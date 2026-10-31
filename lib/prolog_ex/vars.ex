defmodule PrologEx.Vars do
  @moduledoc """
  Kennungen der Variablen: eine Zahl aus einem gemeinsamen Zähler der VM
  (`:atomics`, über alle Prozesse), nie zweimal vergeben. Eine Variable ist

    * `{:var, n}` – frische Variable (Maschine, copy_term, Bibliotheken,
      read/1): Kennung `n`
    * `{:var, {name, n}}` – vom Reader, aus dem Quelltext: Name für
      Antworten, Singleton-Warnungen, `listing/1`, `variable_names/1`;
      anonyme `_` heißen `"_"` (jede mit eigener Zahl)
    * `{:var, {:attv, n}}` – attributiert (siehe `PrologEx.bind/3`)

  Geschrieben wird jede als `_n` (ISO 7.10.5: `_` und eine Zeichenfolge;
  dieselbe Variable heißt überall gleich, verschiedene verschieden – auch
  über getrennte Aufrufe hinweg, wie SWI, Scryer und SICStus), nur die
  Toplevel-Antworten zeigen die Namen der Anfrage und nennen frische `_A`,
  `_B`, ... Die Maschine nimmt sich Blöcke von Kennungen (`block/1`) und
  zählt darin lokal weiter; alle anderen eine je Variable (`next/0`).
  """

  @key {__MODULE__, :counter}

  @doc "Nächste freie Kennung"
  def next, do: :atomics.add_get(counter(), 1, 1)

  @doc "Anfang eines Blocks von n Kennungen (Anfang .. Anfang + n - 1)"
  def block(n), do: :atomics.add_get(counter(), 1, n) - n + 1

  defp counter do
    case :persistent_term.get(@key, nil) do
      nil -> init()
      ref -> ref
    end
  end

  # einmal je VM; :global.trans gegen zwei gleichzeitige erste Aufrufer
  defp init do
    :global.trans({@key, self()}, fn ->
      case :persistent_term.get(@key, nil) do
        nil ->
          ref = :atomics.new(1, signed: false)
          :persistent_term.put(@key, ref)
          ref

        ref ->
          ref
      end
    end)
  end
end
