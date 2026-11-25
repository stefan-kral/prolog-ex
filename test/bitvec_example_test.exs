defmodule PrologEx.BitvecExampleTest do
  # examples/bitvec.pl: alle Varianten (Ganzzahl, Byte-Folge, Tabellen)
  # liefern dieselben Summen
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  test "alle Varianten gleich" do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    PrologEx.put_db(%{})
    {:ok, _} = PrologEx.Consult.load_file(Path.expand("../examples/bitvec.pl", __DIR__))

    for n <- [1, 7, 8, 9, 20, 64, 200] do
      q =
        "set_random(seed(#{n})), Max is 1 << #{n}, " <>
          "findall(V, (between(1, 30, _), V is random(Max)), Vs), " <>
          "maplist([V, B]>>int_to_bytes(V, #{n}, B), Vs, Bs), " <>
          "findall(Name-Ss, (variant(Name, K, _), (K == int -> Xs = Vs ; Xs = Bs), " <>
          "sums(Name, #{n}, Xs, Ss)), Rs), " <>
          "maplist([V, S]>>(int_scan(#{n}, V, S)), Vs, Ref), " <>
          "forall(member(Name-Ss, Rs), (Ss == Ref -> true ; throw(abweichung(Name))))"

      [{:term, g, _}] = Reader.read_terms(r, q <> ".")
      assert [_] = PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1), "n = #{n}"
    end
  end
end
