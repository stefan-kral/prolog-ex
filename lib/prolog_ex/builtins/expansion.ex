defmodule PrologEx.Builtins.Expansion do
  @moduledoc """
  Term- und Zielexpansion wie SWI/SICStus:

    * `term_expansion(+Term, -Ersatz)` (Benutzer-Hook): beim Laden für jeden
      gelesenen Term, auch Direktiven, vor der DCG-Übersetzung. Ersatz ist
      ein Term oder eine Liste von Termen (`[]`: Term entfällt). Zum Schluss
      jeder Datei auch für `end_of_file`. Das Ergebnis wird nicht noch
      einmal expandiert.
    * `goal_expansion(+Ziel, -Ersatz)` (Benutzer-Hook): beim Laden für
      jedes Teilziel jedes Klauselrumpfs und jeder Direktive; wiederholt,
      solange ein Hook ein anderes Ziel liefert (höchstens 50-mal, dann
      `resource_error(goal_expansion)`). Geht in `,` `;` `->` `*->` `\\+`
      `M:G` und in Meta-Argumente (`0` und `^`, z. B. `findall/3`,
      `forall/2`, `maplist/2`). Bindet ein Hook Variablen des Ziels, gilt
      das für die ganze Klausel.

  Gesucht werden die Hooks im aktuellen Quellmodul, dann in `user` (der
  erste, der gelingt, zählt). Ohne definierten Hook kostet das Laden
  nichts zusätzlich.

  Anfragen im Toplevel werden ebenso expandiert (Hook in `user`), siehe
  `expand_query/2`.

  Dazu `expand_term/2` (Hooks, sonst DCG-Übersetzung), `expand_goal/2` und
  `dcg_translate_rule/2`.
  """
  use PrologEx.Builtin

  # Steuerkonstrukte der Maschine haben keine meta_predicate-Angaben (die
  # Maschine qualifiziert selbst); für die Expansion:
  @engine_meta %{
    {"call", 1} => [0],
    {"if", 3} => [0, 0, 0],
    {"findall", 3} => ["?", 0, "-"],
    {"findall", 4} => ["?", 0, "-", "?"],
    {"findnsols", 4} => ["?", "?", 0, "-"],
    {"findnsols", 5} => ["?", "?", 0, "-", "?"],
    {"countall", 2} => [0, "-"],
    {"call_nth", 2} => [0, "?"],
    {"catch", 3} => [0, "?", 0],
    {"not", 1} => [0],
    {"forall", 2} => [0, 0],
    {"once", 1} => [0],
    {"ignore", 1} => [0],
    {"time", 1} => [0],
    {"call_with_inference_limit", 3} => [0, "+", "-"],
    {"call_with_depth_limit", 3} => [0, "+", "-"],
    {"setup_call_cleanup", 3} => [0, 0, 0]
  }

  # im Kontextmodul des Aufrufers (ohne meta_predicate: eine vom Benutzer
  # geschriebene Qualifikation M:G bleibt so erhalten)
  defbuiltin "expand_goal", [g, g2] do
    {:call, mk("$expand_goal", [g, a(context_module()), g2, 0])}
  end

  defbuiltin "expand_term", [t, x] do
    {:call, mk("$expand_term", [t, a(context_module()), x])}
  end

  # '$hook_module'(M, Name, Arity, HM): Module, in denen der Hook Name/Arity
  # definiert ist – erst M, dann user
  defbuiltin "$hook_module", [m, name, ar, hm], nondet: true do
    {:atom, mod} = deref(m)
    {:atom, n} = deref(name)
    arity = deref(ar)

    hook_modules(db(), mod, n, arity)
    |> Enum.map(&{:unify, [{hm, a(&1)}]})
  end

  # '$meta_spec'(M, G, Specs): meta_predicate-Angaben des Ziels G (gerufen
  # in M) als Liste, sonst scheitert es
  defbuiltin "$meta_spec", [m, g, specs] do
    {:atom, mod} = deref(m)

    case PrologEx.unmark_top(deref(g)) do
      {:struct, name, args} ->
        case meta_spec(db(), mod, name, length(args)) do
          nil ->
            :fail

          sp ->
            l = Enum.map(sp, fn s -> if is_integer(s), do: s, else: a(s) end)
            {:unify, [{specs, list(l)}]}
        end

      _ ->
        :fail
    end
  end

  defbuiltin "dcg_translate_rule", [rule, clause] do
    case PrologEx.unmark_top(deref(rule)) do
      {:struct, "-->", [h, b]} ->
        {head, body} = PrologEx.DCG.rule(resolve(h), resolve(b))
        {:unify, [{clause, mk(":-", [head, body])}]}

      {:var, _} ->
        PrologEx.Error.instantiation!()

      other ->
        PrologEx.Error.type!("dcg_rule", resolve(other))
    end
  end

  @doc """
  Anfrage im Toplevel: gibt es in `user` einen Hook `goal_expansion/2`,
  wird sie zur Laufzeit expandiert und dann gerufen (wie SWI; SICStus
  expandiert Meta-Aufrufe ebenso). Die Hilfsvariable beginnt mit `_` und
  erscheint daher nicht in der Antwort; Bindungen des Hooks schon.
  """
  def expand_query(db, goal) do
    if Map.has_key?(db, {"user", "goal_expansion", 2}) do
      g2 = {:var, "_ExpandedQuery"}
      mk(",", [mk("$expand_goal", [goal, a("user"), g2, 0]), mk("call", [g2])])
    else
      goal
    end
  end

  @doc """
  Meta-Angabe eines eingebauten Prädikats oder Steuerkonstrukts für
  predicate_property/2 (`meta_predicate(...)`): Liste der Argumentangaben
  oder nil.
  """
  def builtin_meta(name, ar) do
    cond do
      name in [",", ";", "->", "*->"] and ar == 2 -> [0, 0]
      name == "\\+" and ar == 1 -> [0]
      name == "call" and ar >= 2 -> [ar - 1 | List.duplicate("?", ar - 1)]
      true -> PrologEx.Builtins.meta("system", name, ar) || Map.get(@engine_meta, {name, ar})
    end
  end

  @doc false
  def hook_modules(db, mod, name, arity) do
    [mod, "user"]
    |> Enum.uniq()
    |> Enum.filter(&Map.has_key?(db, {&1, name, arity}))
  end

  defp meta_spec(db, mod, name, ar) do
    case PrologEx.locate(db, mod, name, ar) do
      {:db, dm, _} -> Map.get(db, {:meta, dm, name, ar})
      {:builtin, bm, _} -> PrologEx.Builtins.meta(bm, name, ar)
      :none -> nil
    end || Map.get(@engine_meta, {name, ar})
  end

  # ---------------------------------------------------------------------

  def library do
    import PrologEx, only: [s: 2, v: 1, a: 1, rule: 2, fact: 1]

    [t, m, x, x0, hm, g, g1, g2, a1, b1, a2, b2, m2, d, d1, h] =
      Enum.map(~w(T M X X0 HM G G1 G2 A B A2 B2 M2 D D1 H), &v/1)

    [specs, f, as, as2, sp, ss, aa, aas, aa2, aas2, vv] =
      Enum.map(~w(Specs F As As2 S Ss A1 As1 A3 As3 V), &v/1)

    w = v("_")
    cut = a("!")

    control =
      for op <- [",", ";", "->", "*->"] do
        rule(s("$expand_goal", [s(op, [a1, b1]), m, s(op, [a2, b2]), d]), [
          cut,
          s("$expand_goal", [a1, m, a2, d]),
          s("$expand_goal", [b1, m, b2, d])
        ])
      end

    %{
      "system" =>
        [
          rule(s("$expand_term", [t, w, x]), [s("var", [t]), cut, s("=", [x, t])]),
          rule(s("$expand_term", [t, m, x]), [s("$term_hook", [t, m, x0]), cut, s("=", [x, x0])]),
          rule(s("$expand_term", [t, w, x]), [
            s("=", [t, s("-->", [w, w])]),
            cut,
            s("dcg_translate_rule", [t, x])
          ]),
          fact(s("$expand_term", [t, w, t])),
          rule(s("$term_hook", [t, m, x]), [
            s("$hook_module", [m, a("term_expansion"), 2, hm]),
            s(":", [hm, s("term_expansion", [t, x])]),
            cut
          ]),
          rule(s("$expand_goal", [g, w, g, w]), [s("var", [g]), cut])
        ] ++
          control ++
          [
            rule(s("$expand_goal", [s("\\+", [a1]), m, s("\\+", [a2]), d]), [
              cut,
              s("$expand_goal", [a1, m, a2, d])
            ]),
            rule(s("$expand_goal", [s(":", [m2, g]), w, s(":", [m2, g2]), d]), [
              s("atom", [m2]),
              cut,
              s("$expand_goal", [g, m2, g2, d])
            ]),
            rule(s("$expand_goal", [g, m, g2, d]), [
              s("$goal_hook", [g, m, g1]),
              cut,
              s(";", [
                s("->", [
                  s(">=", [d, 50]),
                  s("throw", [s("error", [s("resource_error", [a("goal_expansion")]), g])])
                ]),
                s(",", [
                  s("is", [d1, s("+", [d, 1])]),
                  s("$expand_goal", [g1, m, g2, d1])
                ])
              ])
            ]),
            rule(s("$expand_goal", [g, m, g2, d]), [
              s("$meta_spec", [m, g, specs]),
              cut,
              s("=..", [g, [f | as]]),
              s("$expand_args", [specs, as, m, d, as2]),
              s("=..", [g2, [f | as2]])
            ]),
            fact(s("$expand_goal", [g, w, g, w])),
            rule(s("$goal_hook", [g, m, g1]), [
              s("callable", [g]),
              s("$hook_module", [m, a("goal_expansion"), 2, hm]),
              s(":", [hm, s("goal_expansion", [g, g1])]),
              s("\\==", [g1, g]),
              cut
            ]),
            fact(s("$expand_args", [[], [], w, w, []])),
            rule(s("$expand_args", [[sp | ss], [aa | aas], m, d, [aa2 | aas2]]), [
              s("$expand_arg", [sp, aa, m, d, aa2]),
              s("$expand_args", [ss, aas, m, d, aas2])
            ]),
            rule(s("$expand_arg", [0, aa, m, d, aa2]), [cut, s("$expand_goal", [aa, m, aa2, d])]),
            rule(s("$expand_arg", [a("^"), aa, m, d, aa2]), [
              cut,
              s("$expand_caret", [aa, m, d, aa2])
            ]),
            fact(s("$expand_arg", [w, aa, w, w, aa])),
            rule(s("$expand_caret", [aa, w, w, aa]), [s("var", [aa]), cut]),
            rule(s("$expand_caret", [s("^", [vv, g]), m, d, s("^", [vv, g2])]), [
              cut,
              s("$expand_caret", [g, m, d, g2])
            ]),
            rule(s("$expand_caret", [g, m, d, g2]), [s("$expand_goal", [g, m, g2, d])]),

            # für das Laden: ganze Klausel (Bindungen gelten auch im Kopf)
            rule(s("$expand_clause", [s(":-", [h, b1]), m, s(":-", [h, b2])]), [
              s("$expand_goal", [b1, m, b2, 0])
            ]),
            rule(s("$expand_directive", [g, m, g2]), [s("$expand_goal", [g, m, g2, 0])])
          ]
    }
  end
end
