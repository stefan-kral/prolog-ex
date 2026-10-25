defmodule PrologEx.Builtins.FastRW do
  @moduledoc """
  Schnelles Schreiben und Lesen von Termen in einem Binärformat – wie SWI
  (`fast_write/2`, `fast_read/2`, `fast_term_serialized/2`) und SICStus
  (`library(fastrw)`: dazu `fast_write/1`, `fast_read/1` auf den aktuellen
  Streams).

    * `fast_write(+Stream, +Term)`: Term als Datensatz auf einen
      Binärstream (`open(F, write, S, [type(binary)])`).
    * `fast_read(+Stream, -Term)`: nächsten Datensatz lesen; am Dateiende
      `end_of_file`.
    * `fast_term_serialized(?Term, ?Bytes)`: Term <-> Liste von Bytes
      (ist Bytes eine Liste, wird gelesen, sonst geschrieben).

  Format eines Datensatzes: `"PXT"`, ein Byte Formatversion (1), die Länge
  (32 Bit, big endian), dann der Term im External Term Format der BEAM
  (`term_to_binary`) – geschrieben und gelesen in C, viel schneller als
  `writeq`/`read`. Variablen werden nach ihrem ersten Auftreten nummeriert
  (gleiche Variablen bleiben gleich), Attribute fallen weg (wie
  copy_term/2). Gelesen wird mit der Option `:safe` und geprüft, dass nur
  Prolog-Terme darin stehen – eine fremde oder kaputte Datei gibt
  `syntax_error(fast_term)`, eine andere Formatversion
  `syntax_error(fast_term_version)`.

  Das Format folgt unserer internen Termdarstellung; ändert die sich,
  bekommt es eine neue Version.
  """
  use PrologEx.Builtin
  alias PrologEx.Builtins.IO, as: PIO
  alias PrologEx.Error
  alias PrologEx.Stream, as: S

  @magic "PXT"
  @version 1

  defbuiltin "fast_write", [stream, t] do
    S.put_bytes(PIO.output!(deref(stream), :binary), record(t, subst()))
    :ok
  end

  defbuiltin "fast_write", [t] do
    S.put_bytes(PIO.current_out!(:binary), record(t, subst()))
    :ok
  end

  defbuiltin "fast_read", [stream, t] do
    {:unify, [{t, read_record(PIO.input!(deref(stream), :binary))}]}
  end

  defbuiltin "fast_read", [t] do
    {:unify, [{t, read_record(PIO.current_in!(:binary))}]}
  end

  defbuiltin "fast_term_serialized", [t, bytes] do
    s = subst()

    case byte_list(bytes, s) do
      {:ok, bin} -> {:unify, [{t, decode_record(bin)}]}
      :no -> {:unify, [{bytes, list(:erlang.binary_to_list(record(t, s)))}]}
    end
  end

  # --- Schreiben --------------------------------------------------------

  @doc false
  def record(t, s) do
    {term, _} = number_vars(PrologEx.resolve(t, s), %{})
    etf = :erlang.term_to_binary(term)
    <<@magic, @version, byte_size(etf)::32, etf::binary>>
  end

  # Variablen -> {:v, i} nach erstem Auftreten
  defp number_vars({:var, _} = v, m) do
    case m do
      %{^v => i} -> {{:v, i}, m}
      _ -> {{:v, map_size(m)}, Map.put(m, v, map_size(m))}
    end
  end

  defp number_vars({:struct, f, args}, m) do
    {args, m} = Enum.map_reduce(args, m, &number_vars/2)
    {{:struct, f, args}, m}
  end

  defp number_vars([h | t], m) do
    {h, m} = number_vars(h, m)
    {t, m} = number_vars(t, m)
    {[h | t], m}
  end

  defp number_vars(t, m), do: {t, m}

  # --- Lesen --------------------------------------------------------------

  defp read_record(id) do
    case S.get_bytes(id, 8) do
      "" ->
        a("end_of_file")

      <<@magic, @version, n::32>> ->
        body = S.get_bytes(id, n)
        if byte_size(body) == n, do: decode(body), else: Error.syntax!("fast_term")

      <<@magic, _other, _::32>> ->
        Error.syntax!("fast_term_version")

      _ ->
        Error.syntax!("fast_term")
    end
  end

  @doc false
  def decode_record(<<@magic, @version, n::32, body::binary>>) when byte_size(body) == n,
    do: decode(body)

  def decode_record(<<@magic, v, _::binary>>) when v != @version,
    do: Error.syntax!("fast_term_version")

  def decode_record(_), do: Error.syntax!("fast_term")

  defp decode(etf) do
    term =
      try do
        :erlang.binary_to_term(etf, [:safe])
      rescue
        ArgumentError -> Error.syntax!("fast_term")
      end

    {t, _} = fresh_vars(term, %{})
    t
  end

  # {:v, i} -> frische Variablen; alles andere muss ein Prolog-Term sein
  defp fresh_vars({:v, i}, m) when is_integer(i) and i >= 0 do
    case m do
      %{^i => v} ->
        {v, m}

      _ ->
        v = fresh_var()
        {v, Map.put(m, i, v)}
    end
  end

  defp fresh_vars(n, m) when is_number(n), do: {n, m}
  defp fresh_vars({:atom, name} = a, m) when is_binary(name), do: {a, m}
  defp fresh_vars([], m), do: {[], m}

  defp fresh_vars([h | t], m) do
    {h, m} = fresh_vars(h, m)
    {t, m} = fresh_vars(t, m)
    {[h | t], m}
  end

  defp fresh_vars({:struct, f, [_ | _] = args}, m) when is_binary(f) do
    {args, m} = Enum.map_reduce(args, m, &fresh_vars/2)
    {mk(f, args), m}
  end

  defp fresh_vars(_, _m), do: Error.syntax!("fast_term")

  # Bytes als Prolog-Liste von 0..255 -> {:ok, binary}; sonst :no (schreiben)
  defp byte_list(l, s) do
    case PrologEx.walk(l, s) do
      {:var, _} ->
        :no

      _ ->
        items = PrologEx.Builtins.Lists.items(l, s)

        if Enum.all?(items, &(is_integer(&1) and &1 in 0..255)),
          do: {:ok, :erlang.list_to_binary(items)},
          else: Error.type!("byte_list", PrologEx.resolve(l, s))
    end
  end
end
