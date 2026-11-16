defmodule PrologEx.ShellTest do
  # Eigener Zeileneditor des Toplevels (PrologEx.Shell): Ctrl-C-Flag an den
  # Prüfpunkten der Maschine, TAB-Completion. Das Terminal selbst (Rohmodus,
  # +Bc, Kreisel) ist hier nicht prüfbar – von Hand im Pseudo-Terminal.
  use ExUnit.Case, async: false
  alias PrologEx.{Reader, TableCase}
  alias PrologEx.Shell.Complete

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    on_exit(fn -> PrologEx.disarm_interrupt() end)
    :ok
  end

  defp run(c, db, q), do: inspect(elem(TableCase.run(c.reader, db, q), 1))

  defp abort_after(ms) do
    ref = :atomics.new(1, [])
    PrologEx.arm_interrupt(ref)
    spawn(fn -> Process.sleep(ms) && :atomics.put(ref, 1, 1) end)
    ref
  end

  test "Ctrl-C-Flag bricht eine Endlosschleife ab ('$aborted')", c do
    abort_after(200)
    assert run(c, %{}, "repeat, fail") =~ "$aborted"
  end

  test "nicht verschluckbar: ein catch-all fängt es, es kommt wieder", c do
    abort_after(200)
    assert run(c, %{}, "repeat, catch((repeat, fail), _, true), fail") =~ "$aborted"
  end

  test "ohne gesetztes Flag rechnet die Anfrage normal", c do
    :atomics.new(1, []) |> PrologEx.arm_interrupt()
    assert run(c, %{}, "length(L, 3)") =~ "L = [_"
    PrologEx.disarm_interrupt()
    assert run(c, %{}, "X = 1") =~ "X = 1"
  end

  defp expand(text), do: Complete.expand(text |> String.to_charlist() |> Enum.reverse())

  test "TAB: Prädikate, Bibliotheken, Dateien" do
    Complete.init()
    Complete.publish(PrologEx.use_library(%{}, "lists", "user"))
    assert expand("mem") == {:yes, ~c"ber", []}
    assert expand("foo(X) :- memb") == {:yes, ~c"er", []}
    assert {:no, [], shown} = expand("sum")
    assert ~c"sum_list/2" in shown
    # nur mit Argumenten: gleich die Klammer
    assert expand("subtra") == {:yes, ~c"ct(", []}
    assert expand("library(clpz") == {:yes, ~c")", []}
    assert expand("['mix.e") == {:yes, ~c"xs'", []}
    assert {:no, [], files} = expand("['lib/prolog_ex/sh")
    assert ~c"shell/" in files
    # ohne Import nicht sichtbar
    Complete.publish(%{})
    assert expand("subtra") == {:no, ~c"", []}
    # nichts zu ergänzen
    assert expand("X = ") == {:no, ~c"", []}
  end

  # --- Zeileneditor (Tasten als Nachrichten wie vom Leseprozess) ---------

  defp edit(keys, opts \\ []) do
    hist = Path.join(System.tmp_dir!(), "prolog_ex_hist_#{System.unique_integer([:positive])}")
    Application.put_env(:prolog_ex, :history_file, hist)
    Process.put(:prolog_shell, %{waiting: :atomics.new(1, []), ref: :atomics.new(1, [])})
    Process.put(:prolog_history, Keyword.get(opts, :history, []))
    for k <- keys, do: send(self(), {:prolog_key, k})

    try do
      ExUnit.CaptureIO.with_io(fn -> PrologEx.Shell.Edit.read("?- ") end) |> elem(0)
    after
      Process.delete(:prolog_shell)
      Application.delete_env(:prolog_ex, :history_file)
      File.rm(hist)
    end
  end

  test "Editor: Tippen, Cursor, Löschen, Enter" do
    assert edit(~w(a b c) ++ ["\e", "[", "D", "X", "\r"]) == "abXc\n"
    assert edit(~w(a b c) ++ [<<127>>, "\r"]) == "ab\n"
    assert edit(~w(a b c) ++ [<<1>>, <<4>>, "\r"]) == "bc\n"
    assert edit(~w(a b) ++ [" ", "c", "d", <<23>>, "\r"]) == "ab \n"
    assert edit(~w(a b c) ++ [<<1>>, <<11>>, "z", "\r"]) == "z\n"
    assert edit(["ä", "ö", <<2>>, "ü", "\r"]) == "äüö\n"
  end

  test "Editor: Ctrl-D auf leerer Zeile Dateiende, Ctrl-C verwirft" do
    assert edit([<<4>>]) == :eof
    assert edit(~w(a b) ++ [<<3>>]) == {:error, :interrupted}
    assert edit([:eof]) == :eof
  end

  test "Editor: Verlauf mit ↑/↓" do
    h = ["neueste", "ältere"]
    assert edit(["\e", "[", "A", "\r"], history: h) == "neueste\n"
    assert edit(["\e", "[", "A", "\e", "[", "A", "\r"], history: h) == "ältere\n"
    assert edit(["x", "\e", "[", "A", "\e", "[", "B", "\r"], history: h) == "x\n"
  end

  test "Editor: TAB ergänzt" do
    Complete.init()
    Complete.publish(PrologEx.use_library(%{}, "lists", "user"))
    assert edit(~w(m e m) ++ ["\t", "(", "X", "\r"]) == "member(X\n"
  end
end
