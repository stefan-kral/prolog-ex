defmodule PrologEx.Jit.Parse do
  @moduledoc false
  # Zerlegen der Klauseln in die Zwischenform (PrologEx.Jit): Köpfe als
  # Muster, Rümpfe als Ziele, Ausdrücke, eingebaute Prädikate.

  alias PrologEx.Jit.Util

  # library(bytes), was der übersetzte Code direkt ruft (b_bytes_*/n)
  @bytes_bis ~w(bytes_length bytes_at bytes_bit bytes_next_bit bytes_integer)

  {ops2, ops1} = PrologEx.Arith.ops()
  @ops2 ops2
  @ops1 ops1 -- ~w(random random_float)
  # ganzzahlig abgeschlossen: Ganzzahlen rein, Ganzzahlen raus
  @iops2 ~w(+ - * // mod rem div min max >> << /\\ \\/ xor gcd getbit)
  @iops1 ~w(- + abs sign msb \\)
  @cmps ~w(< > =< >= =:= =\\=)
  @tords ~w(@< @> @=< @>=)
  @type_tests ~w(var nonvar atom number integer float atomic compound callable is_list)
  @consts %{"pi" => :math.pi(), "e" => :math.exp(1), "epsilon" => 2.220446049250313e-16}
  @max_vars 200

  # --- Zerlegen -----------------------------------------------------------

  def parse({_, arity} = key, source, callable) when arity > 0 do
    # wie der Interpreter die Klausel ausführt (ein führendes V = T im Kopf,
    # Aliase weg): dieselben Inferenzen
    source =
      Enum.map(source, fn {h, b} -> PrologEx.Compiler.simplify({Util.plain(h), Util.plain(b)}) end)

    ctx = %{self: key, callable: callable}

    clauses =
      for {{h, b}, i} <- Enum.with_index(source, 1) do
        try do
          # Variablen einer Klausel liegen in BEAM-Registern (höchstens 1024)
          if {h, b} |> Util.raw_vars([]) |> Enum.uniq() |> length() > @max_vars,
            do: Util.no!("mehr als #{@max_vars} Variablen")

          gs = b |> conj() |> once_disj() |> Enum.map(&goal(&1, ctx)) |> mark_once()
          {Enum.map(Util.args(h), &pat!/1), index_guard(Util.args(h), gs)}
        catch
          {:no, r} -> Util.no!("Klausel #{i}: #{r}")
        end
      end

    calls = clauses |> collect_calls() |> Enum.uniq()
    deps = List.delete(calls, key)
    # gerufene Builtins, die eine eigene Definition verdecken würde
    bdeps = clauses |> collect_bis() |> Enum.uniq()
    size = clauses |> Enum.map(fn {_, gs} -> goal_count(gs) end) |> Enum.sum()

    %{
      key: key,
      arity: arity,
      clauses: clauses,
      source: source,
      deps: deps,
      bdeps: bdeps,
      rec: key in calls,
      size: size
    }
  catch
    {:no, r} ->
      Util.why(key, r)
      nil
  end

  def parse(key, _, _) do
    Util.why(key, "ohne Argumente")
    nil
  end

  defp goal_count(gs) when is_list(gs), do: Enum.reduce(gs, 0, &(goal_count(&1) + &2))
  defp goal_count({:ite, c, t, e}), do: goal_count(c) + goal_count(t) + goal_count(e)
  defp goal_count({:not, g}), do: 1 + goal_count(g)
  defp goal_count(_), do: 1

  # Wie PrologEx.Compiler: ein Typtest als erstes Ziel auf der Variablen des
  # ersten Kopfarguments ist Wächter des Index – der Interpreter lässt die
  # Klausel bei gebundenem Argument weg oder den Test aus, zählt ihn also
  # nicht
  @guards ~w(integer float number atom atomic compound callable var)
  defp index_guard([{:var, v} = x | _], [{:tt, t, x} = g | gs]) when t in @guards and v != "_",
    do: [{:idx, g} | gs]

  defp index_guard(_, gs), do: gs

  defp collect_calls({:call, k, _}), do: [k]
  defp collect_calls({:callo, k, _}), do: [k]
  defp collect_calls(t) when is_tuple(t), do: collect_calls(Tuple.to_list(t))
  defp collect_calls(l) when is_list(l), do: Enum.flat_map(l, &collect_calls/1)
  defp collect_calls(_), do: []

  defp collect_bis({:bi, "append", _, _}), do: [{"append", 3}]
  defp collect_bis({:bi, "bit_is_set", _, _}), do: [{"bit_is_set", 2}]
  defp collect_bis({:bi, "memberchk", _, _}), do: [{"memberchk", 2}]
  defp collect_bis({:bi, n, _, _}) when n in ["length", "sort", "msort"], do: [{n, 2}]
  defp collect_bis({:bi, n, ins, _}) when n in @bytes_bis, do: [{n, length(ins) + 1}]
  defp collect_bis({:bi, "lfsr_next", _, _}), do: [{"lfsr_next", 3}]
  defp collect_bis({:bi, "lfsr_done", _, _}), do: [{"lfsr_done", 1}]
  defp collect_bis(t) when is_tuple(t), do: collect_bis(Tuple.to_list(t))
  defp collect_bis(l) when is_list(l), do: Enum.flat_map(l, &collect_bis/1)
  defp collect_bis(_), do: []

  # Aufrufe, von denen nur die erste Lösung zählt ({:callo, ...}): gleich
  # gefolgt von einem Schnitt, letztes Ziel einer Bedingung oder unter \+.
  # Ist der Gerufene nichtdeterministisch (member/2, between/3), nimmt der
  # Code seine erste Lösung ({:call1, ...}); sonst ein gewöhnlicher Aufruf
  defp mark_once(gs), do: gs |> mark_cut() |> Enum.map(&mark_inner/1)

  defp mark_cut([{:call, k, a}, :cut | rest]), do: [{:callo, k, a}, :cut | mark_cut(rest)]
  defp mark_cut([g | rest]), do: [g | mark_cut(rest)]
  defp mark_cut([]), do: []

  defp mark_inner({:ite, c, t, e}),
    do: {:ite, mark_last(mark_once(c)), mark_once(t), mark_once(e)}

  defp mark_inner({:not, g}), do: {:not, mark_last(mark_once(g))}
  defp mark_inner(g), do: g

  defp mark_last(gs) do
    case Enum.reverse(gs) do
      [{:call, k, a} | r] -> Enum.reverse([{:callo, k, a} | r])
      _ -> gs
    end
  end

  # wie PrologEx.Compiler: `true` im Rumpf fällt weg (zählt also nicht)
  defp conj({:struct, ",", [a, b]}), do: conj(a) ++ conj(b)
  defp conj({:atom, "true"}), do: []
  defp conj(g), do: [g]

  # Eine Disjunktion, auf die gleich ein Schnitt folgt, braucht nur ihre
  # erste Lösung: (A ; B), ! ist dasselbe wie (A -> true ; B -> true), !
  # – wenn in A und B kein Schnitt steht (dort schnitte er die Klausel ab,
  # in einer Bedingung nur lokal). So übersetzt (once_ite/2): jeder Zweig
  # eine Bedingung, ohne `true` danach und ohne `fail` am Ende (beide
  # zählten eine Inferenz, die der Interpreter nicht hat)
  defp once_disj([{:struct, ";", [l, _]} = g, {:atom, "!"} = c | rest]) do
    bs = disj_branches(g)

    if not ite_left?(l) and Enum.all?(bs, &cut_free?/1),
      do: [{:"$once_disj", bs}, c | once_disj(rest)],
      else: [g, c | once_disj(rest)]
  end

  defp once_disj([g | rest]), do: [g | once_disj(rest)]
  defp once_disj([]), do: []

  defp ite_left?({:struct, op, [_, _]}) when op in ["->", "*->"], do: true
  defp ite_left?(_), do: false

  defp disj_branches({:struct, ";", [l, r]} = g) do
    if ite_left?(l), do: [g], else: disj_branches(l) ++ disj_branches(r)
  end

  defp disj_branches(g), do: [g]

  defp cut_free?({:atom, "!"}), do: false

  defp cut_free?({:struct, op, [a, b]}) when op in [",", ";", "->", "*->"],
    do: cut_free?(a) and cut_free?(b)

  defp cut_free?(_), do: true

  defp once_ite([b], ctx), do: {:ite, seq(b, ctx), [], [:fail0]}
  defp once_ite([b | bs], ctx), do: {:ite, seq(b, ctx), [], [once_ite(bs, ctx)]}

  # in Steuerkonstrukten bleibt `true` ein Ziel (zählt eins)
  defp seq({:struct, ",", [a, b]}, ctx), do: seq(a, ctx) ++ seq(b, ctx)
  defp seq(g, ctx), do: [goal(g, ctx)]

  defp goal({:atom, "!"}, _), do: :cut
  defp goal({:atom, "true"}, _), do: true
  defp goal({:atom, f}, _) when f in ["fail", "false"], do: :fail
  defp goal({:struct, "is", [l, r]}, _), do: {:is, num_term!(l), expr!(r)}
  defp goal({:struct, op, [a, b]}, _) when op in @cmps, do: {:cmp, op, expr!(a), expr!(b)}
  defp goal({:struct, "=", [a, b]}, _), do: {:unify, pat!(a), pat!(b)}
  defp goal({:struct, t, [x]}, _) when t in @type_tests, do: {:tt, t, num_term!(x)}
  defp goal({:struct, "==", [a, b]}, _), do: {:teq, true, pat!(a), pat!(b)}
  defp goal({:struct, op, [a, b]}, _) when op in @tords, do: {:tord, op, pat!(a), pat!(b)}

  # Term zerlegen, vergleichen (PrologEx.Jit.Runtime.b_*/n): Eingaben bestimmt,
  # Ergebnisse als Muster
  defp goal({:struct, "arg", [n, t, a]}, _), do: {:bi, "arg", [pat!(n), pat!(t)], [pat!(a)]}

  defp goal({:struct, "functor", [t, f, n]}, _),
    do: {:bi, "functor", [pat!(t)], [pat!(f), pat!(n)]}

  defp goal({:struct, "=..", [t, l]}, _), do: {:bi, "univ", [pat!(t)], [pat!(l)]}

  defp goal({:struct, "compare", [o, a, b]}, _) do
    # die Ordnung: frei oder eine der drei (sonst Fehler wie im Interpreter)
    case o do
      {:var, _} -> :ok
      {:atom, x} when x in ["<", "=", ">"] -> :ok
      _ -> Util.no!("compare/3 mit Ordnung #{Util.desc(o)}")
    end

    {:bi, "compare", [pat!(a), pat!(b)], [pat!(o)]}
  end

  defp goal({:struct, "\\==", [a, b]}, _), do: {:teq, false, pat!(a), pat!(b)}

  defp goal({:struct, ";", [{:struct, "->", [c, t]}, e]}, ctx),
    do: {:ite, seq(c, ctx), seq(t, ctx), seq(e, ctx)}

  # ( C -> T ) ohne Else: der Interpreter nimmt `fail` als Else (zählt eins)
  defp goal({:struct, "->", [c, t]}, ctx), do: {:ite, seq(c, ctx), seq(t, ctx), [:fail]}
  defp goal({:struct, "\\+", [g]}, ctx), do: {:not, seq(g, ctx)}
  defp goal({:"$once_disj", bs}, ctx), do: once_ite(bs, ctx)
  defp goal({:struct, ";", _}, _), do: Util.no!("Disjunktion (; ohne ->): nicht deterministisch")
  defp goal({:struct, "->", _}, _), do: Util.no!("->")

  # Aufruf: das Prädikat selbst oder ein anderes, das übersetzt wird oder
  # schon übersetzt ist
  defp goal({:struct, name, a}, ctx) do
    key = {name, length(a)}

    case key == ctx.self or ctx.callable.(key) do
      true ->
        {:call, key, Enum.map(a, &pat!/1)}

      # lists:append/3 (sichtbar, nicht selbst definiert): erste Liste
      # bestimmt, deterministisch (PrologEx.Jit.Runtime.b_append/2)
      :builtin when key == {"append", 3} ->
        {:bi, "append", Enum.map(Enum.take(a, 2), &pat!/1), [pat!(List.last(a))]}

      # arithmetic:bit_is_set/2 (sichtbar, nicht selbst definiert): zwei
      # Ganzzahlen, K >= 0, sonst aufgeben (der Interpreter meldet den Fehler)
      :builtin when key == {"bit_is_set", 2} ->
        {:bi, "bit_is_set", Enum.map(a, &pat!/1), []}

      # memberchk/2 (Prüfen, ohne zu binden), length/2 (echte Liste),
      # sort/2, msort/2 (echte Liste): sonst aufgeben
      :builtin when key == {"memberchk", 2} ->
        {:bi, "memberchk", Enum.map(a, &pat!/1), []}

      :builtin when key in [{"length", 2}, {"sort", 2}, {"msort", 2}] ->
        [x, y] = a
        {:bi, name, [pat!(x)], [pat!(y)]}

      # library(bytes), lesend: die Eingaben bestimmt (ein freier Index von
      # bytes_at/3, bytes_bit/3 oder eine freie Folge: zur Laufzeit
      # aufgeben), das Ergebnis eine Zahl. bytes_integer/2 nur von der
      # Folge zur Zahl
      :builtin when name in @bytes_bis ->
        {ins, out} = Enum.split(a, length(a) - 1)
        {:bi, name, Enum.map(ins, &pat!/1), Enum.map(out, &pat!/1)}

      # library(lfsr): der Zustand bestimmt (sonst aufgeben, der
      # Interpreter meldet den Fehler); lfsr_next/3 gibt Zahl und Zustand
      :builtin when key == {"lfsr_next", 3} ->
        [st, x, st1] = a
        {:bi, name, [pat!(st)], [pat!(x), pat!(st1)]}

      :builtin when key == {"lfsr_done", 1} ->
        {:bi, name, Enum.map(a, &pat!/1), []}

      :dynamic ->
        Util.no!("ruft das dynamische #{Util.pi(key)}")

      false ->
        Util.no!("Ziel #{Util.pi(key)}")
    end
  end

  defp goal(g, _), do: Util.no!("Ziel #{Util.desc(g)}")

  # Term: Zahl, Variable, Atom, :nl ([]), {:cons, Element, Rest} oder
  # {:st, Funktor, Argumente}
  defp pat!(n) when is_integer(n) or is_float(n), do: n
  defp pat!({:var, _} = v), do: v
  defp pat!({:atom, _} = a), do: a
  defp pat!([]), do: :nl
  defp pat!([h | t]), do: {:cons, pat!(h), pat!(t)}
  defp pat!({:struct, f, a}), do: {:st, f, Enum.map(a, &pat!/1)}
  defp pat!(t), do: Util.no!("Term #{Util.desc(t)}")

  defp num_term!(n) when is_integer(n) or is_float(n), do: n
  defp num_term!({:var, _} = v), do: v
  defp num_term!(t), do: Util.no!("Term #{Util.desc(t)} (nur Zahl oder Variable)")

  defp expr!(n) when is_integer(n) or is_float(n), do: n
  defp expr!({:var, _} = v), do: v
  defp expr!({:atom, c}) when is_map_key(@consts, c), do: @consts[c]
  defp expr!({:struct, op, [a, b]}) when op in @ops2, do: {:op2, op, expr!(a), expr!(b)}
  defp expr!({:struct, op, [a]}) when op in @ops1, do: {:op1, op, expr!(a)}
  defp expr!(t), do: Util.no!("Ausdruck mit #{Util.desc(t)}")

  # nur Ganzzahlen und ganzzahlig abgeschlossene Operationen?
  def int_only?(f) when is_float(f), do: false
  def int_only?({:var, _}), do: true
  def int_only?({:tt, t, _}) when t in ["float", "number"], do: false
  def int_only?({:op2, op, a, b}), do: op in @iops2 and int_only?(a) and int_only?(b)
  def int_only?({:op1, op, a}), do: op in @iops1 and int_only?(a)
  def int_only?(t) when is_tuple(t), do: int_only?(Tuple.to_list(t))
  def int_only?(l) when is_list(l), do: Enum.all?(l, &int_only?/1)
  def int_only?(_), do: true
end
