defmodule PrologEx.ReaderTest do
  # PrologEx.Reader: Lesen im Sitzungsprozess mit PrologEx.Parser
  use ExUnit.Case, async: true
  alias PrologEx.Reader

  @moduletag :tmp_dir

  defp file(c, name, text) do
    path = Path.join(c.tmp_dir, name)
    File.write!(path, text)
    path
  end

  defp names(items), do: for({:term, t, _} <- items, do: PrologEx.format(t, quoted: true))

  test "Dateien in Abschnitten bis zur nächsten Direktive", c do
    path = file(c, "a.pl", "a.\nb.\n:- d1.\nc.\n:- d2.\n")
    assert Reader.open_file(nil, path) == :ok
    assert {items, :pause} = Reader.next_chunk(nil)
    assert names(items) == ["a", "b", ":-d1"]
    assert {items, :pause} = Reader.next_chunk(nil)
    assert names(items) == ["c", ":-d2"]
    assert {[], :eof} = Reader.next_chunk(nil)
    # nichts mehr offen
    assert {[], :eof} = Reader.next_chunk(nil)
  end

  test "zwischen den Abschnitten gesetzte Operatoren und Flags gelten sofort", c do
    path = file(c, "a.pl", ":- op(700, xfx, ===>).\na ===> b.\n:- dq.\nx(\"ab\").\n")
    :ok = Reader.open_file(nil, path)
    assert {[_], :pause} = Reader.next_chunk(nil)
    PrologEx.Ops.add(700, "xfx", "===>")
    assert {items, :pause} = Reader.next_chunk(nil)
    assert names(items) == ["a===>b", ":-dq"]
    Reader.set_double_quotes(nil, "atom")
    assert {[{:term, {:gstruct, "x", [{:atom, "ab"}]}, _}], :eof} = Reader.next_chunk(nil)
  end

  test "ohne die Direktive auszuführen gilt der Operator nicht", c do
    path = file(c, "a.pl", ":- op(700, xfx, ===>).\na ===> b.\nok.\n")
    :ok = Reader.open_file(nil, path)
    assert {[_], :pause} = Reader.next_chunk(nil)
    assert {[{:error, msg}, {:term, {:atom, "ok"}, _}], :eof} = Reader.next_chunk(nil)
    assert msg =~ "Zeile 2"
  end

  test "Stapel: eine in einer Direktive geöffnete Datei wird zuerst gelesen", c do
    outer = file(c, "outer.pl", "o1.\n:- inc.\no2.\n")
    inner = file(c, "inner.pl", "i1.\ni2.\n")
    :ok = Reader.open_file(nil, outer)
    assert {items, :pause} = Reader.next_chunk(nil)
    assert names(items) == ["o1", ":-inc"]
    :ok = Reader.open_file(nil, inner)
    assert {items, :eof} = Reader.next_chunk(nil)
    assert names(items) == ["i1", "i2"]
    assert {items, :eof} = Reader.next_chunk(nil)
    assert names(items) == ["o2"]
  end

  test "end_of_file beendet die Datei; Byte-Order-Mark", c do
    path = file(c, "a.pl", <<0xEF, 0xBB, 0xBF>> <> "a.\nend_of_file.\nb.\n")
    :ok = Reader.open_file(nil, path)
    assert {items, :eof} = Reader.next_chunk(nil)
    assert names(items) == ["a"]
  end

  test "fehlende Datei", c do
    assert {:error, msg} = Reader.open_file(nil, Path.join(c.tmp_dir, "fehlt.pl"))
    assert msg =~ "fehlt.pl"
  end

  test "read_terms: Prozess-Schnittstelle ohne gprolog" do
    {:ok, r} = Reader.start_link()
    assert [{:term, {:struct, "f", [{:var, "X"}]}, %{"X" => "X"}}] = Reader.read_terms(r, "f(X).")
    assert Reader.available?()
    Reader.stop(r)
  end
end
