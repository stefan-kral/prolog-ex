defmodule PrologEx.Builtins.Swi do
  @moduledoc """
  Komfort aus SWI-Prolog mit Heimat `library(swi)` (in `system`, sichtbar
  nach `use_module(library(swi))`, siehe `PrologEx.Builtins`):

    * Ausgabe: `writeln/1,2`, `tab/1,2` (Anzahl ist ein arithmetischer
      Ausdruck), `with_output_to(+Senke, :Ziel)` mit den Senken `atom(A)`,
      `chars(Cs)`, `chars(Cs, Rest)`, `codes(Cs)`, `codes(Cs, Rest)` (das
      Ziel läuft wie `once/1`; seine Ausgabe landet in der Senke). Dieselben
      Senken nimmt `format/3` als ersten Argument (eingebaut, überall).
    * Listen: `select/4`, `selectchk/3,4`, `flatten/2`, `predsort/3`,
      `sort/4` (Schlüssel 0 oder Argumentnummer; `@<` und `@>` entfernen
      Elemente mit gleichem Schlüssel, `@=<` und `@>=` behalten sie; stabil).
    * Zeichen: `code_type/2` mit den Typen von SWI (`alpha`, `csym`,
      `digit(W)`, `to_lower(L)`, ...; `char_type/2` bleibt Scryers aus
      `library(charsio)`).
    * Globale Variablen: `nb_setval/2`, `nb_getval/2`, `b_setval/2`,
      `b_getval/2`, `nb_current/2` – eigene Schlüssel neben `bb_put/2`
      (library(iso_ext)); `nb_setval` kopiert, `b_setval` wird beim
      Backtracking zurückgenommen; unbekannter Schlüssel bei `nb_getval`,
      `b_getval`: `existence_error(variable, K)`.
    * `term_variables/3` (mit Rest), `string/1` (PrologEx kennt keine
      Strings: scheitert immer), `garbage_collect/0` (tut nichts),
      `get_time/1` (Sekunden seit 1970 als Float), `cyclic_term/1`
      (in `PrologEx.Builtins.Terms`).
  """
  use PrologEx.Builtin
  alias PrologEx.Builtins.{Blackboard, Charsio, IO, Lists}
  alias PrologEx.{Error, Order, Store}
  alias PrologEx.Stream, as: S

  # --- Ausgabe ---------------------------------------------------------------

  defbuiltin "writeln", [x] do
    IO.out(PrologEx.Writer.format(PrologEx.resolve_out(x, subst()), numbervars: true) <> "\n")
    :ok
  end

  defbuiltin "writeln", [stream, x] do
    id = IO.output!(deref(stream), :text)

    S.put_text(
      id,
      PrologEx.Writer.format(PrologEx.resolve_out(x, subst()), numbervars: true) <> "\n"
    )

    :ok
  end

  defbuiltin "tab", [n] do
    IO.out(spaces(n, subst()))
    :ok
  end

  defbuiltin "tab", [stream, n] do
    id = IO.output!(deref(stream), :text)
    S.put_text(id, spaces(n, subst()))
    :ok
  end

  defp spaces(n, s) do
    case PrologEx.Arith.eval(n, s) do
      k when is_integer(k) -> String.duplicate(" ", max(k, 0))
      other -> Error.type!("integer", other)
    end
  end

  # with_output_to/2: Senke prüfen, Ausgabe umlenken, Ergebnis in die Senke
  defbuiltin "$wot_sink", [sink] do
    sink!(deref(sink), subst())
    :ok
  end

  defbuiltin "$wot_open", [old, id] do
    old_id = S.current_output()
    new_id = S.open_memory_out()
    S.set_output(new_id)
    {:unify, [{old, old_id}, {id, new_id}]}
  end

  defbuiltin "$wot_restore", [old, id] do
    restore(deref(old), deref(id))
    :ok
  end

  defbuiltin "$wot_close", [old, id, sink] do
    text = restore(deref(old), deref(id))
    {:unify, [{sink_target(deref(sink), subst()), sink_value(deref(sink), text, subst())}]}
  end

  defp restore(old, id) do
    S.set_output(old)
    text = S.memory_text(id)
    S.close(id)
    text
  end

  @doc false
  # Senke für with_output_to/2 und format/3: {Ziel, Art} oder Fehler
  def sink!({:var, _}, _s), do: Error.instantiation!()

  def sink!(t, s) do
    case PrologEx.unmark_top(t) do
      {:struct, k, [_]} when k in ["atom", "chars", "codes"] -> :ok
      {:struct, k, [_, _]} when k in ["chars", "codes"] -> :ok
      other -> Error.domain!("output_sink", PrologEx.resolve(other, s))
    end
  end

  @doc false
  def sink?(t),
    do:
      match?({:struct, k, [_]} when k in ["atom", "chars", "codes"], t) or
        match?({:struct, k, [_, _]} when k in ["chars", "codes"], t)

  defp sink_target(sink, _s) do
    {:struct, _, [target | _]} = PrologEx.unmark_top(sink)
    target
  end

  @doc false
  # der Wert, der mit dem ersten Argument der Senke unifiziert wird
  def sink_value(sink, text, _s) do
    case PrologEx.unmark_top(sink) do
      {:struct, "atom", [_]} -> a(text)
      {:struct, "chars", [_]} -> list(for(<<c::utf8 <- text>>, do: a(<<c::utf8>>)))
      {:struct, "codes", [_]} -> list(String.to_charlist(text))
      {:struct, "chars", [_, rest]} -> list(for(<<c::utf8 <- text>>, do: a(<<c::utf8>>)), rest)
      {:struct, "codes", [_, rest]} -> list(String.to_charlist(text), rest)
    end
  end

  @doc false
  # format/3 mit einer Senke: Text formatieren und in die Senke
  def format_to_sink(sink, f, args, s) do
    id = S.open_memory_out()

    text =
      try do
        PrologEx.Builtins.Format.format(id, f, args, s)
        S.memory_text(id)
      after
        S.close(id)
      end

    {:unify, [{sink_target(sink, s), sink_value(sink, text, s)}]}
  end

  # --- sort/4 --------------------------------------------------------------------

  defbuiltin "sort", [key, order, l, sorted] do
    s = subst()

    k =
      case deref(key) do
        {:var, _} -> Error.instantiation!()
        k when is_integer(k) and k >= 0 -> k
        k when is_integer(k) -> Error.domain!("not_less_than_zero", k)
        other -> Error.type!("integer", resolve(other))
      end

    {dir, dedup} =
      case deref(order) do
        {:var, _} -> Error.instantiation!()
        {:atom, "@<"} -> {:asc, true}
        {:atom, "@=<"} -> {:asc, false}
        {:atom, "@>"} -> {:desc, true}
        {:atom, "@>="} -> {:desc, false}
        other -> Error.domain!("order", resolve(other))
      end

    items =
      case Lists.skip_list(l, s) do
        {_, []} -> Lists.items(l, s)
        {_, {:var, _}} -> Error.instantiation!()
        _ -> Error.type!("list", resolve(l))
      end

    case Lists.skip_list(sorted, s) do
      {_, []} -> :ok
      {_, {:var, _}} -> :ok
      _ -> Error.type!("list", resolve(sorted))
    end

    keyed = Enum.map(items, &{sort_key(&1, k, s), &1})

    cmp =
      case dir do
        :asc -> fn {a, _}, {b, _} -> Order.compare(a, b, s) != :gt end
        :desc -> fn {a, _}, {b, _} -> Order.compare(a, b, s) != :lt end
      end

    out = Enum.sort(keyed, cmp)
    out = if dedup, do: dedup_keys(out, s), else: out
    {:unify, [{sorted, list(Enum.map(out, &elem(&1, 1)))}]}
  end

  defp sort_key(e, 0, _s), do: e

  defp sort_key(e, k, s) do
    case PrologEx.unmark_top(Store.walk(e, s)) do
      {:var, _} ->
        Error.instantiation!()

      {:struct, _, args} when length(args) >= k ->
        Enum.at(args, k - 1)

      [h | t] when k <= 2 ->
        if k == 1, do: h, else: t

      {:glist, [h | t]} when k <= 2 ->
        if k == 1, do: h, else: t

      other ->
        Error.type!("compound", PrologEx.resolve(other, s))
    end
  end

  # benachbarte Elemente mit gleichem Schlüssel: das erste bleibt
  defp dedup_keys([], _s), do: []

  defp dedup_keys([{k, _} = x | rest], s) do
    [x | dedup_keys(Enum.drop_while(rest, fn {k2, _} -> Order.compare(k, k2, s) == :eq end), s)]
  end

  # --- code_type/2 (wie SWI) ---------------------------------------------------
  #
  # code_type(?Code, ?Type): die Typen von SWI (nicht die von char_type/2
  # aus library(charsio), die Scryers sind): alnum, alpha (Buchstabe,
  # Ziffer oder _), csym, csymf, ascii, white, cntrl, digit(W), space,
  # end_of_line, lower, lower(U), upper, upper(L), punct, graph, print,
  # period, quote, paren, code(C), to_lower(L), to_upper(U), xdigit(W).
  # Ungebundener Typ: alle zutreffenden; ungebundener Code: alle Codes,
  # auf die der Typ passt (aufsteigend).

  @ctypes ~w(alnum alpha csym csymf ascii white cntrl space end_of_line lower upper punct
             graph print period quote paren)
  @ctypes1 ~w(digit lower upper code to_lower to_upper xdigit)

  defbuiltin "code_type", [code, type], nondet: true do
    s = subst()
    ty = PrologEx.unmark_top(deref(type))

    case ty do
      {:var, _} -> :ok
      {:atom, n} when n in @ctypes -> :ok
      {:struct, n, [_]} when n in @ctypes1 -> :ok
      other -> Error.domain!("char_type", resolve(other))
    end

    case deref(code) do
      c when is_integer(c) and c >= 0 and c <= 0x10FFFF ->
        types = if match?({:var, _}, ty), do: all_ctypes(), else: [ty]
        for t <- types, u = ctype(c, t), u != nil, do: {:unify, [{type, t} | u]}

      {:atom, <<c::utf8>>} ->
        types = if match?({:var, _}, ty), do: all_ctypes(), else: [ty]
        for t <- types, u = ctype(c, t), u != nil, do: {:unify, [{type, t} | u]}

      {:var, _} ->
        if match?({:var, _}, ty), do: Error.instantiation!()
        enum_codes(0, code, ty, s)

      other ->
        Error.type!("character_code", resolve(other))
    end
  end

  defp all_ctypes do
    Enum.map(@ctypes, &a/1) ++ Enum.map(@ctypes1, &mk(&1, [fresh_var()]))
  end

  # alle Codes ab c (lazy): je Treffer eine Lösung
  defp enum_codes(c, _code, _ty, _s) when c > 0x10FFFF, do: []
  defp enum_codes(c, code, ty, s) when c in 0xD800..0xDFFF, do: enum_codes(0xE000, code, ty, s)

  defp enum_codes(c, code, ty, s) do
    case ctype(c, ty) do
      nil -> enum_codes(c + 1, code, ty, s)
      u -> [{:unify, [{code, c} | u]} | fn -> enum_codes(c + 1, code, ty, s) end]
    end
  end

  # Bindungen (Liste) wenn Code c den Typ t hat, sonst nil
  defp ctype(c, {:atom, n}), do: if(ctype?(c, n), do: [], else: nil)

  defp ctype(c, {:struct, n, [x]}) do
    case n do
      "digit" -> if c in ?0..?9, do: [{x, c - ?0}]
      "xdigit" -> xdigit(c, x)
      "code" -> [{x, c}]
      "lower" -> if Charsio.type?(c, "lower"), do: [{x, case1(c, &String.upcase/1)}]
      "upper" -> if Charsio.type?(c, "upper"), do: [{x, case1(c, &String.downcase/1)}]
      "to_lower" -> [{x, case1(c, &String.downcase/1)}]
      "to_upper" -> [{x, case1(c, &String.upcase/1)}]
    end
  end

  defp xdigit(c, x) do
    cond do
      c in ?0..?9 -> [{x, c - ?0}]
      c in ?a..?f -> [{x, c - ?a + 10}]
      c in ?A..?F -> [{x, c - ?A + 10}]
      true -> nil
    end
  end

  # Groß-/Kleinschreibung eines Zeichens, nur wenn es eines bleibt
  defp case1(c, f) do
    case f.(<<c::utf8>>) do
      <<d::utf8>> -> d
      _ -> c
    end
  end

  defp letter?(c), do: Charsio.type?(c, "alphabetic")
  defp digit?(c), do: Charsio.type?(c, "numeric")

  defp graph?(c),
    do:
      not Charsio.type?(c, "whitespace") and not Charsio.type?(c, "control") and
        Regex.match?(~r/^[^\p{Cn}\p{Cs}\p{Co}]$/u, <<c::utf8>>)

  defp ctype?(c, n) do
    case n do
      "alnum" -> letter?(c) or digit?(c)
      "alpha" -> letter?(c) or digit?(c) or c == ?_
      "csym" -> letter?(c) or digit?(c) or c == ?_
      "csymf" -> letter?(c) or c == ?_
      "ascii" -> c < 128
      "white" -> c in [?\s, ?\t]
      "cntrl" -> Charsio.type?(c, "control")
      "space" -> Charsio.type?(c, "whitespace")
      "end_of_line" -> c in [?\n, ?\r]
      "lower" -> Charsio.type?(c, "lower")
      "upper" -> Charsio.type?(c, "upper")
      "punct" -> graph?(c) and not letter?(c) and not digit?(c)
      "graph" -> graph?(c)
      "print" -> graph?(c) or c == ?\s
      "period" -> c in ~c".!?"
      "quote" -> c in ~c"'\"`"
      "paren" -> c in ~c"()"
    end
  end

  # --- globale Variablen ------------------------------------------------------

  @gvar "$gvar"

  defbuiltin "nb_setval", [key, v] do
    Blackboard.put(key!(key, subst()), v, @gvar, subst())
  end

  defbuiltin "b_setval", [key, v] do
    {:atom, name} = key!(key, subst())
    {:subst, Blackboard.b_put(subst(), @gvar, name, v)}
  end

  defbuiltin "nb_getval", [key, v] do
    get(key, v, subst())
  end

  defbuiltin "b_getval", [key, v] do
    get(key, v, subst())
  end

  defbuiltin "nb_current", [key, v], nondet: true do
    s = subst()

    case deref(key) do
      {:var, _} ->
        for name <- Blackboard.keys(@gvar, s) do
          {:ok, val} = Blackboard.b_value(@gvar, name, s)
          {:unify, [{key, a(name)}, {v, val}]}
        end

      {:atom, name} ->
        case Blackboard.b_value(@gvar, name, s) do
          {:ok, val} -> [{:unify, [{v, val}]}]
          :error -> []
        end

      other ->
        Error.type!("atom", resolve(other))
    end
  end

  defp get(key, v, s) do
    {:atom, name} = k = key!(key, s)

    case Blackboard.b_value(@gvar, name, s) do
      {:ok, val} -> {:unify, [{v, val}]}
      :error -> Error.existence!("variable", k)
    end
  end

  defp key!(key, s) do
    case Store.walk(key, s) do
      {:atom, _} = k -> k
      {:var, _} -> Error.instantiation!()
      other -> Error.type!("atom", PrologEx.resolve(other, s))
    end
  end

  # --- Verschiedenes ------------------------------------------------------------

  defbuiltin "term_variables", [t, vs, tail] do
    s = subst()
    {:unify, [{vs, list(PrologEx.Builtins.Order.variables(t, s), tail)}]}
  end

  defbuiltin "string", [_x] do
    :fail
  end

  defbuiltin "garbage_collect", [] do
    :erlang.garbage_collect()
    :ok
  end

  defbuiltin "get_time", [t] do
    {:unify, [{t, System.os_time(:microsecond) / 1_000_000}]}
  end

  # --- in Prolog ---------------------------------------------------------------

  def meta do
    [
      {"system", "with_output_to", ["?", 0]},
      {"system", "predsort", [3, "+", "-"]}
    ]
  end

  def library do
    import PrologEx, only: [s: 2, v: 1, a: 1, rule: 2, fact: 1]

    [x, xs, y, ys, h, t, t2, e, l, r, r0, sink, g, old, id, ex] =
      Enum.map(~w(X Xs Y Ys H T T2 E L R R0 Sink G Old Id E2), &v/1)

    [p, n, n1, n2, l1, l2, l3, r1, r2, d, x1, x2, h1, h2, t1, tl, hd, fl] =
      Enum.map(~w(P N N1 N2 L1 L2 L3 R1 R2 D X1 X2 H1 H2 T1 Tl Hd Fl), &v/1)

    [
      # with_output_to(Senke, Ziel): Ziel wie once/1, Ausgabe in die Senke
      rule(s("with_output_to", [sink, g]), [
        s("$wot_sink", [sink]),
        s("$wot_open", [old, id]),
        s(";", [
          s("->", [
            s("catch", [g, ex, s(",", [s("$wot_restore", [old, id]), s("throw", [ex])])]),
            s("$wot_close", [old, id, sink])
          ]),
          s(",", [s("$wot_restore", [old, id]), a("fail")])
        ])
      ]),
      # select(X, Xs, Y, Ys): Ys ist Xs mit einem X durch Y ersetzt
      fact(s("select", [x, [x | t], y, [y | t]])),
      rule(s("select", [x, [h | t], y, [h | t2]]), [s("select", [x, t, y, t2])]),
      # selectchk/3 ohne library(lists): eigenes select/3
      rule(s("selectchk", [e, l, r]), [s("$select3", [e, l, r0]), a("!"), s("=", [r, r0])]),
      fact(s("$select3", [x, [x | t], t])),
      rule(s("$select3", [x, [h | t], [h | t2]]), [s("$select3", [x, t, t2])]),
      rule(s("selectchk", [x, xs, y, ys]), [
        s("select", [x, xs, y, r0]),
        a("!"),
        s("=", [ys, r0])
      ]),
      # flatten/2 wie SWI (Variablen bleiben Elemente)
      rule(s("flatten", [l, fl]), [s("$flatten", [l, [], r0]), a("!"), s("=", [fl, r0])]),
      rule(s("$flatten", [x, tl, [x | tl]]), [s("var", [x]), a("!")]),
      rule(s("$flatten", [[], tl, tl]), [a("!")]),
      rule(s("$flatten", [[hd | t], tl, l]), [
        a("!"),
        s("$flatten", [hd, r0, l]),
        s("$flatten", [t, tl, r0])
      ]),
      fact(s("$flatten", [x, tl, [x | tl]])),
      # predsort/3 wie SWI: Mergesort, call(P, O, A, B), = entfernt
      rule(s("predsort", [p, l, r]), [
        s("length", [l, n]),
        s("$predsort", [p, n, l, v("_"), r0]),
        a("!"),
        s("=", [r, r0])
      ]),
      rule(s("$predsort", [p, 2, [x1, x2 | l], l, r]), [
        a("!"),
        s("call", [p, d, x1, x2]),
        s("$psort2", [d, x1, x2, r])
      ]),
      rule(s("$predsort", [v("_"), 1, [x | l], l, [x]]), [a("!")]),
      rule(s("$predsort", [v("_"), 0, l, l, []]), [a("!")]),
      rule(s("$predsort", [p, n, l1, l3, r]), [
        s("is", [n1, s("//", [n, 2])]),
        s("is", [n2, s("-", [n, n1])]),
        s("$predsort", [p, n1, l1, l2, r1]),
        s("$predsort", [p, n2, l2, l3, r2]),
        s("$predmerge", [p, r1, r2, r])
      ]),
      fact(s("$psort2", [a("<"), x1, x2, [x1, x2]])),
      fact(s("$psort2", [a("="), x1, v("_"), [x1]])),
      fact(s("$psort2", [a(">"), x1, x2, [x2, x1]])),
      rule(s("$predmerge", [v("_"), [], r, r]), [a("!")]),
      rule(s("$predmerge", [v("_"), r, [], r]), [a("!")]),
      rule(s("$predmerge", [p, [h1 | t1], [h2 | t2], r]), [
        s("call", [p, d, h1, h2]),
        a("!"),
        s("$predmerge_", [d, p, h1, h2, t1, t2, r])
      ]),
      rule(s("$predmerge_", [a("<"), p, h1, h2, t1, t2, [h1 | r]]), [
        s("$predmerge", [p, t1, [h2 | t2], r])
      ]),
      rule(s("$predmerge_", [a("="), p, h1, v("_"), t1, t2, [h1 | r]]), [
        s("$predmerge", [p, t1, t2, r])
      ]),
      rule(s("$predmerge_", [a(">"), p, h1, h2, t1, t2, [h2 | r]]), [
        s("$predmerge", [p, [h1 | t1], t2, r])
      ])
    ]
  end
end
