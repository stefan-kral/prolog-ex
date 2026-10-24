defmodule PrologEx.ReaderTest do
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag :gprolog

  # Jede Leseanfrage schickt ihre Endemarke zweimal; die zweite Antwort
  # kann (unter Last) erst ankommen, wenn der Reader schon die nächste
  # Datei-Anfrage bearbeitet – etwa nach op/3 aus einer Direktive, während
  # die Datei pausiert. Hier erzwungen: veraltete Marke hinter der Anfrage.
  @tag :tmp_dir
  test "veraltete Endemarke beim Weiterlesen einer Datei wird ignoriert", %{tmp_dir: dir} do
    {:ok, r} = Reader.start_link()
    file = Path.join(dir, "f.pl")
    File.write!(file, ":- dir.\na(1).\nb(2).\n")

    assert Reader.open_file(r, file) == :ok
    assert {[{:term, _, _}], :pause} = Reader.next_chunk(r)
    assert Reader.op(r, 700, "xfx", "===>") == :ok

    port = :sys.get_state(r).port
    :sys.suspend(r)
    task = Task.async(fn -> Reader.next_chunk(r) end)
    # warten, bis die Anfrage im Postfach des Readers liegt
    wait_queued(r)
    send(r, {port, {:data, {:eol, "batch_end(99)."}}})
    :sys.resume(r)

    assert {items, :eof} = Task.await(task)
    assert [{:term, {_, "a", [1]}, _}, {:term, {_, "b", [2]}, _}] = items

    # der Operator gilt
    assert [{:term, {:gstruct, "===>", [1, 2]}, _}] = Reader.read_terms(r, "1 ===> 2.")
  end

  defp wait_queued(r) do
    case Process.info(r, :message_queue_len) do
      {:message_queue_len, n} when n > 0 -> :ok
      _ -> Process.sleep(1) && wait_queued(r)
    end
  end
end
