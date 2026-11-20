defmodule PrologEx.SubAtomCostTest do
  # sub_atom/5 Zeichen für Zeichen über ein langes Atom: die Tabelle der
  # Zeichenpositionen (bzw. der ASCII-Test) entsteht einmal, nicht je
  # Aufruf – vorher O(Länge) je sub_atom, ein Durchgang O(n²) (40 000
  # Zeichen 2,8 s). Gezählt: Aufrufe von ascii?/1 (rekursiv, je Byte einer
  # bis zum ersten Nicht-ASCII-Zeichen), deterministisch. Die Anfrage läuft
  # im Testprozess (gezählt wird nur dort). async: false – die Zählung gilt
  # global
  use ExUnit.Case, async: false
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r, db: TableCase.db(r, ~w(lists between apply swi))}
  end

  defp count(c, q) do
    Reader.put_current(c.reader)
    [{:term, g, _}] = Reader.read_terms(c.reader, q)

    {_, {:call_count, rows}} =
      :tprof.profile(
        fn -> assert [_] = c.db |> PrologEx.query(g) |> Enum.take(1) end,
        %{type: :call_count, pattern: {PrologEx.Builtins.Atoms, :ascii?, 1}, report: :return}
      )

    Enum.sum(for {_m, _f, _a, l} <- rows, {_, n, _} <- l, do: n)
  end

  defp scan(code),
    do:
      "length(L, 5000), maplist(=(#{code}), L), atom_codes(A, L), " <>
        "forall(between(0, 4999, B), sub_atom(A, B, 1, _, _))."

  test "sub_atom/5 über ein langes Atom: die Positionen einmal", c do
    # ASCII: ein Aufbau ~ 5000 Aufrufe (vorher 5000 Aufbauten: 25 Mio.);
    # mindestens einer, sonst lief die Anfrage nicht
    n = count(c, scan(?a))
    assert n >= 5000 and n < 50_000, "#{n}"
    # nicht ASCII: je Aufbau einer (vorher 5000)
    n = count(c, scan(?ä))
    assert n >= 1 and n < 100, "#{n}"
  end
end
