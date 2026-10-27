ExUnit.start()

# gprolog-Orakel für Aufzeichnungen (GPROLOG_RECORD=1), siehe tools/gprolog
Code.require_file("../tools/gprolog/gprolog.ex", __DIR__)

defmodule PrologEx.TestLibs do
  @moduledoc false
  # wie :- use_module(library(lists)), use_module(library(apply)) in user
  def libs(db), do: db |> PrologEx.use_library("lists") |> PrologEx.use_library("apply")
end
