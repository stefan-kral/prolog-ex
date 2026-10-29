defmodule PrologEx.Builtins.Terms do
  @moduledoc "Termaufbau und -zerlegung: functor/3, (=..)/2."
  use PrologEx.Builtin
  alias PrologEx.Builtins.Core

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

  @doc false
  # plus/3 – auch direkt aus der Maschine (PrologEx: engine_step)
  def plus(x, y, z, s) do
    a = int_or_var!(x, s)
    b = int_or_var!(y, s)
    c = int_or_var!(z, s)

    cond do
      is_integer(a) and is_integer(b) -> int_result(c, a + b, s)
      is_integer(a) and is_integer(c) -> {:subst, PrologEx.bind(b, c - a, s)}
      is_integer(b) and is_integer(c) -> {:subst, PrologEx.bind(a, c - b, s)}
      true -> PrologEx.Error.instantiation!()
    end
  end

  defp int_or_var!(t, s) do
    case PrologEx.walk(t, s) do
      n when is_integer(n) -> n
      {:var, _} = v -> v
      other -> PrologEx.Error.type!("integer", PrologEx.resolve(other, s))
    end
  end

  # Ergebnis n an t (ganze Zahl oder ungebundene Variable)
  defp int_result(n, n, _s), do: :ok
  defp int_result(m, _n, _s) when is_integer(m), do: :fail
  defp int_result(v, n, s), do: {:subst, PrologEx.bind(v, n, s)}

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
    acyclic(t, subst(), MapSet.new(), MapSet.new()) != :cyclic
  end

  defp acyclic({:var, _} = x, s, path, done) do
    cond do
      not Map.has_key?(s, x) ->
        done

      MapSet.member?(done, x) ->
        done

      MapSet.member?(path, x) ->
        :cyclic

      true ->
        case acyclic(Map.fetch!(s, x), s, MapSet.put(path, x), done) do
          :cyclic -> :cyclic
          done -> MapSet.put(done, x)
        end
    end
  end

  defp acyclic({:struct, _, args}, s, path, done), do: acyclic_all(args, s, path, done)
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

  # mehr Argumente auf einmal anzulegen ist sinnlos (je ~50 Byte)
  @max_build 268_435_456

  defbuiltin "functor", [t, name, arity] do
    functor(t, name, arity, subst())
  end

  @doc false
  # functor/3 – auch direkt aus der Maschine (PrologEx.step/5)
  def functor(t, name, arity, s) do
    case PrologEx.walk(t, s) do
      {:var, _} ->
        n = PrologEx.walk(name, s)
        ar = PrologEx.walk(arity, s)

        cond do
          match?({:var, _}, n) or match?({:var, _}, ar) ->
            PrologEx.Error.instantiation!()

          not is_integer(ar) ->
            PrologEx.Error.type!("integer", ar)

          ar < 0 ->
            PrologEx.Error.domain!("not_less_than_zero", ar)

          ar == 0 and (is_number(n) or Core.atom?(n)) ->
            {:unify, [{t, n}]}

          ar == 0 ->
            PrologEx.Error.type!("atomic", n)

          not Core.atom?(n) ->
            if Core.compound?(n),
              do: PrologEx.Error.type!("atomic", n),
              else: PrologEx.Error.type!("atom", n)

          # max_arity ist unbeschränkt, der Speicher nicht
          ar > @max_build ->
            PrologEx.Error.resource!("memory")

          true ->
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
    case PrologEx.walk(t, s) do
      {:var, _} = x -> {:ok, PrologEx.bind(x, v, s)}
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
      case PrologEx.walk(t, s) do
        {:var, _} ->
          PrologEx.Error.instantiation!()

        tt ->
          if Core.compound?(tt),
            do: elem(parts(tt), 1),
            else: PrologEx.Error.type!("compound", PrologEx.resolve(tt, s))
      end

    case PrologEx.walk(n, s) do
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
    {:unify, [{c, PrologEx.copy_fresh(t, subst())}]}
  end

  # T =.. [Name | Args]
  defbuiltin "=..", [t, l] do
    univ(t, l, subst())
  end

  @doc false
  # =../2 – auch direkt aus der Maschine (PrologEx.step/5)
  def univ(t, l, s) do
    case PrologEx.walk(t, s) do
      {:var, _} ->
        case proper_list(l, s) do
          {:ok, [n]} ->
            n = PrologEx.walk(n, s)

            cond do
              match?({:var, _}, n) -> PrologEx.Error.instantiation!()
              Core.compound?(n) -> PrologEx.Error.type!("atomic", n)
              true -> {:unify, [{t, n}]}
            end

          {:ok, [n | args]} ->
            case PrologEx.walk(n, s) do
              {:var, _} ->
                PrologEx.Error.instantiation!()

              nn ->
                if Core.atom?(nn),
                  do: {:unify, [{t, mk(atom_name(nn), args)}]},
                  else: PrologEx.Error.type!("atom", nn)
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
