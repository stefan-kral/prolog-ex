# Integrationstests mit gprolog nur, wenn der Reader übersetzt ist (das
# erledigt mix compile, wenn gplc da ist; siehe mix.exs).
if PrologEx.Reader.available?() do
  ExUnit.start()
else
  IO.puts("Hinweis: gprolog-Reader fehlt, Integrationstests (:gprolog) werden übersprungen")
  ExUnit.start(exclude: [:gprolog])
end

defmodule PrologEx.TestLibs do
  @moduledoc false
  # wie :- use_module(library(lists)), use_module(library(apply)) in user
  def libs(db), do: db |> PrologEx.use_library("lists") |> PrologEx.use_library("apply")
end
