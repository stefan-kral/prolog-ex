defmodule PrologEx.Builtins.System do
  @moduledoc "Prolog-Flags und Zugriff auf die Datenbank (clause/2, current_predicate/1)."
  use PrologEx.Builtin
  alias PrologEx.{Builtins, Compiler, Flags}
  alias PrologEx.Builtins.Modules

  # clause(H, B): H :- B ist eine Klausel (Fakten: B = true). H darf
  # M:Kopf sein; sonst gilt das Kontextmodul, mit derselben Sichtbarkeit wie
  # ein Aufruf. Gilt für Benutzerprädikate und in Prolog geschriebene
  # Bibliotheksprädikate; Builtins von system, in Elixir geschriebene und
  # $-Hilfsprädikate ergeben permission_error. Die Klauseln werden mit
  # frischen Variablen kopiert; die Liste ist ein Schnappschuss beim Aufruf.
  defbuiltin "clause", [h, b], nondet: true do
    {m, head} = Modules.strip(h, context_module(), subst())

    head =
      case head do
        {:var, _} -> PrologEx.Error.instantiation!()
        hh -> hh
      end

    {name, arity} = Compiler.key(head)

    case deref(b) do
      {:var, _} -> :ok
      bb -> Compiler.key(bb)
    end

    clause_results(source(m, name, arity, db()), head, b)
  end

  # current_predicate(PI), PI = Name/Arity oder M:Name/Arity: in M (sonst
  # im Kontextmodul) definierte oder dorthin importierte Prädikate
  # (keine von system). Mit ungebundenem M: alle Module.
  # style_check(+Art) / style_check(-Art) wie SWI: Warnungen beim Laden
  # (singleton, discontiguous) ein- und ausschalten; ?(Art) fragt ab
  defbuiltin "style_check", [spec] do
    case resolve(spec) do
      {:var, _} ->
        PrologEx.Error.instantiation!()

      {:struct, sign, [x]} when sign in ["+", "-", "?"] ->
        kind =
          case x do
            {:var, _} when sign != "?" -> PrologEx.Error.instantiation!()
            {:atom, k} when k in ["singleton", "discontiguous"] -> String.to_atom(k)
            other -> PrologEx.Error.domain!("style_name", other)
          end

        case sign do
          "+" -> PrologEx.StyleCheck.set(kind, true)
          "-" -> PrologEx.StyleCheck.set(kind, false)
          "?" -> if PrologEx.StyleCheck.on?(kind), do: :ok, else: :fail
        end

      other ->
        PrologEx.Error.domain!("style_name", other)
    end
  end

  defbuiltin "current_predicate", [pi], nondet: true do
    db = db()

    {mod_t, spec} =
      case PrologEx.unmark_top(deref(pi)) do
        {:struct, ":", [m, inner]} -> {m, PrologEx.unmark_top(deref(inner))}
        other -> {a(context_module()), other}
      end

    visible = for {m, n, ar} <- visible_keys(db, deref(mod_t)), do: {m, n, ar}

    {name, arity} =
      case spec do
        {:var, _} -> {nil, nil}
        {:struct, "/", [name, arity]} -> {name, arity}
        other -> PrologEx.Error.type!("predicate_indicator", resolve(other))
      end

    if name do
      nm = deref(name)
      ar = deref(arity)

      unless match?({:var, _}, nm) or match?({:atom, _}, nm) or nm == [],
        do: PrologEx.Error.type!("predicate_indicator", resolve(pi))

      unless match?({:var, _}, ar) or (is_integer(ar) and ar >= 0),
        do: PrologEx.Error.type!("predicate_indicator", resolve(pi))

      for {m, n, k} <- visible,
          match?({:var, _}, nm) or a(n) == nm,
          match?({:var, _}, ar) or k == ar,
          do: {:unify, [{mod_t, a(m)}, {name, a(n)}, {arity, k}]}
    else
      for {m, n, k} <- visible,
          do: {:unify, [{mod_t, a(m)}, {spec, mk("/", [a(n), k])}]}
    end
  end

  defp visible_keys(db, {:atom, m}), do: visible_keys(db, m)

  defp visible_keys(db, {:var, _}) do
    for({m, n, ar} <- Map.keys(db), is_binary(m), do: {m, n, ar}) |> Enum.sort()
  end

  defp visible_keys(db, m) when is_binary(m) do
    local = for {^m, n, ar} <- Map.keys(db), do: {m, n, ar}
    imported = for {:import, ^m, n, ar} <- Map.keys(db), do: {m, n, ar}
    Enum.sort(local ++ imported)
  end

  defp visible_keys(_db, other), do: PrologEx.Error.type!("module", other)

  defp source(m, name, arity, db) do
    private = fn mod ->
      pi = PrologEx.Error.indicator(name, arity)
      pi = if mod in ["user", "system"], do: pi, else: mk(":", [a(mod), pi])
      PrologEx.Error.permission!("access", "private_procedure", pi)
    end

    case PrologEx.locate(db, m, name, arity) do
      {:db, _, pred} ->
        PrologEx.pred_source(pred)

      {:builtin, lm, {:prolog, pred, _}} ->
        if lm == "system" or String.starts_with?(name, "$"),
          do: private.(lm),
          else: PrologEx.pred_source(pred)

      {:builtin, lm, _elixir} ->
        private.(lm)

      :none ->
        if Builtins.system?({name, arity}), do: private.("system"), else: []
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

    {:unify, [{h, head2}, {b, converted_body(body2)}]}
  end

  # ISO 7.6.1: im gespeicherten Rumpf steht jede Variable an Zielstelle
  # als call(V) – clause/2 zeigt das so
  defp converted_body({:var, _} = v), do: mk("call", [v])

  defp converted_body({tag, op, [x, y]})
       when tag in [:struct, :gstruct] and op in [",", ";", "->", "*->"],
       do: mk(op, [converted_body(x), converted_body(y)])

  defp converted_body(t), do: t

  defbuiltin "current_prolog_flag", [flag, value], nondet: true do
    case deref(flag) do
      {:var, _} ->
        for {name, v} <- Flags.all(), do: {:unify, [{flag, a(name)}, {value, v}]}

      {:atom, name} ->
        case Flags.get(name) do
          nil -> PrologEx.Error.domain!("prolog_flag", a(name))
          v -> [{:unify, [{value, v}]}]
        end

      other ->
        PrologEx.Error.type!("atom", resolve(other))
    end
  end

  defbuiltin "set_prolog_flag", [flag, value] do
    case {deref(flag), deref(value)} do
      {{:var, _}, _} -> PrologEx.Error.instantiation!()
      {_, {:var, _}} -> PrologEx.Error.instantiation!()
      {{:atom, name}, v} -> Flags.set(name, resolve(v))
      {other, _} -> PrologEx.Error.type!("atom", resolve(other))
    end
  end
end
