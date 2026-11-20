defmodule PrologEx.RlwrapTest do
  # start_ex: TAB-Ergänzung unter rlwrap. .rlwrap_libraries ist die Liste
  # der Bibliotheken für den Filter .rlwrap_filter.py (use_module(library(X))
  # ergänzen); sie muss zu PrologEx passen. Neu schreiben:
  #
  #   mix run -e 'IO.puts(Enum.join(Enum.sort(PrologEx.Shell.Complete.libraries()), "\n"))' > .rlwrap_libraries
  use ExUnit.Case, async: true

  @libs ".rlwrap_libraries"
  @filter ".rlwrap_filter.py"

  test ".rlwrap_libraries: alle Bibliotheken von PrologEx, sortiert" do
    listed = @libs |> File.read!() |> String.split("\n", trim: true)

    assert listed == Enum.sort(PrologEx.Shell.Complete.libraries()),
           "#{@libs} neu schreiben (Befehl oben in test/rlwrap_test.exs)"
  end

  # die Ergänzungslogik des Filters, ohne rlwrap (wenn python3 da ist)
  @check """
  import importlib.util, sys
  spec = importlib.util.spec_from_file_location("flt", sys.argv[1])
  m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
  libs = m.read_libraries()
  c = lambda line, prefix: m.complete(line, prefix, ["use_module", "member"], libs)
  assert "use_module" in c("use_mod", "use_mod")
  assert "use_module(library(clpz))" in c("use_mod", "use_mod")
  assert c("use_module(library(cl", "cl") == ["clpb))", "clpz))"], c("use_module(library(cl", "cl")
  assert c("X = library(betw", "betw") == ["between)"]
  assert "library(lists))" in c("use_module(", "")
  assert c("forall(mem", "mem") == ["member"]
  assert c("foo", "foo") == []
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
