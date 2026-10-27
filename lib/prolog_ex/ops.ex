defmodule PrologEx.Ops do
  @moduledoc """
  Die Operatortabelle der Sitzung (Prozess-Dictionary), für Reader
  (`PrologEx.Parser`) und Writer. Änderungen kommen von `op/3`, aus
  Bibliotheken (`Reader.op/4`) und aus `module/2`-Exportlisten. Ohne
  Änderungen gilt die Standardtabelle: ISO, dazu wie gprolog und SWI die
  Deklarationsoperatoren (`dynamic`, ...), `=@=`, `\\=@=`, `xor` (Cor. 2) und
  die CLP(FD)-Operatoren.

  Tabelle: `%{name => %{prefix: {p, typ}, infix: {p, typ}, postfix: {p, typ}}}`
  (nur die vorhandenen Klassen).
  """

  @key :prolog_ex_ops

  # wie gprolog 1.4/1.5 samt den Deklarationsoperatoren (dynamic, ...,
  # attribute), =@=, \\=@=, xor
  @default_list [
    {1200, "xfx", "-->"},
    {1200, "fx", ":-"},
    {1200, "xfx", ":-"},
    {1200, "fx", "?-"},
    {1150, "fx", "attribute"},
    {1150, "fx", "discontiguous"},
    {1150, "fx", "dynamic"},
    {1150, "fx", "initialization"},
    {1150, "fx", "meta_predicate"},
    {1150, "fx", "module_transparent"},
    {1150, "fx", "multifile"},
    {1150, "fx", "table"},
    {1105, "xfy", "|"},
    {1100, "xfy", ";"},
    {1050, "xfy", "*->"},
    {1050, "xfy", "->"},
    {1000, "xfy", ","},
    {900, "fy", "\\+"},
    {750, "xfy", "#<=>"},
    {750, "xfy", "#\\<=>"},
    {740, "xfy", "#==>"},
    {740, "xfy", "#\\==>"},
    {730, "xfy", "##"},
    {730, "yfx", "#\\/"},
    {730, "yfx", "#\\\\/"},
    {720, "yfx", "#/\\"},
    {720, "yfx", "#\\/\\"},
    {710, "fy", "#\\"},
    {700, "xfx", "#<"},
    {700, "xfx", "#<#"},
    {700, "xfx", "#="},
    {700, "xfx", "#=#"},
    {700, "xfx", "#=<"},
    {700, "xfx", "#=<#"},
    {700, "xfx", "#>"},
    {700, "xfx", "#>#"},
    {700, "xfx", "#>="},
    {700, "xfx", "#>=#"},
    {700, "xfx", "#\\="},
    {700, "xfx", "#\\=#"},
    {700, "xfx", "<"},
    {700, "xfx", "="},
    {700, "xfx", "=.."},
    {700, "xfx", "=:="},
    {700, "xfx", "=<"},
    {700, "xfx", "=@="},
    {700, "xfx", "\\=@="},
    {700, "xfx", "=="},
    {700, "xfx", "=\\="},
    {700, "xfx", ">"},
    {700, "xfx", ">="},
    {700, "xfx", "@<"},
    {700, "xfx", "@=<"},
    {700, "xfx", "@>"},
    {700, "xfx", "@>="},
    {700, "xfx", "\\="},
    {700, "xfx", "\\=="},
    {700, "xfx", "is"},
    {600, "xfy", ":"},
    {500, "yfx", "+"},
    {500, "yfx", "-"},
    {500, "yfx", "/\\"},
    {500, "yfx", "\\/"},
    {400, "yfx", "*"},
    {400, "yfx", "/"},
    {400, "yfx", "//"},
    {400, "yfx", "<<"},
    {400, "yfx", ">>"},
    {400, "yfx", "div"},
    {400, "yfx", "mod"},
    {400, "yfx", "rem"},
    {400, "yfx", "xor"},
    {200, "xfx", "**"},
    {200, "fy", "+"},
    {200, "fy", "-"},
    {200, "fy", "\\"},
    {200, "xfy", "^"}
  ]

  @classes %{
    "fy" => :prefix,
    "fx" => :prefix,
    "xfx" => :infix,
    "xfy" => :infix,
    "yfx" => :infix,
    "xf" => :postfix,
    "yf" => :postfix
  }

  @default Enum.reduce(@default_list, %{}, fn {p, t, n}, acc ->
             c = Map.fetch!(@classes, t)
             Map.update(acc, n, %{c => {p, t}}, &Map.put(&1, c, {p, t}))
           end)

  @doc "Klasse eines Operatortyps"
  def class(t), do: Map.fetch!(@classes, t)

  @doc "Aktuelle Tabelle der Sitzung"
  def table, do: Process.get(@key, @default)

  @doc "Standardtabelle"
  def default, do: @default

  @doc "Zurück zur Standardtabelle (neuer Reader)"
  def reset, do: Process.delete(@key)

  @doc "Operator eintragen (Priorität 0 entfernt ihn aus seiner Klasse)"
  def add(p, type, name) do
    c = class(type)
    t = table()

    entry =
      if p == 0,
        do: Map.delete(Map.get(t, name, %{}), c),
        else: Map.put(Map.get(t, name, %{}), c, {p, type})

    t = if entry == %{}, do: Map.delete(t, name), else: Map.put(t, name, entry)
    Process.put(@key, t)
    :ok
  end

  @doc "{p, typ} der Klasse oder nil"
  def lookup(table, name, class), do: table |> Map.get(name, %{}) |> Map.get(class)

  @doc "Ist das Atom irgendein Operator? Dann seine höchste Priorität, sonst nil"
  def max_priority(table, name) do
    case Map.get(table, name) do
      nil -> nil
      m -> m |> Map.values() |> Enum.map(&elem(&1, 0)) |> Enum.max()
    end
  end
end
