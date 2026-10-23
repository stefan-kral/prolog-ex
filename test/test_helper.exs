# Reader neu übersetzen, wenn reader.pl neuer ist (und gplc vorhanden)
if PrologEx.Reader.available?() and PrologEx.Reader.stale?() do
  case Mix.Tasks.Prolog.BuildReader.build() do
    {:ok, _} -> IO.puts("Hinweis: gprolog-Reader neu übersetzt")
    {:error, msg} -> IO.puts("Hinweis: Reader veraltet, Neubau gescheitert: #{msg}")
  end
end

# Integrationstests mit gprolog nur, wenn der Reader übersetzt ist
# (mix prolog.build_reader).
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
