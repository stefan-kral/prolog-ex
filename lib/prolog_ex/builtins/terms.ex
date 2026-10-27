defmodule PrologEx.Builtins.Terms do
  @moduledoc "Termaufbau und -zerlegung: functor/3, (=..)/2."
  use PrologEx.Builtin
  alias PrologEx.Builtins.Core

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

  defbuiltin "functor", [t, name, arity] do
    case deref(t) do
      {:var, _} ->
        n = deref(name)
        ar = deref(arity)

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

          true ->
            {:unify, [{t, mk(atom_name(n), Enum.map(1..ar, fn _ -> fresh_var() end))}]}
        end

      tt ->
        {f, args} = parts(tt)
        {:unify, [{name, f}, {arity, length(args)}]}
    end
  end

  # arg(N, T, A): N-tes Argument. ISO 8.5.2.3: N muss eine Zahl sein
  # (ein offenes N gibt instantiation_error, kein Aufzählen wie in SWI)
  defbuiltin "arg", [n, t, x], nondet: true do
    args =
      case deref(t) do
        {:var, _} ->
          PrologEx.Error.instantiation!()

        tt ->
          if Core.compound?(tt),
            do: elem(parts(tt), 1),
            else: PrologEx.Error.type!("compound", resolve(tt))
      end

    case deref(n) do
      k when is_integer(k) and k >= 1 and k <= length(args) ->
        [{:unify, [{x, Enum.at(args, k - 1)}]}]

      k when is_integer(k) and k >= 0 ->
        []

      k when is_integer(k) ->
        PrologEx.Error.domain!("not_less_than_zero", k)

      {:var, _} ->
        PrologEx.Error.instantiation!()

      other ->
        PrologEx.Error.type!("integer", resolve(other))
    end
  end

  # copy_term(T, C): Kopie mit frischen Variablen
  defbuiltin "copy_term", [t, c] do
    {:unify, [{c, PrologEx.copy_fresh(t, subst())}]}
  end

  # T =.. [Name | Args]
  defbuiltin "=..", [t, l] do
    case deref(t) do
      {:var, _} ->
        case proper_list(l, subst()) do
          {:ok, [n]} ->
            n = deref(n)

            cond do
              match?({:var, _}, n) -> PrologEx.Error.instantiation!()
              Core.compound?(n) -> PrologEx.Error.type!("atomic", n)
              true -> {:unify, [{t, n}]}
            end

          {:ok, [n | args]} ->
            case deref(n) do
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
            PrologEx.Error.type!("list", resolve(l))
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
