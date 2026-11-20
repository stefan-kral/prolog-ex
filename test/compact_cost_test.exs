defmodule PrologEx.CompactCostTest do
  # Die Arbeit der Kompaktierung bleibt amortisiert linear, auch wenn ein
  # lebender Term eine lange ground Liste hinter einem nicht-ground Anfang
  # hat (die Fortsetzung über einen links tiefen Baum: N ground Ziele hinter
  # wenigen offenen). Gezählt: Aufrufe von compact_spine/5 (je Zelle einer),
  # deterministisch statt Zeit. Vorher zählten die ground Zellen nicht als
  # Kosten, die Schwelle blieb klein, und jede Kompaktierung lief über die
  # ganze Liste: viermal so viele Blätter, sechzehnmal so viele Zellen.
  # async: false – die Zählung gilt für alle Prozesse
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    PrologEx.put_db(%{})
    {:ok, _} = PrologEx.Consult.load_file("test/fixtures/cont/cont.pl")
    {:ok, reader: r, db: PrologEx.current_db()}
  end

  defp cells(c, n) do
    Reader.put_current(c.reader)
    [{:term, g, _}] = Reader.read_terms(c.reader, "left(#{n}, T), count(leaves(T), 0, N).")

    {_, {:call_count, rows}} =
      :tprof.profile(
        fn -> capture_io(fn -> [_] = c.db |> PrologEx.query(g) |> Enum.take(1) end) end,
        %{type: :call_count, pattern: {PrologEx, :compact_spine, 5}, report: :return}
      )

    Enum.sum(for {_m, _f, _a, l} <- rows, {_, n, _} <- l, do: n)
  end

  @tag timeout: 60_000
  test "Same Fringe über einen links tiefen Baum: Kompaktierung linear", c do
    small = cells(c, 4000)
    big = cells(c, 16000)
    assert big < 8 * max(small, 1), "#{small} Zellen bei 4000, #{big} bei 16000"
  end
end
