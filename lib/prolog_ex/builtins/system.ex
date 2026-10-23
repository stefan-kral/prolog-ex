defmodule PrologEx.Builtins.System do
  @moduledoc "Prolog-Flags und Zugriff auf die Datenbank (clause/2, current_predicate/1)."
  use PrologEx.Builtin
  alias PrologEx.{Builtins, Compiler, Flags}

  # clause(H, B): H :- B ist eine Klausel (Fakten: B = true). Gilt für
  # Benutzerprädikate und in Prolog geschriebene Bibliotheksprädikate; in
  # Elixir geschriebene Builtins, Steuerkonstrukte und $-Hilfsprädikate
  # ergeben permission_error. Die Klauseln werden mit frischen Variablen
  # kopiert; die Liste ist ein Schnappschuss beim Aufruf.
  defbuiltin "clause", [h, b], nondet: true do
    head =
      case deref(h) do
        {:var, _} -> raise "instantiation_error"
        hh -> hh
      end

    key = Compiler.key(head)

    case deref(b) do
      {:var, _} -> :ok
      bb -> Compiler.key(bb)
    end

    clause_results(source(key, db()), h, b)
  end

  # current_predicate(Name/Arity): benutzerdefinierte Prädikate
  defbuiltin "current_predicate", [pi], nondet: true do
    keys = db() |> Map.keys() |> Enum.filter(&match?({_, _}, &1)) |> Enum.sort()

    case PrologEx.unmark_top(deref(pi)) do
      {:var, _} ->
        for {n, ar} <- keys, do: {:unify, [{pi, mk("/", [a(n), ar])}]}

      {:struct, "/", [name, arity]} ->
        nm = deref(name)
        ar = deref(arity)

        unless match?({:var, _}, nm) or match?({:atom, _}, nm) or nm == [],
          do: raise("type_error(predicate_indicator, #{format(resolve(pi))})")

        unless match?({:var, _}, ar) or is_integer(ar),
          do: raise("type_error(predicate_indicator, #{format(resolve(pi))})")

        for {n, k} <- keys,
            match?({:var, _}, nm) or a(n) == nm,
            match?({:var, _}, ar) or k == ar,
            do: {:unify, [{name, a(n)}, {arity, k}]}

      other ->
        raise "type_error(predicate_indicator, #{format(resolve(other))})"
    end
  end

  defp source(key, db) do
    {name, arity} = key

    case Map.fetch(db, key) do
      {:ok, pred} ->
        PrologEx.pred_source(pred)

      :error ->
        case Builtins.lookup(key) do
          {:prolog, pred, _} ->
            if String.starts_with?(name, "$"),
              do: raise("permission_error(access, private_procedure, #{name}/#{arity})"),
              else: PrologEx.pred_source(pred)

          nil ->
            if Builtins.protected?(key),
              do: raise("permission_error(access, private_procedure, #{name}/#{arity})"),
              else: []

          _elixir ->
            raise "permission_error(access, private_procedure, #{name}/#{arity})"
        end
    end
  end

  # eine Lösung je Klausel, lazy; Kopf und Rumpf gemeinsam kopiert
  defp clause_results([], _h, _b), do: []
  defp clause_results([cl], h, b), do: [clause_result(cl, h, b)]

  defp clause_results([cl | rest], h, b),
    do: [clause_result(cl, h, b) | fn -> clause_results(rest, h, b) end]

  defp clause_result({head, body}, h, b) do
    {_tag, "$clause", [head2, body2]} =
      PrologEx.copy_fresh({:struct, "$clause", [head, body]}, %{})

    {:unify, [{h, head2}, {b, body2}]}
  end

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
