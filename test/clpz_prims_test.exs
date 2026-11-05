defmodule PrologEx.ClpzPrimsTest do
  # Schranken-Arithmetik von clpz in Elixir (PrologEx.Builtins.ClpzPrims)
  # gegen Triskas Code (die Originale mit der Endung _ref in clpz.pl):
  # Zufallsschranken; verglichen werden Ergebnis, Fehlschlag und Fehler.
  # Die Domänen (PrologEx.Builtins.ClpzDom) prüft clpz_dom_test gegen ein
  # Mengenorakel; hier nur die Prolog-Schnittstelle der Domänenbuiltins.
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

  test "Sonderfälle der Schranken: ungebundene oder falsche Eingaben wie das Original", c do
    for {setup, ref, new} <- [
          {"true", "clpz:cis_exp_ref(2, -1, _)", "clpz:cis_exp(2, -1, _)"},
          {"true", "clpz:cis_exp_ref(1, -3, _)", "clpz:cis_exp(1, -3, _)"},
          {"true", "clpz:cis_slash_ref(4, 0, _)", "clpz:cis_slash(4, 0, _)"},
          {"true", "clpz:cis_max_ref(1, B, M)", "clpz:cis_max(1, B, M)"}
        ] do
      assert TableCase.run(c.reader, c.db, "#{setup}, cmp(#{ref}, #{new})") ==
               {"", {:answers, ["true"]}},
             ref
    end
  end

  # Die Prolog-Schnittstelle der Domänen: Terme hin und zurück, Fehlschlag
  # und Fehler bei Eingaben, die keine Domänen sind
  test "Domänenbuiltins: Terme, Fehlschlag, Fehler", c do
    for {q, expect} <- [
          {"clpz:interval(1, 5, D)", ["D = [1..5]"]},
          {"clpz:interval(3, 3, D)", ["D = [3]"]},
          {"clpz:interval(5, 1, D)", ["D = []"]},
          {"clpz:interval(inf, sup, D)", ["D = [inf..sup]"]},
          {"clpz:interval(sup, sup, D)", ["D = []"]},
          {"clpz:empty_domain(D)", ["D = []"]},
          {"clpz:singleton_domain([3], V)", ["V = 3"]},
          {"clpz:singleton_domain([3..4], V)", :fails},
          {"clpz:singleton_domain([], V)", :fails},
          {"clpz:is_domain([inf..3,5,9..13,16..sup])", true},
          {"clpz:is_domain([])", true},
          {"clpz:is_domain([1..3,4..6])", :fails},
          {"clpz:is_domain([3..3])", :fails},
          {"clpz:is_domain([5,3])", :fails},
          {"clpz:is_domain(foo)", :fails},
          {"clpz:is_domain(_)", :fails},
          {"clpz:domain_remove([1..5], 3, D)", ["D = [1..2,4..5]"]},
          {"clpz:domain_remove([1..5], 9, D)", ["D = [1..5]"]},
          {"clpz:domain_remove([3], 3, D)", ["D = []"]},
          {"clpz:domains_intersection([1..5], [4..9], D)", ["D = [4..5]"]},
          {"clpz:domains_intersection([1..5], [7..9], D)", :fails},
          {"clpz:domains_union([1..3], [4..6], D)", ["D = [1..6]"]},
          {"clpz:domain_complement([inf..3,5], D)", ["D = [4,6..sup]"]},
          {"clpz:domain_subtract([1..9], [3..4], D)", ["D = [1..2,5..9]"]},
          {"clpz:domain_infimum([inf..3,5], I), clpz:domain_supremum([inf..3,5], S)",
           ["I = inf, S = 5"]},
          {"clpz:domain_infimum([], _)", :fails},
          {"clpz:domain_num_elements([1..3,7], N)", ["N = 4"]},
          {"clpz:domain_num_elements([1..sup], N)", ["N = sup"]},
          {"clpz:domain_num_elements([], N)", ["N = 0"]},
          {"clpz:domain_contains([1..3,7], 7)", true},
          {"clpz:domain_contains([1..3,7], 5)", :fails},
          {"clpz:domain_subdomain([1..9], [2..3,7])", true},
          {"clpz:domain_subdomain([1..9], [2..3,10])", :fails},
          {"clpz:domain_subdomain([], [])", :fails},
          {"clpz:domain_to_list([1..3,7], L)", ["L = [1,2,3,7]"]},
          {"clpz:domain_to_list([1..sup], L)", :fails},
          {"clpz:domain_intervals([inf..3,5], Is)", ["Is = [inf-3,5-5]"]},
          {"clpz:intervals_to_domain([5-7,1-3,4-4], D)", ["D = [1..7]"]},
          {"clpz:list_to_domain([5,3,4,9,3], D)", ["D = [3..5,9]"]},
          {"clpz:list_to_domain([], D)", ["D = []"]},
          {"clpz:domain_expand([1..3], 2, D)", ["D = [2..6]"]},
          {"clpz:domain_expand([1..3], 0, D)", ["D = [0]"]},
          {"clpz:domain_contract([1..3], 0, D)", {:error, "evaluation_error(zero_divisor)"}},
          {"clpz:domain_contract([3..8], 3, D)", ["D = [1..2]"]},
          {"clpz:domain_spread([inf..3,7..9], S)", ["S = 6"]},
          {"clpz:domain_spread([inf..sup], S)", ["S = inf"]},
          # keine Domäne: Fehler (das Original hatte dafür zufällige Klauseln)
          {"clpz:domain_remove(D, 3, _)", {:error, "instantiation_error"}},
          {"clpz:domain_remove(foo, 3, _)", {:error, "type_error(clpz_domain,foo)"}},
          # (die Ordnung prüft nur is_domain/1; die Operationen vertrauen ihr)
          {"clpz:domain_remove([1..3,4..6], 3, D)", ["D = [1..2,4..6]"]},
          {"clpz:domain_remove(empty, 3, _)", {:error, "type_error(clpz_domain,empty)"}},
          {"clpz:domain_remove(from_to(1,5), 3, _)",
           {:error, "type_error(clpz_domain,from_to(1,5))"}}
        ] do
      actual = TableCase.run(c.reader, c.db, q)
      assert TableCase.matches?(expect, actual), inspect({q, actual})
    end
  end
end
