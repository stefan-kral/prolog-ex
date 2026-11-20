defmodule PrologEx.RlwrapTest do
  # start_ex: TAB-Ergänzung unter rlwrap über den Filter .rlwrap_filter.py.
  #
  # .rlwrap_libraries: die Bibliotheken für use_module(library(X)) – eine
  # Auswahl (von Hand gepflegt); jeder Eintrag muss eine Bibliothek von
  # PrologEx sein.
  #
  # Aus PrologEx erzeugt (PrologEx.Shell.Complete.rlwrap_files/0), müssen
  # dazu passen: .rlwrap_predicates (Stelligkeiten: member( mit Klammer),
  # .rlwrap_flags, .rlwrap_ops, .rlwrap_evaluables, .rlwrap_char_types,
  # .rlwrap_clpz.
  # Alle neu schreiben:
  #
  #   mix run -e 'PrologEx.Shell.Complete.write_rlwrap_files()'
  use ExUnit.Case, async: true

  @libs ".rlwrap_libraries"
  @filter ".rlwrap_filter.py"

  test ".rlwrap_libraries: nur Bibliotheken, die es gibt" do
    listed = @libs |> File.read!() |> String.split("\n", trim: true)
    known = PrologEx.Shell.Complete.libraries()
    assert listed -- known == [], "keine Bibliothek von PrologEx"
  end

  test "erzeugte .rlwrap-Dateien passen zu PrologEx" do
    for {file, text} <- PrologEx.Shell.Complete.rlwrap_files() do
      assert File.read!(file) == text,
             "#{file} neu schreiben (Befehl oben in test/rlwrap_test.exs)"
    end
  end

  # die Ergänzungslogik des Filters, ohne rlwrap (wenn python3 da ist)
  @check """
  import importlib.util, sys
  spec = importlib.util.spec_from_file_location("flt", sys.argv[1])
  m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
  data = m.load()
  words = ["use_module", "member", "findall", "halt", "true", "lists"]
  c = lambda line, prefix: m.complete(line, prefix, words, data)
  assert c("use_mod", "use_mod") == ["use_module("]
  assert not [x for x in c("", "") if "library" in x]
  assert c("use_module(library(cl", "cl") == ["clpb)", "clpz)"], c("use_module(library(cl", "cl")
  assert c("X = library(betw", "betw") == ["between)"]
  assert "library(lists)" in c("use_module(", "")
  assert c("forall(mem", "mem") == ["member("], c("forall(mem", "mem")
  assert c("fin", "fin") == ["findall("]
  assert c("hal", "hal") == ["halt", "halt("]
  assert c("tr", "tr") == ["true"]
  assert c("lis", "lis") == ["lists"]
  assert c("foo", "foo") == []
  assert c("use_module(library(si", "si") == ["si)", "simplex)"]
  assert c("use_module(library(si)", "") == [")"]
  assert c("use_module(library(si))", "") == []
  assert c("X = library(si)", "") == []
  assert c("use_module(library(nix)", "") == []
  assert c("current_prolog_flag(dia", "dia") == ["dialect,"]
  assert "bounded," in c("X = 1, current_prolog_flag(", "")
  assert c("set_prolog_flag(occ", "occ") == ["occurs_check,"]
  assert c("set_prolog_flag(dia", "dia") == []
  assert c("set_prolog_flag(occurs_check,", "") == ["false)", "true)", "error)"]
  assert c("set_prolog_flag(occurs_check, t", "t") == ["true)"]
  assert c("set_prolog_flag(dialect,", "") == []
  assert c("current_op(", "")[:2] == ["1200,", "1150,"]
  assert c("current_op(11", "11") == ["1150,", "1105,", "1100,"]
  assert c("current_op(700, x", "x") == ["xfx,"]
  assert c("current_op(1200, T,", "") == ["-->)", ":-)", "?-)"]
  assert c("current_op(P, T, dyn", "dyn") == ["dynamic)"]
  assert c("current_op(P, T, =.", "") == [".)"]
  assert c("X is ma", "ma") == ["max(", "max_tagged_integer"]
  assert "abs(" in c("X is ", "") and "mod" not in c("X is ", "")
  assert c("X is A ", "") == ["div", "mod", "rdiv", "rem", "xor"]
  assert c("X is (A + B) m", "m") == ["mod"]
  assert c("X is A mod s", "s")[0] == "sign("
  assert c("X is max(A, sq", "sq") == ["sqrt("]
  assert c("X =:= ab", "ab") == ["abs("]
  assert c("X is 1.5 + p", "p") == ["pi", "plus(", "popcount("]
  assert c("X is 1, Y = tr", "tr") == ["true"]
  assert c("X -> tr", "tr") == ["true"]
  assert c("X @< mem", "mem") == ["member("]
  assert c("X is ", "")[:2] == ["(", "abs("]
  assert c("X is (A + ", "")[0] == "("
  assert c("X #= ", "") == ["(", "abs(", "div(", "lsb(", "max(", "min(", "mod(", "msb(",
                            "popcount(", "rem(", "sign(", "xor("]
  assert c("X #=< Y*ma", "ma") == ["max("]
  assert c("X #\\\\= A ", "") == ["div", "mod", "rem", "xor"]
  assert c("X #= 1 #<==> tr", "tr") == ["true"]
  assert c("X #<==> tr", "tr") == ["true"]
  assert c("X #= 1 #/\\\\ Y #= ab", "ab") == ["abs("]
  assert c("char_type(C, alpha", "alpha") == ["alpha)", "alphabetic)", "alphanumeric)"]
  assert c("char_type(C, up", "up") == ["upper)", "upper("]
  assert c("code_type(0'a, dig", "dig") == ["digit("]
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
