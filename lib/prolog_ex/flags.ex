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
    "occurs_check" => {false, [false, true, :error]},
    # ISO 7.11.2: debug und char_conversion mit on/off; char_conversion
    # schaltet die Zeichenumsetzung beim Lesen ein (PrologEx.CharConversion)
    "debug" => {:off, [:off, :on]},
    "char_conversion" => {:off, [:off, :on]},
    "max_arity" => {:unbounded, :read_only},
    "last_call_optimisation" => {true, :read_only},
    "dialect" => {:prolog_ex, :read_only},
    # Toplevel: Antworten ohne Rückfrage zeigen, solange keine Seiteneffekte
    # passieren – auto: eine Bildschirmseite, N: höchstens N, 1: einzeln
    "answer_chunk" => {:auto, [:auto, :positive_integer]},
    # true: die eingebauten Prädikate aus library(swi), iso_ext, between,
    # fastrw sind ohne Import sichtbar (wie früher; Übergang)
    "swi_compat" => {false, [false, true]},
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
        PrologEx.Error.domain!("prolog_flag", PrologEx.a(name))

      {:ok, {_, :read_only}} ->
        PrologEx.Error.permission!("modify", "flag", PrologEx.a(name))

      {:ok, {_, allowed}} ->
        unless Enum.any?(allowed, fn
                 :positive_integer -> is_integer(value) and value > 0
                 v -> term(v) == value
               end),
               do:
                 PrologEx.Error.domain!("flag_value", PrologEx.mk("+", [PrologEx.a(name), value]))

        Process.put(@key, Map.put(Process.get(@key, %{}), name, value))
        apply_side_effect(name, value)
        :ok
    end
  end

  @doc "Alle Flags auf Standardwerte zurücksetzen (für Tests)"
  def reset do
    Process.delete(@key)
    Process.delete(PrologEx.occurs_key())
  end

  # occurs_check: eigener Prozessschlüssel, damit bind_checked/3 schnell ist
  defp apply_side_effect("occurs_check", {:atom, "false"}),
    do: Process.delete(PrologEx.occurs_key())

  defp apply_side_effect("occurs_check", {:atom, "true"}),
    do: Process.put(PrologEx.occurs_key(), true)

  defp apply_side_effect("occurs_check", {:atom, "error"}),
    do: Process.put(PrologEx.occurs_key(), :error)

  defp apply_side_effect(_, _), do: :ok

  defp term(v) when is_atom(v), do: a(Atom.to_string(v))
  defp term(v), do: v
end
