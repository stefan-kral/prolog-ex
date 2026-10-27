# Vergleiche mit gprolog nur, wenn dessen Reader übersetzt ist (das
# erledigt mix compile, wenn gplc da ist; siehe mix.exs).
if PrologEx.GprologReader.available?() do
  ExUnit.start()
else
  IO.puts("Hinweis: gprolog-Reader fehlt, Vergleiche mit gprolog (:gprolog) werden übersprungen")
  ExUnit.start(exclude: [:gprolog])
end

defmodule PrologEx.TestLibs do
  @moduledoc false
  # wie :- use_module(library(lists)), use_module(library(apply)) in user
  def libs(db), do: db |> PrologEx.use_library("lists") |> PrologEx.use_library("apply")
end
