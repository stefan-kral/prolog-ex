defmodule PrologEx.Builtins.BytesLazy do
  @moduledoc """
  Hilfsprädikate für `library(dcg/bytes)` (`priv/library/dcg/bytes.pl`):
  eine Byte-Folge als faule Liste.

  Die Liste besteht aus Blöcken von 4096 Bytes ab einem Versatz. Ihr noch
  nicht ausgepackter Rest ist eine Variable, die mit `freeze/2` auf
  `dcg_bytes:'$bytes_fill'(B, Sicht, Versatz, Rest)` wartet. Anders als
  beim Stream (`library(pio)`) ist nichts zu merken: die Byte-Folge ist
  unveränderlich, nach dem Rücksetzen wird der Block einfach neu erzeugt.

  Sichten: `codes` (Zahlen 0..255), `latin1` (ein Zeichen je Byte),
  `utf8` (dekodierte Zeichen; ein Block endet an einer Zeichengrenze).
  """
  use PrologEx.Builtin
  alias PrologEx.{Error, Store}

  @block 4096

  # '$bytes_block'(B, Sicht, Versatz, L, T, Versatz1): L = die Elemente ab
  # Versatz (ein Block), dahinter T; am Ende L = []
  defbuiltin "$bytes_block", [b, view, off, l, t, off1] do
    {:bytes, bin} = deref(b)
    o = deref(off)
    n = byte_size(bin)

    if o >= n do
      {:unify, [{l, []}, {off1, o}]}
    else
      chunk = :binary.part(bin, o, min(@block, n - o))
      {items, used} = items(deref(view), chunk, o + byte_size(chunk) == n)
      {:unify, [{l, list(items, t)}, {off1, o + used}]}
    end
  end

  defp items({:atom, "codes"}, chunk, _last), do: {:binary.bin_to_list(chunk), byte_size(chunk)}

  defp items({:atom, "latin1"}, chunk, _last),
    do: {for(<<c <- chunk>>, do: a(<<c::utf8>>)), byte_size(chunk)}

  defp items({:atom, "utf8"}, chunk, last) do
    case :unicode.characters_to_list(chunk, :utf8) do
      cs when is_list(cs) ->
        {Enum.map(cs, &a(<<&1::utf8>>)), byte_size(chunk)}

      # ein Zeichen über die Blockgrenze: der Block endet davor
      {:incomplete, cs, rest} when not last and cs != [] ->
        {Enum.map(cs, &a(<<&1::utf8>>)), byte_size(chunk) - byte_size(rest)}

      _ ->
        Error.representation!("character")
    end
  end

  # '$bytes_rest'(T, Sicht, Versatz, B, R): T ist ein Rest der faulen Liste,
  # Versatz der des noch wartenden Rests dahinter (oder das Ende); R = die
  # Bytes ab T, ohne Kopie
  defbuiltin "$bytes_rest", [t, view, off, b, r] do
    s = subst()
    {:bytes, bin} = deref(b)
    used = before(Store.walk(t, s), deref(view), s, 0)
    start = deref(off) - used
    {:unify, [{r, {:bytes, :binary.part(bin, start, byte_size(bin) - start)}}]}
  end

  # Bytes der schon ausgepackten Elemente bis zum Ende oder zum wartenden Rest
  defp before({:glist, l}, view, s, acc), do: before(l, view, s, acc)

  defp before([h | t], view, s, acc),
    do: before(Store.walk(t, s), view, s, acc + size(Store.walk(h, s), view))

  defp before(_, _view, _s, acc), do: acc

  defp size({:atom, c}, {:atom, "utf8"}), do: byte_size(c)
  defp size(_, _), do: 1
end
