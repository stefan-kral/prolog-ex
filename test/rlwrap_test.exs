defmodule PrologEx.RlwrapTest do
  # start_ex: TAB-Ergänzung unter rlwrap über den Filter .rlwrap_filter.py.
  #
  # .rlwrap_libraries: die Bibliotheken für use_module(library(X)) – eine
  # Auswahl (von Hand gepflegt); jeder Eintrag muss eine Bibliothek von
  # PrologEx sein.
  #
  # .rlwrap_predicates: je Name die Stelligkeiten aller Prädikate (für
  # member( mit Klammer), erzeugt; muss zu PrologEx passen. Neu schreiben:
  #
  #   mix run -e 'File.write!(".rlwrap_predicates", PrologEx.Shell.Complete.rlwrap_predicates_text())'
  use ExUnit.Case, async: true

  @libs ".rlwrap_libraries"
  @preds ".rlwrap_predicates"
  @filter ".rlwrap_filter.py"

  test ".rlwrap_libraries: nur Bibliotheken, die es gibt" do
    listed = @libs |> File.read!() |> String.split("\n", trim: true)
    known = PrologEx.Shell.Complete.libraries()
    assert listed -- known == [], "keine Bibliothek von PrologEx"
  end

  test ".rlwrap_predicates: passt zu PrologEx" do
    assert File.read!(@preds) == PrologEx.Shell.Complete.rlwrap_predicates_text(),
           "#{@preds} neu schreiben (Befehl oben in test/rlwrap_test.exs)"
  end

  # die Ergänzungslogik des Filters, ohne rlwrap (wenn python3 da ist)
  @check """
  import importlib.util, sys
  spec = importlib.util.spec_from_file_location("flt", sys.argv[1])
  m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
  libs, preds = m.read_libraries(), m.read_predicates()
  words = ["use_module", "member", "findall", "halt", "true", "lists"]
  c = lambda line, prefix: m.complete(line, prefix, words, libs, preds)
  assert "use_module(" in c("use_mod", "use_mod")
  assert "use_module" not in c("use_mod", "use_mod")
  assert "use_module(library(clpz))" in c("use_mod", "use_mod")
  assert c("use_module(library(cl", "cl") == ["clpb))", "clpz))"], c("use_module(library(cl", "cl")
  assert c("X = library(betw", "betw") == ["between)"]
  assert "library(lists))" in c("use_module(", "")
  assert c("forall(mem", "mem") == ["member("], c("forall(mem", "mem")
  assert c("fin", "fin") == ["findall("]
  assert c("hal", "hal") == ["halt", "halt("]
  assert c("tr", "tr") == ["true"]
  assert c("lis", "lis") == ["lists"]
  assert c("foo", "foo") == []
  assert c("use_module(library(si", "si") == ["si))", "simplex))"]
  assert c("use_module(library(si)", "") == [")"]
  assert c("use_module(library(si))", "") == []
  assert c("X = library(si)", "") == []
  assert c("use_module(library(nix)", "") == []
  print("ok")
  """

  test "Filter: Ergänzungen je nach Stelle" do
    case System.find_executable("python3") do
      nil ->
        :ok

      py ->
        assert {"ok\n", 0} = System.cmd(py, ["-B", "-c", @check, @filter], stderr_to_stdout: true)
    end
  end
end
