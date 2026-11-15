defmodule PrologEx.TerminalColorTest do
  # Farben im Toplevel (PrologEx.Terminal): nur am Terminal
  use ExUnit.Case, async: true
  alias PrologEx.Terminal

  test "capabilities: die Felder" do
    c = Terminal.capabilities()
    assert Map.keys(c) |> Enum.sort() == [:ansi, :colors, :terminal, :truecolor, :unicode]
    assert is_integer(c.colors)
  end

  test "ohne Terminal (Tests, Pipes): Text unverändert, Prompt ohne Farbe" do
    refute Terminal.color?()
    assert Terminal.paint(:error, "Fehler: x") == "Fehler: x"
    assert Terminal.input_prompt("?- ") == "?- "
  end

  test "Flag color_term: Vorgabe true, nur true/false" do
    assert PrologEx.Flags.get("color_term") == {:atom, "true"}
  end
end
