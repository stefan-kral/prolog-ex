defmodule PrologEx.Builtins.Bytes do
  @moduledoc """
  `library(bytes)`: Byte-Folgen als eigener atomarer Typ.

  Eine Byte-Folge ist ein BEAM-Binary (`{:bytes, <<...>>}`): kompakt (ein
  Byte je Byte statt einer Listenzelle von 16), Länge und Zugriff in O(1),
  ein Teilstück ist ein Verweis ohne Kopie, und ab 64 Bytes teilen
  Prozesse sie, statt sie zu kopieren (library(concurrent)).

  Wie eine Zahl atomar: `atomic/1` ja, `atom/1` nein; Unifikation und `==`
  vergleichen den Inhalt; in der Standardordnung nach den Atomen und vor
  dem Zusammengesetzten, untereinander Byte für Byte (ein Präfix zuerst).
  Kein Literal: `write/1` und `writeq/1` geben `'$bytes'(Länge)` aus (nicht
  wieder einlesbar, wie Streams); den Inhalt zeigen `bytes_list/2`,
  `bytes_hex/2` und Verwandte. Positionen zählen ab 0 (Byte-Versatz).

    * `bytes(B)` – B ist eine Byte-Folge
    * `bytes_list(B, Bytes)` – Liste der Bytes (0..255)
    * `bytes_utf8(B, Text)`, `bytes_latin1(B, Text)` – Text als Zeichen;
      umgekehrt auch Codes oder ein Atom; ungültiges UTF-8 bzw. ein Zeichen
      über 255: `representation_error(character)`
    * `bytes_hex(B, Hex)`, `bytes_base64(B, Text)` – Kodierungen (Zeichen);
      ungültig: `domain_error(hex_encoding | base64_encoding, Text)`
    * `bytes_length(B, N)`, `bytes_at(I, B, Byte)` (I frei: alle)
    * `sub_bytes(B, Vor, Länge, Nach, Teil)` – wie `sub_atom/5`
    * `bytes_concat(A, B, AB)` (AB gegeben: alle Teilungen),
      `bytes_concat_list(Liste, B)`
    * `bytes_search(Muster, B, Pos)` – jedes Vorkommen, auch überlappend
    * Bits: `bytes_fill(N, Byte, B)` (N gleiche Bytes),
      `bytes_and/3`, `bytes_or/3`, `bytes_xor/3` (gleich lang, sonst
      `domain_error(same_length, B)`), `bytes_not/2`, `bytes_popcount/2`,
      `bytes_bit(I, B, Bit)` (I frei: alle), `bytes_set_bit(I, B0, Bit, B)`
      (eine neue Folge, O(n)); Bit 0 ist das höchste Bit des ersten Bytes
    * `read_file_to_bytes(Datei, B)`, `write_bytes(Stream, B)`,
      `get_bytes(Stream, N, B)` (höchstens N; am Ende die leere Folge) auf
      Binär-Streams
  """
  use PrologEx.Builtin, module: "bytes"
  import Bitwise
  alias PrologEx.{Error, Store}
  alias PrologEx.Stream, as: S

  # --- Typ und Umwandeln ------------------------------------------------------

  defbuiltin "bytes", [b] do
    match?({:bytes, _}, deref(b))
  end

  defbuiltin "bytes_list", [b, l] do
    s = subst()

    case walk(b, s) do
      {:bytes, bin} ->
        {:unify, [{l, list(:binary.bin_to_list(bin))}]}

      {:var, _} ->
        bin = for x <- items!(l, s), into: <<>>, do: <<byte!(x, s)>>
        {:unify, [{b, {:bytes, bin}}]}

      other ->
        Error.type!("bytes", PrologEx.resolve(other, s))
    end
  end

  defbuiltin "bytes_utf8", [b, t] do
    s = subst()

    case walk(b, s) do
      {:bytes, bin} ->
        unless String.valid?(bin), do: Error.representation!("character")
        {:unify, [{t, chars(bin)}]}

      {:var, _} ->
        {:unify, [{b, {:bytes, text!(t, s)}}]}

      other ->
        Error.type!("bytes", PrologEx.resolve(other, s))
    end
  end

  defbuiltin "bytes_latin1", [b, t] do
    s = subst()

    case walk(b, s) do
      {:bytes, bin} ->
        {:unify, [{t, list(for <<c <- bin>>, do: a(<<c::utf8>>))}]}

      {:var, _} ->
        bin =
          for <<c::utf8 <- text!(t, s)>>, into: <<>> do
            if c > 255, do: Error.representation!("character"), else: <<c>>
          end

        {:unify, [{b, {:bytes, bin}}]}

      other ->
        Error.type!("bytes", PrologEx.resolve(other, s))
    end
  end

  defbuiltin "bytes_hex", [b, t] do
    s = subst()

    case walk(b, s) do
      {:bytes, bin} ->
        {:unify, [{t, chars(Base.encode16(bin, case: :lower))}]}

      {:var, _} ->
        text = text!(t, s)

        case Base.decode16(text, case: :mixed) do
          {:ok, bin} -> {:unify, [{b, {:bytes, bin}}]}
          :error -> Error.domain!("hex_encoding", PrologEx.resolve(t, s))
        end

      other ->
        Error.type!("bytes", PrologEx.resolve(other, s))
    end
  end

  defbuiltin "bytes_base64", [b, t] do
    s = subst()

    case walk(b, s) do
      {:bytes, bin} ->
        {:unify, [{t, chars(Base.encode64(bin))}]}

      {:var, _} ->
        case Base.decode64(text!(t, s)) do
          {:ok, bin} -> {:unify, [{b, {:bytes, bin}}]}
          :error -> Error.domain!("base64_encoding", PrologEx.resolve(t, s))
        end

      other ->
        Error.type!("bytes", PrologEx.resolve(other, s))
    end
  end

  # --- Größe, Zugriff, Teilstücke ---------------------------------------------

  defbuiltin "bytes_length", [b, n] do
    s = subst()
    bin = bytes!(b, s)
    int_or_var!(n, s)
    {:unify, [{n, byte_size(bin)}]}
  end

  defbuiltin "bytes_at", [i, b, x], nondet: true do
    s = subst()
    bin = bytes!(b, s)

    case int_or_var!(i, s) do
      nil ->
        at_all(bin, 0, i, x)

      k when k >= 0 and k < byte_size(bin) ->
        [{:unify, [{x, :binary.at(bin, k)}]}]

      _ ->
        []
    end
  end

  defp at_all(bin, k, _i, _x) when k >= byte_size(bin), do: []

  defp at_all(bin, k, i, x) do
    r = {:unify, [{i, k}, {x, :binary.at(bin, k)}]}
    if k + 1 == byte_size(bin), do: [r], else: [r | fn -> at_all(bin, k + 1, i, x) end]
  end

  defbuiltin "sub_bytes", [b, before, len, aft, sub], nondet: true do
    s = subst()
    bin = bytes!(b, s)
    n = byte_size(bin)
    bv = int_or_var!(before, s)
    lv = int_or_var!(len, s)
    av = int_or_var!(aft, s)

    case walk(sub, s) do
      {:bytes, pat} ->
        for p <- occurrences(bin, pat),
            l = byte_size(pat),
            ok?(bv, p) and ok?(lv, l) and ok?(av, n - p - l),
            do: {:unify, [{before, p}, {len, l}, {aft, n - p - l}]}

      {:var, _} ->
        for {p, l} <- spans(n, bv, lv, av),
            do: {:unify, [{before, p}, {len, l}, {aft, n - p - l}, {sub, part(bin, p, l)}]}

      other ->
        Error.type!("bytes", PrologEx.resolve(other, s))
    end
  end

  defp ok?(nil, _), do: true
  defp ok?(k, v), do: k == v

  # alle {Vor, Länge} passend zu den gegebenen Zahlen (lazy, wie sub_atom/5)
  defp spans(n, b, l, a) do
    cond do
      b != nil and l != nil -> if b + l <= n, do: [{b, l}], else: []
      b != nil and a != nil -> if b + a <= n, do: [{b, n - b - a}], else: []
      l != nil and a != nil -> if l + a <= n, do: [{n - l - a, l}], else: []
      b != nil -> if b <= n, do: Stream.map(0..(n - b)//1, &{b, &1}), else: []
      l != nil -> if l <= n, do: Stream.map(0..(n - l)//1, &{&1, l}), else: []
      a != nil -> if a <= n, do: Stream.map(0..(n - a)//1, &{&1, n - a - &1}), else: []
      true -> Stream.flat_map(0..n//1, fn p -> Stream.map(0..(n - p)//1, &{p, &1}) end)
    end
  end

  # Teilstück ohne Kopie (ein Verweis auf das Binary)
  defp part(bin, p, l), do: {:bytes, :binary.part(bin, p, l)}

  defbuiltin "bytes_concat", [x, y, xy], nondet: true do
    s = subst()

    case {walk(x, s), walk(y, s), walk(xy, s)} do
      {{:bytes, a}, {:bytes, b}, _} ->
        [{:unify, [{xy, {:bytes, a <> b}}]}]

      {_, _, {:bytes, ab}} ->
        n = byte_size(ab)

        case {bytes_or_var!(x, s), bytes_or_var!(y, s)} do
          {nil, nil} ->
            Stream.map(0..n//1, fn k ->
              {:unify, [{x, part(ab, 0, k)}, {y, part(ab, k, n - k)}]}
            end)

          {a, nil} ->
            k = byte_size(a)

            if k <= n and :binary.part(ab, 0, k) == a,
              do: [{:unify, [{y, part(ab, k, n - k)}]}],
              else: []

          {nil, b} ->
            k = byte_size(b)

            if k <= n and :binary.part(ab, n - k, k) == b,
              do: [{:unify, [{x, part(ab, 0, n - k)}]}],
              else: []
        end

      {a, b, _} ->
        # mit freier Verbindung müssen beide Teile da sein
        bytes!(a, s)
        bytes!(b, s)
        []
    end
  end

  defbuiltin "bytes_concat_list", [l, b] do
    s = subst()
    parts = for x <- items!(l, s), do: bytes!(x, s)
    {:unify, [{b, {:bytes, IO.iodata_to_binary(parts)}}]}
  end

  defbuiltin "bytes_search", [pat, b, pos], nondet: true do
    s = subst()
    p = bytes!(pat, s)
    bin = bytes!(b, s)

    case int_or_var!(pos, s) do
      nil ->
        for k <- occurrences(bin, p), do: {:unify, [{pos, k}]}

      k ->
        if k >= 0 and k + byte_size(p) <= byte_size(bin) and
             :binary.part(bin, k, byte_size(p)) == p,
           do: [:ok],
           else: []
    end
  end

  # Positionen aller Vorkommen, auch überlappend, aufsteigend (lazy)
  defp occurrences(bin, <<>>), do: 0..byte_size(bin)//1

  defp occurrences(bin, pat) do
    cp = :binary.compile_pattern(pat)

    Stream.unfold(0, fn start ->
      n = byte_size(bin)

      if start > n - byte_size(pat) do
        nil
      else
        case :binary.match(bin, cp, scope: {start, n - start}) do
          {k, _} -> {k, k + 1}
          :nomatch -> nil
        end
      end
    end)
  end

  # --- Bits -------------------------------------------------------------------
  #
  # Bit I: Byte I div 8, darin von oben (Bit 0 ist das höchste Bit des
  # ersten Bytes, wie Erlangs Bit-Syntax und die Netzwerk-Reihenfolge).
  # and/or/xor über zwei gleich lange Folgen: als eine große Ganzzahl
  # gerechnet (in C, ein Durchlauf).

  defbuiltin "bytes_fill", [n, byte, b] do
    s = subst()

    k =
      case int_or_var!(n, s) do
        nil -> Error.instantiation!()
        k when k < 0 -> Error.domain!("not_less_than_zero", k)
        k -> k
      end

    {:unify, [{b, {:bytes, :binary.copy(<<byte!(byte, s)>>, k)}}]}
  end

  defbuiltin "bytes_and", [x, y, z] do
    bitwise(x, y, z, subst(), &band/2)
  end

  defbuiltin "bytes_or", [x, y, z] do
    bitwise(x, y, z, subst(), &bor/2)
  end

  defbuiltin "bytes_xor", [x, y, z] do
    bitwise(x, y, z, subst(), &bxor/2)
  end

  defbuiltin "bytes_not", [x, z] do
    a = bytes!(x, subst())
    ones = :binary.copy(<<255>>, byte_size(a))
    {:unify, [{z, {:bytes, IO.iodata_to_binary(chunks(a, ones, &bxor/2, 0, []))}}]}
  end

  defbuiltin "bytes_popcount", [x, c] do
    {:unify, [{c, popcount(bytes!(x, subst()), 0)}]}
  end

  defbuiltin "bytes_bit", [i, x, bit], nondet: true do
    s = subst()
    a = bytes!(x, s)

    case int_or_var!(i, s) do
      nil -> bits_all(a, 0, bit_size(a), i, bit)
      k when k >= 0 and k < bit_size(a) -> [{:unify, [{bit, bit_at(a, k)}]}]
      _ -> []
    end
  end

  defbuiltin "bytes_set_bit", [i, x, bit, z] do
    s = subst()
    a = bytes!(x, s)

    k =
      case int_or_var!(i, s) do
        nil -> Error.instantiation!()
        k when k >= 0 and k < bit_size(a) -> k
        k -> Error.domain!("bit_index", k)
      end

    v =
      case walk(bit, s) do
        b when b in [0, 1] -> b
        {:var, _} -> Error.instantiation!()
        other -> Error.type!("bit", PrologEx.resolve(other, s))
      end

    <<pre::bits-size(^k), _::1, post::bits>> = a
    {:unify, [{z, {:bytes, <<pre::bits, v::1, post::bits>>}}]}
  end

  defp bitwise(x, y, z, s, op) do
    a = bytes!(x, s)
    b = bytes!(y, s)

    if byte_size(a) != byte_size(b),
      do: Error.domain!("same_length", PrologEx.resolve(y, s))

    {:unify, [{z, {:bytes, IO.iodata_to_binary(chunks(a, b, op, 0, []))}}]}
  end

  # Ganzzahlen sind auf einige Millionen Bits begrenzt: in Stücken zu 64 KB
  @chunk 65536

  defp chunks(a, _b, _op, off, acc) when off >= byte_size(a), do: Enum.reverse(acc)

  defp chunks(a, b, op, off, acc) do
    k = min(@chunk, byte_size(a) - off)
    n = 8 * k
    <<i::size(^n)>> = :binary.part(a, off, k)
    <<j::size(^n)>> = :binary.part(b, off, k)
    chunks(a, b, op, off + k, [<<op.(i, j)::size(n)>> | acc])
  end

  defp bit_at(a, k) do
    <<_::bits-size(^k), v::1, _::bits>> = a
    v
  end

  # mit freiem I: jedes Bit der Reihe nach (lazy)
  defp bits_all(_a, k, n, _i, _bit) when k >= n, do: []

  defp bits_all(a, k, n, i, bit) do
    r = {:unify, [{i, k}, {bit, bit_at(a, k)}]}
    if k + 1 == n, do: [r], else: [r | fn -> bits_all(a, k + 1, n, i, bit) end]
  end

  # gesetzte Bits: je 32 Bit auf einmal (SWAR, bleibt eine kleine Ganzzahl),
  # der Rest byteweise
  defp popcount(<<w::32, rest::binary>>, acc) do
    w = w - (w >>> 1 &&& 0x55555555)
    w = (w &&& 0x33333333) + (w >>> 2 &&& 0x33333333)
    w = w + (w >>> 4) &&& 0x0F0F0F0F
    popcount(rest, acc + ((w * 0x01010101) >>> 24 &&& 0xFF))
  end

  defp popcount(<<b, rest::binary>>, acc), do: popcount(<<0, 0, 0, b>> <> rest, acc)
  defp popcount(<<>>, acc), do: acc

  # --- Dateien und Streams ----------------------------------------------------

  defbuiltin "read_file_to_bytes", [file, b] do
    s = subst()
    path = file_name!(file, s)

    case File.read(path) do
      {:ok, bin} -> {:unify, [{b, {:bytes, bin}}]}
      {:error, :enoent} -> Error.existence!("source_sink", PrologEx.resolve(file, s))
      {:error, _} -> Error.permission!("open", "source_sink", PrologEx.resolve(file, s))
    end
  end

  defbuiltin "write_bytes", [stream, b] do
    s = subst()
    bin = bytes!(b, s)
    id = PrologEx.Builtins.IO.output!(deref(stream), :binary)
    S.put_bytes(id, bin)
  end

  defbuiltin "get_bytes", [stream, n, b] do
    s = subst()
    st = deref(stream)

    k =
      case int_or_var!(n, s) do
        nil -> Error.instantiation!()
        k when k < 0 -> Error.domain!("not_less_than_zero", k)
        k -> k
      end

    id = PrologEx.Builtins.IO.input!(st, :binary)
    {:unify, [{b, {:bytes, S.get_bytes(id, k)}}]}
  end

  # --- Hilfen -----------------------------------------------------------------

  defp walk(t, s), do: PrologEx.unmark_top(Store.walk(t, s))

  defp bytes!(t, s) do
    case walk(t, s) do
      {:bytes, bin} -> bin
      {:var, _} -> Error.instantiation!()
      other -> Error.type!("bytes", PrologEx.resolve(other, s))
    end
  end

  defp bytes_or_var!(t, s) do
    case walk(t, s) do
      {:var, _} -> nil
      _ -> bytes!(t, s)
    end
  end

  defp int_or_var!(t, s) do
    case walk(t, s) do
      {:var, _} -> nil
      n when is_integer(n) -> n
      other -> Error.type!("integer", PrologEx.resolve(other, s))
    end
  end

  defp byte!(t, s) do
    case Store.walk(t, s) do
      n when is_integer(n) and n >= 0 and n <= 255 -> n
      {:var, _} -> Error.instantiation!()
      other -> Error.type!("byte", PrologEx.resolve(other, s))
    end
  end

  # echte Liste: Teilliste instantiation_error, sonst type_error(list, L)
  defp items!(l, s) do
    case PrologEx.Builtins.Lists.skip_list(l, s) do
      {_, []} -> PrologEx.Builtins.Lists.items(l, s)
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(l, s))
    end
  end

  # Text: Atom, Zeichen- oder Codeliste
  defp text!(t, s) do
    case walk(t, s) do
      {:atom, n} ->
        n

      [] ->
        ""

      {:var, _} ->
        Error.instantiation!()

      _ ->
        for c <- items!(t, s), into: "" do
          case Store.walk(c, s) do
            {:atom, <<_::utf8>> = ch} ->
              ch

            n when is_integer(n) and n >= 0 and n <= 0x10FFFF ->
              try do
                <<n::utf8>>
              rescue
                ArgumentError -> Error.representation!("character")
              end

            {:var, _} ->
              Error.instantiation!()

            other ->
              Error.type!("character", PrologEx.resolve(other, s))
          end
        end
    end
  end

  defp chars(text), do: list(for <<c::utf8 <- text>>, do: a(<<c::utf8>>))

  defp file_name!(t, s) do
    case walk(t, s) do
      {:atom, p} ->
        p

      {:var, _} ->
        Error.instantiation!()

      [_ | _] = l ->
        try do
          PrologEx.Builtins.Modules.file_name(PrologEx.resolve(l, s))
        rescue
          PrologEx.Error -> Error.domain!("source_sink", PrologEx.resolve(l, s))
        end

      other ->
        Error.domain!("source_sink", PrologEx.resolve(other, s))
    end
  end
end
