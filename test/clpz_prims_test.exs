defmodule PrologEx.ClpzPrimsTest do
  # Domänen und Schranken von clpz in Elixir (PrologEx.Builtins.ClpzPrims)
  # gegen Triskas Code (die Originale mit der Endung _ref in clpz.pl):
  # Zufallsdomänen (aus Intervallen mit inf/sup, durch Entfernen auch
  # unausgeglichen), Zahlen, Listen; verglichen werden Ergebnis,
  # Fehlschlag und Fehler
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @program """
  :- use_module(library(clpz)).
  % Ergebnis eines Ziels: yes(Ziel nach dem Aufruf), no, err(Fehler)
  outcome(G, O) :-
      copy_term(G, G1),
      catch((call(G1) -> O = yes(G1) ; O = no), error(E, _), O = err(E)).
  cmp(Ref, New) :-
      outcome(Ref, O1), outcome(New, O2),
      (   O1 = yes(R1), O2 = yes(R2) -> arg_eq(R1, R2, O1, O2)
      ;   O1 == O2 -> true
      ;   throw(verschieden(O1, O2))
      ).
  % die Argumente vergleichen (die Ziele selbst heißen verschieden)
  rm_all([], D, D).
  rm_all([X|Xs], D0, D) :- clpz:domain_remove_ref(D0, X, D1), rm_all(Xs, D1, D).
  arg_eq(R1, R2, O1, O2) :-
      R1 = _:G1, R2 = _:G2, G1 =.. [_|A1], G2 =.. [_|A2],
      (   A1 == A2 -> true ; throw(verschieden(O1, O2)) ).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db, ops: Process.get(:prolog_ex_ops)}
  end

  setup c do
    Reader.put_current(c.reader)
    Process.put(:prolog_ex_ops, c.ops)
    PrologEx.put_db(c.db)
    :rand.seed(:exsss, {2026, 11, 3})
    :ok
  end

  # --- Zufallsdaten (als Prolog-Text) ---------------------------------------

  defp int, do: Enum.random(-6..9)

  defp bound do
    case :rand.uniform(8) do
      1 -> "inf"
      2 -> "sup"
      3 -> "#{Enum.random([-1000, 10 ** 20, 7])}"
      _ -> "#{int()}"
    end
  end

  # Ziel, das D an eine Zufallsdomäne bindet (nur mit _ref-Prädikaten)
  defp dom_goal(d) do
    case :rand.uniform(10) do
      1 ->
        "#{d} = empty"

      2 ->
        "#{d} = from_to(inf,sup)"

      _ ->
        pts = Enum.take_random(-8..12, 2 * Enum.random(1..4)) |> Enum.sort()
        ivs = pts |> Enum.chunk_every(2) |> Enum.map(fn [a, b] -> {a, b} end)
        ivs = if :rand.uniform(4) == 1, do: [{"inf", elem(hd(ivs), 1)} | tl(ivs)], else: ivs

        ivs =
          if :rand.uniform(4) == 1,
            do: List.replace_at(ivs, -1, {elem(List.last(ivs), 0), "sup"}),
            else: ivs

        # (negative Zahlen in Klammern: -3- -1 liest sich sonst nicht)
        b = fn x -> if is_integer(x) and x < 0, do: "(#{x})", else: x end
        is = Enum.map_join(ivs, ",", fn {x, y} -> "#{b.(x)}-#{b.(y)}" end)
        rm = for _ <- 1..Enum.random(0..3)//1, do: int()

        "clpz:intervals_to_domain_ref([#{is}], #{d}0), " <>
          "rm_all([#{Enum.join(rm, ",")}], #{d}0, #{d})"
    end
  end

  defp check(c, n, gen) do
    diffs =
      for _ <- 1..n,
          {setup, ref, new} = gen.(),
          q = "#{setup}, cmp(#{ref}, #{new})",
          r = TableCase.run(c.reader, c.db, q),
          r != {"", {:answers, ["true"]}} and not match?({_, {:answers, [_]}}, r),
          do: {q, r}

    assert diffs == [], inspect(Enum.take(diffs, 3), pretty: true)
  end

  # Name(Args) und Name_ref(Args) mit Ausgabe als letztem Argument
  defp pair(name, args, out \\ true) do
    a = Enum.join(args ++ if(out, do: ["_"], else: []), ", ")
    {"clpz:#{name}_ref(#{a})", "clpz:#{name}(#{a})"}
  end

  # --- Schranken --------------------------------------------------------------

  test "Schranken-Arithmetik und Vergleiche", c do
    # {Name, Zahl der Eingaben, Ausgabe?}
    for {name, ins, out} <- [
          {"cis_gt", 2, false},
          {"cis_geq", 2, false},
          {"cis_min", 2, true},
          {"cis_max", 2, true},
          {"cis_plus", 2, true},
          {"cis_minus", 2, true},
          {"cis_times", 2, true},
          {"cis_div", 2, true},
          {"cis_slash", 2, true},
          {"cis_exp", 2, true},
          {"cis_uminus", 1, true},
          {"cis_abs", 1, true},
          {"cis_sign", 1, true}
        ] do
      check(c, 150, fn ->
        args = for _ <- 1..ins, do: bound()
        # Exponenten klein (sonst riesige Zahlen, auch im Original)
        args =
          if name == "cis_exp",
            do: [
              hd(args),
              Enum.random(["inf", "sup", "0", "1", "2", "3", "-1", "-2"])
            ],
            else: args

        # eine Eingabe manchmal ungebunden (das Original wählt dann Klauseln)
        args = if :rand.uniform(15) == 1, do: List.replace_at(args, 0, "V"), else: args
        {r, n} = pair(name, args, out)
        {"true", r, n}
      end)
    end

    for name <- ~w(cis_lt_numeric cis_gt_numeric cis_leq_numeric cis_geq_numeric) do
      check(c, 150, fn ->
        {r, n} = pair(name, [bound(), "#{int()}"], false)
        {"true", r, n}
      end)
    end
  end

  # --- Domänen ----------------------------------------------------------------

  test "Domänen: eine Domäne", c do
    for name <- ~w(domain_infimum domain_supremum domain_num_elements domain_negate
                   domain_intervals domain_complement domain_spread domain_smallest_finite
                   domain_largest_finite domain_to_list) do
      check(c, 200, fn ->
        {r, n} = pair(name, ["D"])
        {dom_goal("D"), r, n}
      end)
    end
  end

  test "Domänen: Domäne und Zahl", c do
    for name <- ~w(domain_contains domain_remove domain_remove_greater_than
                   domain_remove_smaller_than domain_shift domain_expand domain_expand_more
                   domain_contract domain_contract_less) do
      check(c, 200, fn ->
        out = name != "domain_contains"
        x = if :rand.uniform(20) == 1, do: "a", else: "#{Enum.random(-4..12)}"
        {r, n} = pair(name, ["D", x], out)
        {dom_goal("D"), r, n}
      end)
    end
  end

  test "Domänen: zwei Domänen", c do
    for {name, out} <- [
          {"domain_subdomain", false},
          {"domain_subtract", true},
          {"domains_intersection", true},
          {"domains_union", true}
        ] do
      check(c, 250, fn ->
        {r, n} = pair(name, ["D", "E"], out)
        {dom_goal("D") <> ", " <> dom_goal("E"), r, n}
      end)
    end
  end

  test "Listen: list_to_domain, intervals_to_domain, merge_intervals", c do
    check(c, 200, fn ->
      l = for _ <- 1..Enum.random(0..7)//1, do: Enum.random(-5..8)
      {r, n} = pair("list_to_domain", ["[#{Enum.join(l, ",")}]"])
      {"true", r, n}
    end)

    for name <- ~w(intervals_to_domain merge_intervals) do
      check(c, 200, fn ->
        is = for _ <- 1..Enum.random(0..5)//1, do: "(#{bound()})-(#{bound()})"
        {r, n} = pair(name, ["[#{Enum.join(is, ",")}]"])
        {"true", r, n}
      end)
    end
  end

  test "Schranken: alle Paare aus inf, sup, -2..2", c do
    bs = ~w(inf sup) ++ for(i <- -2..2, do: "#{i}")

    ops =
      for(
        n <- ~w(cis_min cis_max cis_plus cis_minus cis_times cis_div cis_slash cis_exp),
        do: {n, 2, true}
      ) ++
        for(n <- ~w(cis_gt cis_geq), do: {n, 2, false}) ++
        for(n <- ~w(cis_uminus cis_abs cis_sign), do: {n, 1, true})

    for {name, ins, out} <- ops,
        x <- bs,
        y <- if(ins == 2, do: bs, else: [nil]) do
      {r, n} = pair(name, Enum.reject([x, y], &is_nil/1), out)

      assert TableCase.run(c.reader, c.db, "cmp(#{r}, #{n})") == {"", {:answers, ["true"]}},
             r
    end
  end

  test "Sonderfälle: ungebundene oder falsche Eingaben wie das Original", c do
    for {setup, ref, new} <- [
          {"true", "clpz:domain_remove_ref(D, 3, _)", "clpz:domain_remove(D, 3, _)"},
          {"true", "clpz:domain_remove_ref(foo, 3, _)", "clpz:domain_remove(foo, 3, _)"},
          {"true", "clpz:domain_infimum_ref(empty, _)", "clpz:domain_infimum(empty, _)"},
          {"true", "clpz:domain_contract_ref(from_to(1,5), 0, _)",
           "clpz:domain_contract(from_to(1,5), 0, _)"},
          {"true", "clpz:cis_exp_ref(2, -1, _)", "clpz:cis_exp(2, -1, _)"},
          {"true", "clpz:cis_exp_ref(1, -3, _)", "clpz:cis_exp(1, -3, _)"},
          {"true", "clpz:cis_slash_ref(4, 0, _)", "clpz:cis_slash(4, 0, _)"},
          {"true", "clpz:cis_max_ref(1, B, M)", "clpz:cis_max(1, B, M)"},
          {"true", "clpz:list_to_domain_ref([a], _)", "clpz:list_to_domain([a], _)"},
          {"true", "clpz:domain_to_list_ref(from_to(inf,3), _)",
           "clpz:domain_to_list(from_to(inf,3), _)"},
          # keine gewöhnlichen Domänen, aber eindeutig im Original
          {"true", "clpz:domain_to_list_ref(from_to(3,1), _)",
           "clpz:domain_to_list(from_to(3,1), _)"},
          {"true", "clpz:domain_subtract_ref(from_to(1,5), from_to(sup,sup), _)",
           "clpz:domain_subtract(from_to(1,5), from_to(sup,sup), _)"},
          {"true", "clpz:domain_subtract_ref(from_to(1,5), from_to(3,sup), _)",
           "clpz:domain_subtract(from_to(1,5), from_to(3,sup), _)"}
        ] do
      assert TableCase.run(c.reader, c.db, "#{setup}, cmp(#{ref}, #{new})") ==
               {"", {:answers, ["true"]}},
             ref
    end
  end
end
