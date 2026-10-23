defmodule PrologEx.Flags do
  @moduledoc """
  Prolog-Flags (current_prolog_flag/2, set_prolog_flag/2).

  Flags gelten für die Sitzung und überstehen Backtracking. Sie liegen im
  Prozess, der die Anfragen ausführt (Toplevel bzw. Aufrufer von
  `PrologEx.query/3`). Vorläufige Lösung – sobald es eine globale,
  veränderliche Datenbank gibt (assert/retract), ziehen die Flags dorthin.

  Werte sind Prolog-Terme. Schreibbare Flags haben eine Liste erlaubter
  Werte (oder `:any_integer` usw.), lesbare nur einen festen Wert.
  """

  import PrologEx, only: [a: 1]

  @key :prolog_ex_flags

  # name => {standardwert, erlaubte_werte | :read_only}
  @flags %{
    "bounded" => {false, :read_only},
    "max_tagged_integer" => {576_460_752_303_423_487, :read_only},
    "min_tagged_integer" => {-576_460_752_303_423_488, :read_only},
    "integer_rounding_function" => {:toward_zero, :read_only},
    "double_quotes" => {:chars, [:chars, :codes, :atom]},
    "unknown" => {:error, [:error, :fail, :warning]},
    "occurs_check" => {false, :read_only},
    "debug" => {false, [true, false]},
    "last_call_optimisation" => {true, :read_only},
    "dialect" => {:prolog_ex, :read_only},
    "version" => {1, :read_only}
  }

  @doc "Alle Flags als `[{name, wert}]`, sortiert"
  def all do
    current = Process.get(@key, %{})

    @flags
    |> Enum.map(fn {name, {default, _}} -> {name, Map.get(current, name, term(default))} end)
    |> Enum.sort()
  end

  @doc "Wert eines Flags (Prolog-Term) oder nil"
  def get(name) do
    case Map.fetch(@flags, name) do
      {:ok, {default, _}} -> Map.get(Process.get(@key, %{}), name, term(default))
      :error -> nil
    end
  end

  @doc "Setzt ein Flag; wirft ISO-Fehler bei unbekanntem Flag oder Wert"
  def set(name, value) do
    case Map.fetch(@flags, name) do
      :error ->
        raise "domain_error(prolog_flag, #{name})"

      {:ok, {_, :read_only}} ->
        raise "permission_error(modify, flag, #{name})"

      {:ok, {_, allowed}} ->
        unless Enum.any?(allowed, &(term(&1) == value)),
          do: raise("domain_error(flag_value, #{name}+#{PrologEx.format(value)})")

        Process.put(@key, Map.put(Process.get(@key, %{}), name, value))
        :ok
    end
  end

  @doc "Alle Flags auf Standardwerte zurücksetzen (für Tests)"
  def reset, do: Process.delete(@key)

  defp term(v) when is_atom(v), do: a(Atom.to_string(v))
  defp term(v), do: v
end
