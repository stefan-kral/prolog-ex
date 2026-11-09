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
    # wie SWI: true – 1/3 und 2 ** -1 (Ganzzahlen) geben Brüche (1r3, 1r2)
    # statt Floats, 2 ^ -1 statt type_error ebenfalls
    "prefer_rationals" => {false, [false, true]},
    # ISO 7.11.2: debug und char_conversion mit on/off; char_conversion
    # schaltet die Zeichenumsetzung beim Lesen ein (PrologEx.CharConversion)
    "debug" => {:off, [:off, :on]},
    "char_conversion" => {:off, [:off, :on]},
    # größte Stelligkeit (functor/3, =../2, Lesen): darüber
    # representation_error(max_arity); max_arity/0
    "max_arity" => {65_536, :read_only},
    "last_call_optimisation" => {true, :read_only},
    "dialect" => {:prolog_ex, :read_only},
    # Toplevel: Antworten ohne Rückfrage zeigen, solange keine Seiteneffekte
    # passieren – auto: eine Bildschirmseite, N: höchstens N, 1: einzeln
    "answer_chunk" => {:auto, [:auto, :positive_integer]},
    # wie SWI (dort Vorgabe silent): Meldungen beim Laden (PrologEx.LoadLog) – silent: keine,
    # normal: geladene Dateien und je Import die Zahl der Prädikate, full:
    # dazu die importierten Prädikate und Operatoren einzeln
    "verbose_load" => {:full, [:silent, :normal, :full]},
    # true: die eingebauten Prädikate aus library(swi), iso_ext, between,
    # fastrw sind ohne Import sichtbar (wie früher; Übergang)
    "swi_compat" => {false, [false, true]},
    # library(clpz): Restziele lesbar (X #> 1 statt X in 2..sup, X #< Y
    # statt X #=< Y + -1) oder genau wie Scryer
    "clpz_residuals" => {:compact, [:compact, :scryer]},
    # Speichergrenze je Anfrage (wie SWIs stack_limit, Bytes): wächst der
    # Heap der Anfrage um mehr, resource_error(memory); unlimited: keine
    "stack_limit" => {1_073_741_824, [:positive_integer, :unlimited]},
    "version" => {1, :read_only},
    # wie SWI (swi(9, 3, 0, [])): Funktor = Dialekt, dann Major, Minor,
    # Patch, Extra
    "version_data" => {{:struct, "prolog_ex", [0, 1, 0, []]}, :read_only}
  }

  # Standardwerte als Prolog-Terme, einmal beim Übersetzen (sonst baute
  # jedes Lesen eines nicht gesetzten Flags den Term neu: Atom.to_string)
  @defaults Map.new(@flags, fn
              {name, {v, _}} when is_atom(v) -> {name, {:atom, Atom.to_string(v)}}
              {name, {v, _}} -> {name, v}
            end)

  @doc "Größte Stelligkeit eines Terms (Flag max_arity, 2^16)"
  def max_arity, do: 65_536

  @doc "Alle Flags als `[{name, wert}]`, sortiert"
  def all do
    current = Process.get(@key, %{})

    @defaults
    |> Enum.map(fn {name, default} -> {name, Map.get(current, name, default)} end)
    |> Enum.sort()
  end

  @doc "Wert eines Flags (Prolog-Term) oder nil"
  def get(name) do
    case Map.fetch(@defaults, name) do
      {:ok, default} -> Map.get(Process.get(@key, %{}), name, default)
      :error -> nil
    end
  end

  @doc "Der gesetzte Wert eines Flags, nil wenn es nicht gesetzt wurde"
  def explicit(name), do: Map.get(Process.get(@key, %{}), name)

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
