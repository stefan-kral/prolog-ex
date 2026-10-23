defmodule PrologEx.Builtins.System do
  @moduledoc "Prolog-Flags."
  use PrologEx.Builtin
  alias PrologEx.Flags

  defbuiltin "current_prolog_flag", [flag, value], nondet: true do
    case deref(flag) do
      {:var, _} ->
        for {name, v} <- Flags.all(), do: {:unify, [{flag, a(name)}, {value, v}]}

      {:atom, name} ->
        case Flags.get(name) do
          nil -> raise "domain_error(prolog_flag, #{name})"
          v -> [{:unify, [{value, v}]}]
        end

      other ->
        raise "type_error(atom, #{format(resolve(other))})"
    end
  end

  defbuiltin "set_prolog_flag", [flag, value] do
    case {deref(flag), deref(value)} do
      {{:var, _}, _} -> raise "instantiation_error"
      {_, {:var, _}} -> raise "instantiation_error"
      {{:atom, name}, v} -> Flags.set(name, resolve(v))
      {other, _} -> raise "type_error(atom, #{format(resolve(other))})"
    end
  end
end
