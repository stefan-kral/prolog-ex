defmodule PrologEx.Builtins.Pio do
  @moduledoc """
  Hilfsprädikate für `library(pio)` (priv/library/pio.pl): Blöcke der
  faulen Liste lesen und Positionen in ihr bestimmen.

  Die faule Liste eines Streams besteht aus Blöcken (Nr. 0, 1, ...). Ihr
  noch nicht gelesener Rest ist eine Variable, die mit `freeze/2` auf
  `pio:'$lazy_fill'(Stream, Nr, Typ, Rest)` wartet. Wird sie gebunden,
  liest `'$lazy_block'/5` den Block (oder nimmt den gemerkten: nach dem
  Rücksetzen wird nicht neu gelesen, der Stream ist ja schon weiter) und
  liefert seine Zeichen mit einem neuen wartenden Rest.
  """
  use PrologEx.Builtin
  alias PrologEx.Builtins.IO, as: PIO
  alias PrologEx.Builtins.Blackboard
  alias PrologEx.Stream, as: S

  # --- phrase_to_file/2,3: Schreiben, das Backtracking zurücknimmt ---------
  #
  # Die Position, bis zu der eine Lösung geschrieben hat, steht backtrackbar
  # in der Substitution (wie b_setval/2). Vor dem Schreiben der nächsten
  # Lösung und beim Schließen geht der Stream dorthin zurück und die Datei
  # wird dort abgeschnitten: am Ende steht nur, was die zuletzt gültige
  # Lösung geschrieben hat. Nur für Dateien, die sich positionieren lassen
  # (open(..., write, ...) mit reposition(true), der Vorgabe); sonst wie
  # bisher.

  # '$pio_mark'(S): jetzige Position merken (backtrackbar)
  defbuiltin "$pio_mark", [stream] do
    id = S.lookup!(deref(stream))
    S.flush(id)
    s = S.get(id)
    mark = {:struct, "$p", [s.chars, s.lines, s.line_pos, s.bytes]}
    {:subst, Blackboard.b_put(subst(), "$pio", "#{id}", mark)}
  end

  # '$pio_rewind'(S): zur gemerkten Position, dahinter abschneiden
  defbuiltin "$pio_rewind", [stream] do
    id = S.lookup!(deref(stream))
    s = S.get(id)

    with true <- s.kind == :file and s.reposition and s.mode == :write,
         {:ok, {:struct, "$p", [c, l, lp, b]}} <- Blackboard.b_value("$pio", "#{id}", subst()) do
      S.set_position(id, c, l, lp, b)
      S.truncate(id)
    end

    true
  end

  @block 256

  # '$lazy_start'(S, K): S ist ein Eingabe-Textstream; K = Nr. des nächsten
  # Blocks (eine zweite faule Liste desselben Streams beginnt dort)
  defbuiltin "$lazy_start", [stream, k] do
    id = PIO.input!(deref(stream), :text)
    {blocks, _} = S.lazy_blocks(id)
    {:unify, [{k, map_size(blocks)}]}
  end

  # '$lazy_block'(S, K, Typ, L, T): L = Zeichen von Block K, dahinter T;
  # am Ende L = []
  defbuiltin "$lazy_block", [stream, k, type, l, t] do
    id = PIO.input!(deref(stream), :text)
    {_, text} = S.lazy_block(id, deref(k), @block)

    case text do
      "" ->
        {:unify, [{l, []}]}

      _ ->
        item =
          case deref(type) do
            {:atom, "codes"} -> & &1
            _ -> &a(<<&1::utf8>>)
          end

        {:unify, [{l, list(for(<<c::utf8 <- text>>, do: item.(c)), t)}]}
    end
  end

  # '$lazy_position'(S, K, Zurück, Pos): Position Zurück Zeichen vor dem
  # Anfang von Block K, als pos(Zeichen, Zeile, Spalte)
  defbuiltin "$lazy_position", [stream, k, back, pos] do
    id = S.lookup!(deref(stream))
    {blocks, now} = S.lazy_blocks(id)
    k = deref(k)

    {c0, _, _} =
      case blocks do
        %{^k => {c, l, p, _}} -> {c, l, p}
        _ -> now
      end

    char = c0 - deref(back)

    # Block, in dem das Zeichen liegt (oder der Anfang des ungelesenen Rests)
    {line, col} =
      Enum.find_value(blocks, fn {_, {c, l, p, text}} ->
        n = String.length(text)
        if char >= c and char < c + n, do: walk_to(text, char - c, l, p)
      end) || {elem(now, 1), elem(now, 2)}

    {:unify, [{pos, mk("pos", [char, line, col])}]}
  end

  defp walk_to(_text, 0, l, p), do: {l, p}
  defp walk_to(<<?\n::utf8, rest::binary>>, n, l, _p), do: walk_to(rest, n - 1, l + 1, 0)
  defp walk_to(<<_::utf8, rest::binary>>, n, l, p), do: walk_to(rest, n - 1, l, p + 1)
end
