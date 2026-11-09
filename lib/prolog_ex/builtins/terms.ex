defmodule PrologEx.Builtins.Terms do
  @moduledoc "Termaufbau und -zerlegung: functor/3, (=..)/2."
  use PrologEx.Builtin
  require PrologEx.Cyclic
  alias PrologEx.Builtins.Core
  alias PrologEx.Store

  # plus(X, Y, Z): Z = X + Y für Ganzzahlen, zwei beliebige gebunden (wie
  # SWI); gebundene Nicht-Ganzzahl: type_error(integer, _), weniger als zwei
  # gebunden: instantiation_error
  # plus(X, Y, Z): X + Y = Z, mindestens zwei ganze Zahlen. Jedes Argument
  # einmal dereferenziert und geprüft (Typfehler in der Reihenfolge X, Y,
  # Z); das Ergebnis ist eine Zahl: gebunden wird direkt (bind/3 weckt
  # attributierte Variablen), ein gebundenes Ziel nur verglichen
  defbuiltin "plus", [x, y, z] do
    plus(x, y, z, subst())
  end

  # evaluable_property(E, P) (Logtalks „Prolog commons“, library(iso_ext)):
  # E ist ein auswertbarer Funktor (abs(_), pi); P ist built_in, static oder
  # template(T, R) – etwa template(abs(number), number), template(pi, float),
  # Typen integer, float, number (PrologEx.Arith). Andere gültige
  # Eigenschaften (dynamic, foreign) treffen nie zu; unbekannter Funktor:
  # scheitert
  @eval_props ~w(built_in static dynamic foreign)

  defbuiltin "evaluable_property", [e, p], nondet: true do
    s = subst()

    {name, arity} =
      case PrologEx.unmark_top(Store.walk(e, s)) do
        {:var, _} -> PrologEx.Error.instantiation!()
        {:atom, n} -> {n, 0}
        {:struct, n, args} -> {n, length(args)}
        other -> PrologEx.Error.type!("callable", PrologEx.resolve(other, s))
      end

    case PrologEx.unmark_top(Store.walk(p, s)) do
      {:var, _} -> :ok
      {:atom, x} when x in @eval_props -> :ok
      {:struct, "template", [_, _]} -> :ok
      other -> PrologEx.Error.domain!("evaluable_property", PrologEx.resolve(other, s))
    end

    case PrologEx.Arith.templates(name, arity) do
      nil ->
        []

      ts ->
        templates =
          for {args, ret} <- ts do
            t = if args == [], do: a(name), else: mk(name, Enum.map(args, &a(Atom.to_string(&1))))
            mk("template", [t, a(Atom.to_string(ret))])
          end

        for prop <- [a("built_in"), a("static") | templates], do: {:unify, [{p, prop}]}
    end
  end

  # cached_is(X, E) (library(iso_ext)): wie X is E, geteilte Teilausdrücke
  # von E nur einmal ausgewertet (PrologEx.Arith.eval_cached/2)
  defbuiltin "cached_is", [x, e] do
    {:unify, [{x, PrologEx.Arith.eval_cached(e, subst())}]}
  end

  @doc false
  # plus/3 – auch direkt aus der Maschine (PrologEx: engine_step)
  def plus(x, y, z, s) do
    a = int_or_var!(x, s)
    b = int_or_var!(y, s)
    c = int_or_var!(z, s)

    cond do
      is_integer(a) and is_integer(b) -> int_result(c, a + b, s)
      is_integer(a) and is_integer(c) -> {:subst, PrologEx.Store.bind(b, c - a, s)}
      is_integer(b) and is_integer(c) -> {:subst, PrologEx.Store.bind(a, c - b, s)}
      true -> PrologEx.Error.instantiation!()
    end
  end

  defp int_or_var!(t, s) do
    case PrologEx.Store.walk(t, s) do
      n when is_integer(n) -> n
      {:var, _} = v -> v
      other -> PrologEx.Error.type!("integer", PrologEx.resolve(other, s))
    end
  end

  # Ergebnis n an t (ganze Zahl oder ungebundene Variable)
  defp int_result(n, n, _s), do: :ok
  defp int_result(m, _n, _s) when is_integer(m), do: :fail
  defp int_result(v, n, s), do: {:subst, PrologEx.Store.bind(v, n, s)}

  # numbervars(T, Start, End): die Variablen von T (nach erstem Auftreten)
  # werden '$VAR'(Start), '$VAR'(Start+1), ...; End ist die nächste Nummer
  defbuiltin "numbervars", [t, start, stop] do
    n0 =
      case deref(start) do
        {:var, _} -> PrologEx.Error.instantiation!()
        n when is_integer(n) -> n
        other -> PrologEx.Error.type!("integer", resolve(other))
      end

    case deref(stop) do
      {:var, _} -> :ok
      n when is_integer(n) -> :ok
      other -> PrologEx.Error.type!("integer", resolve(other))
    end

    vars = PrologEx.Builtins.Order.variables(t, subst())

    pairs =
      vars
      |> Enum.with_index(n0)
      |> Enum.map(fn {v, i} -> {v, mk("$VAR", [i])} end)

    {:unify, [{stop, n0 + length(vars)} | pairs]}
  end

  # functor(T, Name, Arity)
  #   T gebunden:   Name/Arity von T (atomar: Name = T, Arity = 0)
  #   T ungebunden: T = Name(_, ..., _) mit frischen Variablen
  # acyclic_term(T): T ist (unter der aktuellen Substitution) endlich.
  # Zyklen entstehen nur über gebundene Variablen; Tiefensuche merkt sich
  # die Variablen auf dem aktuellen Pfad und die schon als azyklisch
  # bekannten (jede gebundene Variable wird so höchstens einmal besucht).
  defbuiltin "acyclic_term", [t] do
    acyclic?(t, subst())
  end

  # --- library(terms): term_hash/2,4, term_size/2 (wie SWI) ---------------

  # term_hash(T, H): ist T ground, H ein Hashwert (0..2^27-1, über
  # Sitzungen und Rechner gleich: :erlang.phash2/1 einer kanonischen Form);
  # sonst bleibt H ungebunden. T == U ergibt denselben Wert, auch für
  # zyklische Terme (dann aus den ersten @hash_nodes Knoten der Abwicklung,
  # in Breitensuche).
  defbuiltin "term_hash", [t, h] do
    s = subst()

    case hash_canon(t, s, :inf) do
      :nonground -> :ok
      c -> {:unify, [{h, :erlang.phash2(c)}]}
    end
  end

  # term_hash(T, Tiefe, Bereich, H): nur bis Tiefe (1: Funktor bzw.
  # atomarer Wert, 2: dazu die Argumente, ...; 0: nichts), H in
  # 0..Bereich-1; ungebunden, wenn T bis Tiefe nicht ground ist
  defbuiltin "term_hash", [t, depth, range, h] do
    s = subst()
    d = int_arg!(deref(depth))
    r = int_arg!(deref(range))
    if d < 0, do: PrologEx.Error.domain!("not_less_than_zero", d)
    if r < 1 or r > 2_147_483_647, do: PrologEx.Error.domain!("hash_range", r)

    case hash_canon(t, s, d) do
      :nonground -> :ok
      c -> {:unify, [{h, :erlang.phash2(c, r)}]}
    end
  end

  # term_size(T, N): Speicherzellen wie SWI – ein zusammengesetzter Term
  # f(A1, ..., An) 1 + n Zellen plus die seiner Argumente (eine Listenzelle
  # also 3), Atome, kleine Zahlen und Variablen 0. Was über dieselbe
  # gebundene Variable geteilt ist, zählt einmal (auch Zyklen: endlich).
  defbuiltin "term_size", [t, n] do
    {size, _memo} = tsize(t, subst(), %{})
    {:unify, [{n, size}]}
  end

  @hash_nodes 1000

  defp int_arg!(n) when is_integer(n), do: n
  defp int_arg!({:var, _}), do: PrologEx.Error.instantiation!()
  defp int_arg!(other), do: PrologEx.Error.type!("integer", other)

  defp hash_canon(t, s, depth) do
    canon(t, s, depth, 0)
  catch
    :nonground ->
      :nonground

    # zyklisch (nur bei unbeschränkter Tiefe): die Abwicklung in
    # Breitensuche, die ersten @hash_nodes Knoten – gleiche rationale
    # Bäume haben gleiche Abwicklungen
    :"$cyclic" ->
      if PrologEx.Builtins.Order.variables(t, s) == [],
        do: {:cyclic, bfs(:queue.from_list([t]), s, @hash_nodes, [])},
        else: :nonground
  end

  # kanonische Form: atomar wie es ist, zusammengesetzt {Name, Stelligkeit,
  # Argumente} (Listen als '.'/2, ohne Markierungen); :cut jenseits der Tiefe
  defp canon(_t, _s, 0, _d), do: :cut

  defp canon(t0, s, depth, d) do
    t = Store.walk(t0, s)
    d = PrologEx.Cyclic.step(t, t0, d, s)

    case tnode(t) do
      :var -> throw(:nonground)
      {:atomic, a} -> a
      {f, args} -> {f, length(args), Enum.map(args, &canon(&1, s, dec(depth), d))}
    end
  end

  defp dec(:inf), do: :inf
  defp dec(n), do: n - 1

  defp bfs(q, s, budget, acc) do
    case {budget, :queue.out(q)} do
      {0, _} ->
        Enum.reverse(acc)

      {_, {:empty, _}} ->
        Enum.reverse(acc)

      {_, {{:value, t}, q}} ->
        case tnode(Store.walk(t, s)) do
          {:atomic, a} ->
            bfs(q, s, budget - 1, [a | acc])

          {f, args} ->
            bfs(:queue.join(q, :queue.from_list(args)), s, budget - 1, [{f, length(args)} | acc])
        end
    end
  end

  defp tnode({:var, _}), do: :var
  defp tnode([h | t]), do: {".", [h, t]}
  defp tnode({:glist, [h | t]}), do: {".", [h, glist_rest(t)]}
  defp tnode({tag, f, args}) when tag in [:struct, :gstruct], do: {f, args}
  defp tnode(a), do: {:atomic, a}

  defp glist_rest([_ | _] = t), do: {:glist, t}
  defp glist_rest(t), do: t

  defp tsize({:var, _} = v, s, memo) do
    case memo do
      %{^v => _} ->
        {0, memo}

      _ ->
        case Store.binding(s, v) do
          {:ok, t} -> tsize(t, s, Map.put(memo, v, true))
          :error -> {0, memo}
        end
    end
  end

  defp tsize(t, s, memo) do
    case tnode(t) do
      {f, args} when is_binary(f) ->
        Enum.reduce(args, {1 + length(args), memo}, fn a, {n, memo} ->
          {k, memo} = tsize(a, s, memo)
          {n + k, memo}
        end)

      _ ->
        {0, memo}
    end
  end

  # cyclic_term(T) wie SWI (Heimat library(swi)): T ist ein rationaler
  # Baum, der nicht endlich ist
  defbuiltin "cyclic_term", [t] do
    not acyclic?(t, subst())
  end

  @doc false
  # auch für Bibliotheken in Elixir (clpb)
  def acyclic?(t, s), do: acyclic(t, s, MapSet.new(), %{}) != :cyclic

  # done: als azyklisch bekannte Variablen und (PrologEx.Share) Teilterme;
  # ein vollständig geprüfter Teilterm bleibt azyklisch, über welchen Pfad
  # man ihn auch erreicht (ein Zyklus über ihn wäre schon gefunden worden)
  defp acyclic({:var, _} = x, s, path, done) do
    case Store.binding(s, x) do
      :error ->
        done

      {:ok, t} ->
        cond do
          Map.has_key?(done, x) ->
            done

          MapSet.member?(path, x) ->
            :cyclic

          true ->
            case acyclic(t, s, MapSet.put(path, x), done) do
              :cyclic -> :cyclic
              done -> Map.put(done, x, true)
            end
        end
    end
  end

  defp acyclic({:struct, _, args} = t, s, path, done) do
    case PrologEx.Share.get(done, t) do
      {:ok, _} ->
        done

      :error ->
        case acyclic_all(args, s, path, done) do
          :cyclic -> :cyclic
          done -> PrologEx.Share.put(done, t, true)
        end
    end
  end

  defp acyclic([h | t], s, path, done), do: acyclic_all([h, t], s, path, done)
  # ground markierte Terme und Atome/Zahlen sind immer endlich
  defp acyclic(_, _s, _path, done), do: done

  defp acyclic_all([], _s, _path, done), do: done

  defp acyclic_all([x | xs], s, path, done) do
    case acyclic(x, s, path, done) do
      :cyclic -> :cyclic
      done -> acyclic_all(xs, s, path, done)
    end
  end

  defbuiltin "functor", [t, name, arity] do
    functor(t, name, arity, subst())
  end

  @doc false
  # functor/3 – auch direkt aus der Maschine (PrologEx.step/5)
  def functor(t, name, arity, s) do
    case PrologEx.Store.walk(t, s) do
      {:var, _} ->
        n = PrologEx.Store.walk(name, s)
        ar = PrologEx.Store.walk(arity, s)

        cond do
          match?({:var, _}, n) or match?({:var, _}, ar) ->
            PrologEx.Error.instantiation!()

          not is_integer(ar) ->
            PrologEx.Error.type!("integer", ar)

          ar < 0 ->
            PrologEx.Error.domain!("not_less_than_zero", ar)

          ar == 0 and (is_number(n) or Core.atom?(n) or match?({:rat, _, _}, n)) ->
            {:unify, [{t, n}]}

          ar == 0 ->
            PrologEx.Error.type!("atomic", n)

          not Core.atom?(n) ->
            if Core.compound?(n),
              do: PrologEx.Error.type!("atomic", n),
              else: PrologEx.Error.type!("atom", n)

          ar > PrologEx.Flags.max_arity() ->
            PrologEx.Error.representation!("max_arity")

          true ->
            # groß: vorab gegen eine Speichergrenze (Argument + Variable)
            if ar > 10_000, do: PrologEx.reserve!(5 * ar)
            {:unify, [{t, mk(atom_name(n), Enum.map(1..ar, fn _ -> fresh_var() end))}]}
        end

      tt ->
        # Name und Stelligkeit sind atomar: direkt binden bzw. vergleichen
        {f, args} = parts(tt)

        with {:ok, s} <- bind_atomic(name, f, s),
             {:ok, s} <- bind_atomic(arity, length(args), s) do
          {:subst, s}
        else
          :error -> :fail
        end
    end
  end

  # t mit dem atomaren Wert v unifizieren, ohne den allgemeinen Weg:
  # ungebunden → binden (bind/3 vermerkt attributierte Variablen zum
  # Wecken), sonst strikt vergleichen (wie unify/4: 1 und 1.0 verschieden);
  # ein Occurs-Check ist bei atomarem v nie nötig
  defp bind_atomic(t, v, s) do
    case PrologEx.Store.walk(t, s) do
      {:var, _} = x -> {:ok, PrologEx.Store.bind(x, v, s)}
      ^v -> {:ok, s}
      _ -> :error
    end
  end

  # arg(N, T, A): N-tes Argument. ISO 8.5.2.3: N muss eine Zahl sein
  # (ein offenes N gibt instantiation_error, kein Aufzählen wie in SWI) –
  # also höchstens eine Lösung
  defbuiltin "arg", [n, t, x] do
    arg(n, t, x, subst())
  end

  @doc false
  # arg/3 – auch direkt aus der Maschine (PrologEx.step/5)
  def arg(n, t, x, s) do
    args =
      case PrologEx.Store.walk(t, s) do
        {:var, _} ->
          PrologEx.Error.instantiation!()

        tt ->
          if Core.compound?(tt),
            do: elem(parts(tt), 1),
            else: PrologEx.Error.type!("compound", PrologEx.resolve(tt, s))
      end

    case PrologEx.Store.walk(n, s) do
      k when is_integer(k) and k >= 1 ->
        case nth_arg(args, k) do
          {:ok, a} -> {:unify, [{x, a}]}
          :none -> :fail
        end

      k when is_integer(k) and k >= 0 ->
        :fail

      k when is_integer(k) ->
        PrologEx.Error.domain!("not_less_than_zero", k)

      {:var, _} ->
        PrologEx.Error.instantiation!()

      other ->
        PrologEx.Error.type!("integer", PrologEx.resolve(other, s))
    end
  end

  # k-tes Element (1-basiert) in einem Durchgang, ohne vorher die Länge
  defp nth_arg([a | _], 1), do: {:ok, a}
  defp nth_arg([_ | as], k), do: nth_arg(as, k - 1)
  defp nth_arg([], _k), do: :none

  # copy_term(T, C): Kopie mit frischen Variablen
  defbuiltin "copy_term", [t, c] do
    copy_term(t, c, subst())
  end

  @doc false
  # copy_term/2 – auch direkt aus der Maschine (PrologEx.step/5). Die Kopie
  # enthält nur frische Variablen: eine gewöhnliche ungebundene Variable C
  # kann sie nicht enthalten, also direkt binden (kein Occurs-Check nötig);
  # eine attributierte C unifiziert wie bisher (die Kopie wird an sie
  # gebunden, ohne zu wecken)
  def copy_term(t, c, s) do
    case PrologEx.copy_cyclic(t, s) do
      {copy, []} ->
        case PrologEx.Store.walk(c, s) do
          {:var, {:attv, _}} -> {:unify, [{c, copy}]}
          {:var, _} = v -> {:subst, PrologEx.Store.bind(v, copy, s)}
          _ -> {:unify, [{c, copy}]}
        end

      # ein zyklischer Term: dazu die Gleichungen der Kopie (frische
      # Variablen) binden
      {copy, eqs} ->
        {:unify, eqs ++ [{c, copy}]}
    end
  end

  # T =.. [Name | Args]
  defbuiltin "=..", [t, l] do
    univ(t, l, subst())
  end

  @doc false
  # =../2 – auch direkt aus der Maschine (PrologEx.step/5)
  def univ(t, l, s) do
    case PrologEx.Store.walk(t, s) do
      {:var, _} ->
        case proper_list(l, s) do
          {:ok, [n]} ->
            n = PrologEx.Store.walk(n, s)

            cond do
              match?({:var, _}, n) -> PrologEx.Error.instantiation!()
              Core.compound?(n) -> PrologEx.Error.type!("atomic", n)
              true -> {:unify, [{t, n}]}
            end

          {:ok, [n | args]} ->
            case PrologEx.Store.walk(n, s) do
              {:var, _} ->
                PrologEx.Error.instantiation!()

              nn ->
                cond do
                  not Core.atom?(nn) ->
                    PrologEx.Error.type!("atom", nn)

                  length(args) > PrologEx.Flags.max_arity() ->
                    PrologEx.Error.representation!("max_arity")

                  true ->
                    {:unify, [{t, mk(atom_name(nn), args)}]}
                end
            end

          {:ok, []} ->
            PrologEx.Error.domain!("non_empty_list", [])

          :partial ->
            PrologEx.Error.instantiation!()

          :not_list ->
            PrologEx.Error.type!("list", PrologEx.resolve(l, s))
        end

      tt ->
        {f, args} = parts(tt)
        {:unify, [{l, list([f | args])}]}
    end
  end

  # Funktor und Argumente eines gebundenen Terms; atomar: {T, []}
  defp parts(t) do
    case uncons(t) do
      {:cons, h, tl} ->
        {a("."), [h, tl]}

      _ ->
        case t do
          {tag, f, args} when tag in [:struct, :gstruct] -> {a(f), args}
          other -> {other, []}
        end
    end
  end

  defp atom_name([]), do: "[]"
  defp atom_name({:atom, n}), do: n

  # Elemente einer echten Liste (Elemente unaufgelöst)
  defp proper_list(l, s) do
    {_n, rest} = PrologEx.Builtins.Lists.skip_list(l, s)

    case rest do
      [] -> {:ok, PrologEx.Builtins.Lists.items(l, s)}
      {:var, _} -> :partial
      _ -> :not_list
    end
  end
end
