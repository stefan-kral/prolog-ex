defmodule PrologEx.ScryerErrorTest do
  # library(error) aus Scryer Prolog
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    {db, []} =
      PrologEx.Consult.load(%{}, Reader.read_terms(r, ":- use_module(library(error)).\n"))

    {:ok, reader: r, db: db}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    c.db
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, goal), do: ask(c, "catch(#{goal}, error(E, C), true)")

  test "must_be/2: Erfolg", c do
    for g <-
          ~w{must_be(integer,3) must_be(atom,a) must_be(character,a) must_be(in_character,end_of_file)
                must_be(chars,"ab") must_be(chars,[]) must_be(octet_chars,"aÿ") must_be(list,[_,_])
                must_be(boolean,true) must_be(pair,a-b) must_be(term,f(a)) must_be(var,_)
                must_be(not_less_than_zero,0) must_be(octet_character,'ÿ') must_be(type,chars)} do
      assert ask(c, g) == ["true"], g
    end
  end

  test "must_be/2: Fehler und Kontexte wie Scryer", c do
    assert err(c, "must_be(integer, a)") == ["C = must_be/2, E = type_error(integer, a)"]
    assert err(c, "must_be(integer, _)") == ["C = must_be/2, E = instantiation_error"]
    assert err(c, "must_be(_, 1)") == ["C = must_be/2, E = instantiation_error"]
    assert err(c, "must_be(foo, 1)") == ["C = must_be/2, E = type_error(type, foo)"]
    assert err(c, "must_be(var, 1)") == ["C = must_be/2, E = uninstantiation_error(1)"]
    assert err(c, "must_be(chars, [a|_])") == ["C = must_be/2, E = instantiation_error"]
    assert err(c, "must_be(chars, [a, _])") == ["C = must_be/2, E = instantiation_error"]
    # Typfehler vor Instanziierungsfehlern (aus can_be/2)
    assert err(c, "must_be(chars, [_, 1|_])") == ["C = can_be/2, E = type_error(character, 1)"]
    assert err(c, "must_be(chars, ab)") == ["C = can_be/2, E = type_error(list, ab)"]
    assert err(c, "must_be(list, [a|b])") == ["C = must_be/2, E = type_error(list, [a|b])"]
    assert err(c, "must_be(list, [a|_])") == ["C = must_be/2, E = instantiation_error"]
    assert err(c, "must_be(character, ab)") == ["C = must_be/2, E = type_error(character, ab)"]

    assert err(c, "must_be(in_character, 1)") == [
             "C = must_be/2, E = type_error(in_character, 1)"
           ]

    assert err(c, "must_be(octet_chars, [a, 'ā'])") ==
             ["C = must_be/2, E = domain_error(octet_character, 'ā')"]

    assert err(c, "must_be(octet_character, 'ā')") ==
             ["C = must_be/2, E = domain_error(octet_character, 'ā')"]

    assert err(c, "must_be(not_less_than_zero, -1)") ==
             ["C = must_be/2, E = domain_error(not_less_than_zero, -1)"]

    assert err(c, "must_be(not_less_than_zero, a)") == [
             "C = must_be/2, E = type_error(integer, a)"
           ]

    assert err(c, "must_be(boolean, x)") == ["C = must_be/2, E = type_error(boolean, x)"]
    assert err(c, "must_be(pair, x)") == ["C = must_be/2, E = type_error(pair, x)"]
    assert err(c, "must_be(term, f(_))") == ["C = must_be/2, E = instantiation_error"]
  end

  test "can_be/2", c do
    for g <- ~w{can_be(integer,_) can_be(integer,1) can_be(list,[a|_]) can_be(chars,[a,_|_])
                can_be(octet_chars,[a|_]) can_be(boolean,_) can_be(term,f(_))} do
      assert ask(c, g) == ["true"], g
    end

    assert err(c, "can_be(list, [a|b])") == ["C = can_be/2, E = type_error(list, [a|b])"]
    assert err(c, "can_be(integer, a)") == ["C = can_be/2, E = type_error(integer, a)"]
    assert err(c, "can_be(chars, [a, 1|_])") == ["C = can_be/2, E = type_error(character, 1)"]

    assert err(c, "can_be(octet_chars, [a, 'ā'|_])") ==
             ["C = can_be/2, E = domain_error(octet_character, 'ā')"]

    assert err(c, "can_be(not_less_than_zero, -2)") ==
             ["C = can_be/2, E = domain_error(not_less_than_zero, -2)"]

    assert err(c, "can_be(nix, 1)") == ["C = must_be/2, E = type_error(type, nix)"]
  end

  test "Fehler werfen; call_with_error_context/2", c do
    assert err(c, "instantiation_error") == ["C = [], E = instantiation_error"]
    assert err(c, "domain_error(d, x)") == ["C = [], E = domain_error(d, x)"]
    assert err(c, "type_error(t, x)") == ["C = [], E = type_error(t, x)"]
    assert err(c, "representation_error(r)") == ["C = [], E = representation_error(r)"]
    assert err(c, "resource_error(m)") == ["C = [], E = resource_error(m)"]
    assert err(c, "instantiation_error(k)") == ["C = k, E = instantiation_error"]
    assert err(c, "domain_error(d, x, k)") == ["C = k, E = domain_error(d, x)"]
    assert err(c, "type_error(t, x, k)") == ["C = k, E = type_error(t, x)"]

    assert err(c, "call_with_error_context(type_error(t, x), predicate-p/1)") ==
             ["C = [predicate-p/1], E = type_error(t, x)"]

    assert err(c, "call_with_error_context(true, nopair)") ==
             ["C = must_be/2, E = type_error(pair, nopair)"]

    assert ask(c, "call_with_error_context((X = 1 ; X = 2), p-q)") == ["X = 1", "X = 2"]
  end
end
