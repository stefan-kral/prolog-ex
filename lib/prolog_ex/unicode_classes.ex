defmodule PrologEx.UnicodeClasses do
  @moduledoc """
  Unicode-Klassen aus der allgemeinen Kategorie der Unicode Character
  Database 17.0: für `char_type/2` (alphabetic, lower, upper, numeric,
  control) und für Leser und Schreiber (Variablenanfang Lu/Lt, Buchstabe L,
  Symbolzeichen Sm/So, Fortsetzung eines Namens L/N/M) – dieselbe Version wie `String.upcase/1` und `String.downcase/1`
  (Elixir), mit denen `upper(U)` und `lower(L)` rechnen. Vorher kamen die
  Klassen aus regulären Ausdrücken (`\\p{L}` …, PCRE in OTP 28: Unicode
  16) und kannten die 4800 Zeichen von Unicode 17 nicht; der Leser nahm
  sie nicht in Namen.

  Die Bereiche stehen in `priv/unicode/char_classes.txt` (erzeugt von
  `priv/unicode/gen_char_classes.py` aus UnicodeData.txt) und werden beim
  Übersetzen zu sortierten Tupeln; gesucht wird binär (höchstens 10
  Schritte).
  """

  @path Path.join([__DIR__, "..", "..", "priv", "unicode", "char_classes.txt"])
  @external_resource @path

  ranges =
    @path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.map(fn l ->
      [k, lo, hi] = String.split(l)
      {k, {String.to_integer(lo, 16), String.to_integer(hi, 16)}}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

  @alphabetic ranges |> Map.fetch!("alphabetic") |> List.to_tuple()
  @lower ranges |> Map.fetch!("lower") |> List.to_tuple()
  @upper ranges |> Map.fetch!("upper") |> List.to_tuple()
  @numeric ranges |> Map.fetch!("numeric") |> List.to_tuple()
  @control ranges |> Map.fetch!("control") |> List.to_tuple()
  @var_start ranges |> Map.fetch!("var_start") |> List.to_tuple()
  @letter ranges |> Map.fetch!("letter") |> List.to_tuple()
  @symbol ranges |> Map.fetch!("symbol") |> List.to_tuple()
  @ident ranges |> Map.fetch!("ident") |> List.to_tuple()

  @doc "Buchstabe (L) oder Buchstabenzahl (Nl)"
  def alphabetic?(c), do: member?(@alphabetic, c, 0, tuple_size(@alphabetic) - 1)
  @doc "Kleinbuchstabe (Ll)"
  def lower?(c), do: member?(@lower, c, 0, tuple_size(@lower) - 1)
  @doc "Großbuchstabe (Lu)"
  def upper?(c), do: member?(@upper, c, 0, tuple_size(@upper) - 1)
  @doc "Zahl (N)"
  def numeric?(c), do: member?(@numeric, c, 0, tuple_size(@numeric) - 1)
  @doc "Steuerzeichen (Cc)"
  def control?(c), do: member?(@control, c, 0, tuple_size(@control) - 1)
  @doc "beginnt eine Variable (Lu, Lt)"
  def var_start?(c), do: member?(@var_start, c, 0, tuple_size(@var_start) - 1)
  @doc "Buchstabe (L)"
  def letter?(c), do: member?(@letter, c, 0, tuple_size(@letter) - 1)
  @doc "mathematisches oder sonstiges Symbol (Sm, So)"
  def symbol?(c), do: member?(@symbol, c, 0, tuple_size(@symbol) - 1)
  @doc "setzt einen Namen fort (L, N, M)"
  def ident?(c), do: member?(@ident, c, 0, tuple_size(@ident) - 1)

  defp member?(_t, _c, lo, hi) when lo > hi, do: false

  defp member?(t, c, lo, hi) do
    mid = div(lo + hi, 2)

    case elem(t, mid) do
      {a, _} when c < a -> member?(t, c, lo, mid - 1)
      {_, b} when c > b -> member?(t, c, mid + 1, hi)
      _ -> true
    end
  end
end
