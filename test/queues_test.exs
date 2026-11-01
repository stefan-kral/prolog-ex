defmodule PrologEx.QueuesTest do
  # library(queues): Scryer und SICStus 4 über derselben Darstellung
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)

    {db, []} =
      PrologEx.Consult.load(
        %{},
        Reader.read_terms(c.reader, """
        :- use_module(library(queues)).
        doppelt(X, Y) :- Y is 2 * X.
        gross(X) :- X > 1.
        """)
      )

    PrologEx.put_db(db)
    PrologEx.Flags.set("double_quotes", {:atom, "codes"})
    on_exit(fn -> PrologEx.Flags.reset() end)
    :ok
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(10)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  test "Scryer-API", c do
    assert ask(c, "queue(Q)") == ["Q = q(0,_A,_A)"]
    assert ask(c, "queue(a, Q), list_queue(L, Q)") |> hd() =~ "L = [a]"

    assert ask(
             c,
             "queue(Q0), queue_last(a, Q0, Q1), queue_last(b, Q1, Q2), queue_head(x, Q2, Q3), list_queue(L, Q3), queue_length(Q3, N)"
           )
           |> hd() =~
             "L = [x,a,b], N = 3"

    # abnehmen vorn: queue_head/3 rückwärts
    assert ask(c, "list_queue([a,b,c], Q), queue_head(X, Q1, Q), list_queue(L, Q1)") |> hd() =~
             "L = [b,c]"

    assert ask(
             c,
             "list_queue([c], Q0), queue_head_list([a,b], Q0, Q1), queue_last_list([d,e], Q1, Q), list_queue(L, Q)"
           )
           |> hd() =~
             "L = [a,b,c,d,e]"

    assert ask(c, "queue(Q), queue_head(_, _, Q)") == []
  end

  test "SICStus-4-API", c do
    assert ask(c, "empty_queue(Q), queue_length(Q, N)") |> hd() =~ "N = 0"
    assert ask(c, "list_queue([a], Q), empty_queue(Q)") == []
    assert ask(c, "singleton_queue(a, Q), queue_list(Q, L)") |> hd() =~ "L = [a]"
    q = "list_queue([a,b,c], Q), "
    assert ask(c, q <> "queue_head(Q, H)") |> hd() =~ "H = a"
    assert ask(c, "empty_queue(Q), queue_head(Q, _)") == []
    assert ask(c, q <> "queue_tail(Q, T), queue_list(T, L)") |> hd() =~ "L = [b,c]"
    assert ask(c, q <> "queue_cons(x, Q, Q1), queue_list(Q1, L)") |> hd() =~ "L = [x,a,b,c]"
    assert ask(c, q <> "queue_cons(H, T, Q), queue_list(T, L)") |> hd() =~ "H = a, L = [b,c]"
    assert ask(c, q <> "queue_last(X, Q)") |> hd() =~ "X = c"
    assert ask(c, "empty_queue(Q), queue_last(_, Q)") == []

    assert ask(c, q <> "append_queue([x,y], Q, Q1), queue_list(Q1, L)") |> hd() =~
             "L = [x,y,a,b,c]"

    assert ask(c, q <> "append_queue([X,Y], Q1, Q), queue_list(Q1, L)") |> hd() =~
             ~r/L = \[c\], .*X = a, Y = b/

    assert ask(c, q <> "queue_append(Q, [d,e], Q1), queue_list(Q1, L)") |> hd() =~
             "L = [a,b,c,d,e]"

    # queue_length/2 erzeugt auch (SICStus)
    assert ask(c, "queue_length(Q, 2), queue_list(Q, L)") |> hd() =~ ~r/L = \[_\w+,_\w+\]/
    assert ask(c, q <> "findall(X, queue_member(X, Q), L)") |> hd() =~ "L = [a,b,c]"
    assert ask(c, q <> "queue_memberchk(b, Q)") |> length() == 1
    assert ask(c, q <> "queue_memberchk(x, Q)") == []
  end

  test "erzeugte Warteschlangen sind wohlgeformt", c do
    assert ask(c, "queue_length(Q, 2), is_queue(Q)") |> length() == 1
    assert ask(c, "once(queue_last(x, Q)), is_queue(Q)") |> length() == 1

    assert ask(c, "list_queue([1,2], Q), map_queue(doppelt, Q, Q2), is_queue(Q2)") |> length() ==
             1

    assert ask(c, "map_list_queue(doppelt, [1,2], Q), is_queue(Q)") |> length() == 1
    # verschieden lang: scheitert
    assert ask(c, "list_queue([1,2,3], Q), list_queue([2], R), some_queue(doppelt, Q, R)") == []
  end

  test "is_queue/1", c do
    assert ask(c, "list_queue([1,2], Q), is_queue(Q)") |> length() == 1
    assert ask(c, "empty_queue(Q), is_queue(Q)") |> length() == 1
    assert ask(c, "is_queue(_)") == []
    assert ask(c, "is_queue(foo)") == []
    assert ask(c, "is_queue(q(_, [], []))") == []
    assert ask(c, "is_queue(q(s(0), [a,b], [b]))") == ["true"]
    assert ask(c, "is_queue(q(s(s(0)), [a,b], [b]))") == []
    assert ask(c, "is_queue(q(s(0), _, []))") == []
  end

  test "Abbilden", c do
    q = "list_queue([1,2,3], Q), "
    assert ask(c, q <> "map_queue(integer, Q)") |> length() == 1
    assert ask(c, q <> "map_queue(gross, Q)") == []
    assert ask(c, q <> "map_queue(doppelt, Q, Q2), queue_list(Q2, L)") |> hd() =~ "L = [2,4,6]"
    assert ask(c, q <> "map_queue_list(doppelt, Q, L)") |> hd() =~ "L = [2,4,6]"
    assert ask(c, "map_list_queue(doppelt, [1,2], Q), queue_list(Q, L)") |> hd() =~ "L = [2,4]"
    assert ask(c, "map_queue_list(=, Q, [a,b]), queue_list(Q, L)") |> hd() =~ "L = [a,b]"
    assert ask(c, q <> "findall(x, some_queue(gross, Q), L)") |> hd() =~ "L = [x,x]"
    assert ask(c, q <> "findall(x, somechk_queue(gross, Q), L)") |> hd() =~ "L = [x]"

    assert ask(c, q <> "list_queue([1,4,9], R), findall(X, some_queue(doppelt, Q, R), L)") |> hd() =~
             "L = [_"

    assert ask(c, q <> "list_queue([5,4,6], R), findall(x, some_queue(doppelt, Q, R), L)") |> hd() =~
             "L = [x,x]"

    assert ask(c, q <> "list_queue([5,4,6], R), findall(x, somechk_queue(doppelt, Q, R), L)")
           |> hd() =~ "L = [x]"
  end

  test "portray_queue/1", c do
    out =
      ExUnit.CaptureIO.capture_io(fn -> ask(c, "list_queue([a,'b c',1], Q), portray_queue(Q)") end)

    assert out == "Queue[a,'b c',1]"

    assert ExUnit.CaptureIO.capture_io(fn -> ask(c, "empty_queue(Q), portray_queue(Q)") end) ==
             "Queue[]"
  end
end
