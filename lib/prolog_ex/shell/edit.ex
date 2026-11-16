defmodule PrologEx.Shell.Edit do
  @moduledoc """
  Zeileneditor des Toplevels im Rohmodus (`PrologEx.Shell`). Tasten wie
  bei readline:

    * ←/→, Ctrl-B/Ctrl-F; Home/End, Ctrl-A/Ctrl-E; Alt-B/Alt-F (Wort)
    * Backspace, Entf; Ctrl-D: auf leerer Zeile Dateiende, sonst Zeichen
      unter dem Cursor löschen; Ctrl-U/Ctrl-K bis Zeilenanfang/-ende,
      Ctrl-W Wort davor; Ctrl-L Bildschirm leeren
    * ↑/↓, Ctrl-P/Ctrl-N: Verlauf (auch über Sitzungen hinweg, in
      `~/.prolog_ex_history`, die letzten 1000 Zeilen)
    * TAB: Ergänzen (`PrologEx.Shell.Complete`), mehrdeutig die Liste
    * Ctrl-C: Zeile verwerfen (`{:error, :interrupted}`)

  Lange Zeilen bricht das Terminal um; der Editor zeichnet die Zeile nach
  jeder Taste neu (Prompt samt Farbcodes, die für die Breite nicht zählen).
  """

  @hist_key :prolog_history
  @hist_max 1000

  @doc "Eine Zeile lesen (mit \\n), :eof (Ctrl-D auf leerer Zeile) oder {:error, :interrupted}"
  def read(prompt) do
    %{waiting: w} = PrologEx.Shell.state()
    :atomics.put(w, 1, 1)

    try do
      st = %{prompt: prompt, plen: visible_len(prompt), chars: [], pos: 0, row: 0, hist: nil}
      loop(render(st))
    after
      :atomics.put(w, 1, 0)
    end
  end

  defp loop(st) do
    case handle(key(), st) do
      {:cont, st} -> loop(st)
      {:done, result} -> result
    end
  end

  # --- Tasten -------------------------------------------------------------

  defp key do
    receive do
      {:prolog_key, "\e"} -> escape()
      {:prolog_key, c} -> c
    end
  end

  defp next do
    receive do
      {:prolog_key, c} -> c
    after
      50 -> nil
    end
  end

  defp escape do
    case next() do
      "[" -> csi("")
      "O" -> ss3(next())
      "b" -> :word_left
      "f" -> :word_right
      <<127>> -> :kill_word
      _ -> :ignore
    end
  end

  defp ss3("A"), do: :up
  defp ss3("B"), do: :down
  defp ss3("C"), do: :right
  defp ss3("D"), do: :left
  defp ss3("H"), do: :home
  defp ss3("F"), do: :end
  defp ss3(_), do: :ignore

  defp csi(acc) do
    case next() do
      c when c in ~w(0 1 2 3 4 5 6 7 8 9 ;) ->
        csi(acc <> c)

      "~" ->
        tilde(acc)

      c when c in ~w(C D) and acc in ["1;3", "1;5"] ->
        if c == "C", do: :word_right, else: :word_left

      c when c in ~w(A B C D H F) ->
        ss3(c)

      _ ->
        :ignore
    end
  end

  defp tilde("3"), do: :delete
  defp tilde(k) when k in ["1", "7"], do: :home
  defp tilde(k) when k in ["4", "8"], do: :end
  defp tilde(_), do: :ignore

  # --- Bearbeiten ---------------------------------------------------------

  defp handle(:eof, st), do: finish(st, :eof)

  defp handle(k, st) when k in ["\r", "\n"] do
    line = Enum.join(st.chars)
    add_history(line)
    finish(st, line <> "\n")
  end

  # Ctrl-D: auf leerer Zeile Dateiende, sonst Zeichen unter dem Cursor
  defp handle(<<4>>, %{chars: []} = st), do: finish(st, :eof)
  defp handle(<<4>>, st), do: handle(:delete, st)

  # Ctrl-C: Zeile verwerfen
  defp handle(<<3>>, st) do
    render(%{st | pos: length(st.chars)})
    IO.write("^C\r\n")
    {:done, {:error, :interrupted}}
  end

  defp handle("\t", st), do: complete(st)
  defp handle(k, st) when k in [<<127>>, <<8>>], do: backspace(st)

  defp handle(:delete, %{chars: cs, pos: p} = st) when p < length(cs),
    do: redraw(%{st | chars: List.delete_at(cs, p)})

  defp handle(k, st) when k in [:left, <<2>>], do: redraw(%{st | pos: max(st.pos - 1, 0)})

  defp handle(k, st) when k in [:right, <<6>>],
    do: redraw(%{st | pos: min(st.pos + 1, length(st.chars))})

  defp handle(k, st) when k in [:home, <<1>>], do: redraw(%{st | pos: 0})
  defp handle(k, st) when k in [:end, <<5>>], do: redraw(%{st | pos: length(st.chars)})
  defp handle(:word_left, st), do: redraw(%{st | pos: word_start(st.chars, st.pos)})
  defp handle(:word_right, st), do: redraw(%{st | pos: word_end(st.chars, st.pos)})
  defp handle(k, st) when k in [:up, <<16>>], do: history(st, 1)
  defp handle(k, st) when k in [:down, <<14>>], do: history(st, -1)

  # Ctrl-U, Ctrl-K, Ctrl-W
  defp handle(<<21>>, st), do: redraw(%{st | chars: Enum.drop(st.chars, st.pos), pos: 0})
  defp handle(<<11>>, st), do: redraw(%{st | chars: Enum.take(st.chars, st.pos)})

  defp handle(k, st) when k in [<<23>>, :kill_word] do
    s = word_start(st.chars, st.pos)
    redraw(%{st | chars: Enum.take(st.chars, s) ++ Enum.drop(st.chars, st.pos), pos: s})
  end

  # Ctrl-L
  defp handle(<<12>>, st) do
    IO.write("\e[H\e[2J")
    {:cont, render(%{st | row: 0})}
  end

  defp handle(c, st) when is_binary(c) do
    if printable?(c), do: insert(st, [c]), else: {:cont, st}
  end

  defp handle(_, st), do: {:cont, st}

  defp printable?(<<c, _::binary>>) when c < 32 or c == 127, do: false
  defp printable?(_), do: true

  defp insert(st, cs) do
    {a, b} = Enum.split(st.chars, st.pos)
    redraw(%{st | chars: a ++ cs ++ b, pos: st.pos + length(cs)})
  end

  defp backspace(%{pos: 0} = st), do: {:cont, st}

  defp backspace(st),
    do: redraw(%{st | chars: List.delete_at(st.chars, st.pos - 1), pos: st.pos - 1})

  defp word_start(cs, p) do
    before = cs |> Enum.take(p) |> Enum.reverse()
    skipped = Enum.drop_while(before, &(not word_char?(&1)))
    length(Enum.drop_while(skipped, &word_char?/1))
  end

  defp word_end(cs, p) do
    after_ = Enum.drop(cs, p)
    skipped = Enum.drop_while(after_, &(not word_char?(&1)))
    length(cs) - length(Enum.drop_while(skipped, &word_char?/1))
  end

  defp word_char?(c), do: c =~ ~r/^[\p{L}\p{N}_]$/u

  defp redraw(st), do: {:cont, render(st)}

  # Cursor ans Zeilenende, neue Zeile, Ergebnis
  defp finish(st, result) do
    render(%{st | pos: length(st.chars)})
    IO.write("\r\n")
    {:done, result}
  end

  # --- Anzeige ------------------------------------------------------------

  # Zeile neu zeichnen: zurück an den Anfang der Eingabe (st.row Zeilen
  # hinauf), bis Bildschirmende löschen, Prompt und Text, dann den Cursor
  # setzen. Ist die Zeile genau voll, steht der Cursor noch am Ende
  # (verzögerter Umbruch): dann selbst umbrechen
  defp render(st) do
    cols = columns()
    total = st.plen + length(st.chars)
    wrap = if total > 0 and rem(total, cols) == 0, do: "\r\n", else: ""
    end_row = div(total, cols)
    target = st.plen + st.pos
    trow = div(target, cols)
    tcol = rem(target, cols)

    IO.write([
      "\r",
      up(st.row),
      "\e[J",
      st.prompt,
      Enum.join(st.chars),
      wrap,
      up(end_row - trow),
      "\r",
      if(tcol > 0, do: "\e[#{tcol}C", else: "")
    ])

    %{st | row: trow}
  end

  defp up(0), do: ""
  defp up(n) when n > 0, do: "\e[#{n}A"

  defp columns do
    case :io.columns() do
      {:ok, c} when c > 0 -> c
      _ -> 80
    end
  end

  defp visible_len(prompt),
    do: prompt |> String.replace(~r/\e\[[0-9;?]*[A-Za-z]/, "") |> String.length()

  # --- TAB ----------------------------------------------------------------

  defp complete(st) do
    before =
      st.chars |> Enum.take(st.pos) |> Enum.join() |> String.to_charlist() |> Enum.reverse()

    case PrologEx.Shell.Complete.expand(before) do
      {:yes, ins, _} when ins != [] ->
        insert(st, ins |> List.to_string() |> String.graphemes())

      {_, _, [_ | _] = matches} ->
        st = render(%{st | pos: length(st.chars)})
        IO.write(["\r\n", :edlin_expand.format_matches(matches, columns())])
        {:cont, render(%{st | row: 0})}

      _ ->
        IO.write("\a")
        {:cont, st}
    end
  end

  # --- Verlauf ------------------------------------------------------------

  defp history(st, dir) do
    hist = Process.get(@hist_key, [])
    {idx, saved} = st.hist || {-1, st.chars}
    new = idx + dir

    cond do
      new == -1 ->
        redraw(%{st | chars: saved, pos: length(saved), hist: nil})

      new >= 0 and new < length(hist) ->
        cs = hist |> Enum.at(new) |> String.graphemes()
        redraw(%{st | chars: cs, pos: length(cs), hist: {new, saved}})

      true ->
        {:cont, st}
    end
  end

  defp add_history(line) do
    line = String.trim_trailing(line)
    hist = Process.get(@hist_key, [])

    unless line == "" or match?([^line | _], hist) do
      Process.put(@hist_key, Enum.take([line | hist], @hist_max))
      append_history_file(line)
    end
  end

  # (Tests: Anwendungsumgebung :history_file)
  defp history_file,
    do:
      Application.get_env(:prolog_ex, :history_file) ||
        Path.join(System.user_home() || ".", ".prolog_ex_history")

  @doc false
  def load_history do
    lines =
      case File.read(history_file()) do
        {:ok, text} -> text |> String.split("\n", trim: true) |> Enum.take(-@hist_max)
        _ -> []
      end

    Process.put(@hist_key, Enum.reverse(lines))

    # die Datei wächst nur durch Anhängen: ab und zu kürzen
    if length(lines) == @hist_max do
      File.write(history_file(), Enum.map(lines, &[&1, "\n"]))
    end
  rescue
    _ -> :ok
  end

  defp append_history_file(line) do
    File.write(history_file(), line <> "\n", [:append])
  rescue
    _ -> :ok
  end
end
