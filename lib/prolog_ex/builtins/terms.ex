defmodule PrologEx.Builtins.Terms do
  @moduledoc "Termaufbau und -zerlegung: functor/3, (=..)/2."
  use PrologEx.Builtin
  alias PrologEx.Builtins.Core

  # functor(T, Name, Arity)
  #   T gebunden:   Name/Arity von T (atomar: Name = T, Arity = 0)
  #   T ungebunden: T = Name(_, ..., _) mit frischen Variablen
  defbuiltin "functor", [t, name, arity] do
    case deref(t) do
      {:var, _} ->
        n = deref(name)
        ar = deref(arity)

        cond do
          match?({:var, _}, n) or match?({:var, _}, ar) ->
            raise "instantiation_error"

          not is_integer(ar) ->
            raise "type_error(integer, #{format(ar)})"

          ar < 0 ->
            raise "domain_error(not_less_than_zero, #{ar})"

          ar == 0 and (is_number(n) or Core.atom?(n)) ->
            {:unify, [{t, n}]}

          ar == 0 ->
            raise "type_error(atomic, #{format(n)})"

          not Core.atom?(n) ->
            if Core.compound?(n),
              do: raise("type_error(atomic, #{format(n)})"),
              else: raise("type_error(atom, #{format(n)})")

          true ->
            {:unify, [{t, mk(atom_name(n), Enum.map(1..ar, fn _ -> fresh_var() end))}]}
        end

      tt ->
        {f, args} = parts(tt)
        {:unify, [{name, f}, {arity, length(args)}]}
    end
  end

  # T =.. [Name | Args]
  defbuiltin "=..", [t, l] do
    case deref(t) do
      {:var, _} ->
        case proper_list(l, subst()) do
          {:ok, [n]} ->
            n = deref(n)

            cond do
              match?({:var, _}, n) -> raise "instantiation_error"
              Core.compound?(n) -> raise "type_error(atomic, #{format(n)})"
              true -> {:unify, [{t, n}]}
            end

          {:ok, [n | args]} ->
            case deref(n) do
              {:var, _} ->
                raise "instantiation_error"

              nn ->
                if Core.atom?(nn),
                  do: {:unify, [{t, mk(atom_name(nn), args)}]},
                  else: raise("type_error(atom, #{format(nn)})")
            end

          {:ok, []} ->
            raise "domain_error(non_empty_list, [])"

          :partial ->
            raise "instantiation_error"

          :not_list ->
            raise "type_error(list, #{format(resolve(l))})"
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
