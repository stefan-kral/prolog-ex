defmodule PrologEx.ContTest do
  # library(cont): reset/3, shift/1 wie Scryer – Generator, Zustand als
  # Effekt, Backtracking vor shift/1, Schnitt und catch/3 in der
  # Fortsetzung (test/fixtures/cont/cont.pl; dieselben Ausgaben wie Scryer,
  # bis auf t4: Scryer scheitert bei shift/1 ohne reset/3)
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  alias PrologEx.Reader

  @expected %{
    "t1" => "[a,b,c]\n",
    "t2" => "30\n",
    "t3" => "none\n",
    "t4" => "error(existence_error(reset,x),_)\n",
    "t5" => "[1-k,2-k]\n",
    "t6" => "[1]\n",
    "t7" => "outer(oops)\n",
    "t8" => "3\n3\nok\n",
    "t9" => "end\na/b\n",
    "t10" => "[1]\n",
    "t11" => "20000\n"
  }

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    PrologEx.put_db(%{})
    {:ok, _} = PrologEx.Consult.load_file("test/fixtures/cont/cont.pl")
    {:ok, reader: r, db: PrologEx.current_db()}
  end

  for {t, exp} <- @expected do
    # t11: 20 000 Blätter eines links tiefen Baums, etwa 1 s; als jede
    # Fortsetzung noch alle offenen Ziele kopierte, quadratisch (Minuten)
    @tag timeout: 30_000
    test t, c do
      Reader.put_current(c.reader)
      [{:term, g, _}] = Reader.read_terms(c.reader, unquote(t) <> ".")

      out =
        capture_io(fn ->
          assert [_] = c.db |> PrologEx.query(g) |> Enum.take(1)
        end)

      # Variablennamen (_123) angleichen
      out = Regex.replace(~r/_[0-9A-Z]+/, out, "_")
      assert out == unquote(exp)
    end
  end
end
