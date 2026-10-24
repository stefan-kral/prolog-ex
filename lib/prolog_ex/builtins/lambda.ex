defmodule PrologEx.Builtins.Lambda do
  @moduledoc """
  `library(lambda)` nach Ulrich Neumerkel, in Elixir (schnelle Variante;
  dieselbe Bibliothek in reinem Prolog: `library(lambda_pl)`).

      ?- use_module(library(lambda)), use_module(library(apply)).
      ?- maplist(\\X^Y^(Y is X * 2), [1, 2, 3], L).
      L = [2, 4, 6].
      ?- N = 10, maplist(N+\\X^Y^(Y is X + N), [1, 2], L).
      L = [11, 12].

    * `\\X1^...^Xn^Rumpf` – Lambda: beim Aufruf mit Argumenten A1, ...
      wird der ganze Lambda-Ausdruck kopiert (frische Variablen, ohne
      Attribute: copy_term_nat), dann Xi = Ai und Rumpf aufgerufen
      (übrige Argumente an den Rumpf angehängt, wie call/N).
    * `Free+\\Lambda` – wie `\\Lambda`, aber die Variablen von Free werden
      nicht kopiert (globale Variablen).
    * `X^Rumpf` ohne `\\` – keine Kopie: X und alle Variablen bleiben
      dieselben (Bindungen bleiben also nach dem Aufruf bestehen).
    * Zu wenige Argumente (`\\X^Y^G` mit nur einem) ergeben
      existence_error(lambda_parameter, M:Y^G), wie bei Neumerkel.

  Prädikate: `(^)/3..9`, `(\\)/1..7`, `(+\\)/2..7`, alle als
  meta_predicate deklariert; Operator `op(201, xfx, +\\)` (wird mit
  use_module gesetzt).

  Unterschied zur Prolog-Variante: Kopie, Parameterbindung und der Aufruf
  des Rumpfs geschehen in einem Schritt – ohne die Zwischenaufrufe
  `call/N` → `^/N` → `call/N-1` → ... je Parameter.
  """
  use PrologEx.Builtin, module: "lambda"
  alias PrologEx.Error

  def ops, do: [{"lambda", 201, "xfx", "+\\"}]

  def meta do
    hats = for n <- 1..7, do: {"lambda", "^", ["?", n - 1 | List.duplicate("?", n)]}
    bs = for n <- 0..6, do: {"lambda", "\\", [n | List.duplicate("?", n)]}
    gs = for n <- 0..5, do: {"lambda", "+\\", ["?", n | List.duplicate("?", n)]}
    hats ++ bs ++ gs
  end

  defbuiltin "^", [v, goal, a1] do
    hat(v, goal, [a1], subst())
  end

  defbuiltin "^", [v, goal, a1, a2] do
    hat(v, goal, [a1, a2], subst())
  end

  defbuiltin "^", [v, goal, a1, a2, a3] do
    hat(v, goal, [a1, a2, a3], subst())
  end

  defbuiltin "^", [v, goal, a1, a2, a3, a4] do
    hat(v, goal, [a1, a2, a3, a4], subst())
  end

  defbuiltin "^", [v, goal, a1, a2, a3, a4, a5] do
    hat(v, goal, [a1, a2, a3, a4, a5], subst())
  end

  defbuiltin "^", [v, goal, a1, a2, a3, a4, a5, a6] do
    hat(v, goal, [a1, a2, a3, a4, a5, a6], subst())
  end

  defbuiltin "^", [v, goal, a1, a2, a3, a4, a5, a6, a7] do
    hat(v, goal, [a1, a2, a3, a4, a5, a6, a7], subst())
  end

  defbuiltin "\\", [fc] do
    lambda(fc, nil, [], subst())
  end

  defbuiltin "\\", [fc, a1] do
    lambda(fc, nil, [a1], subst())
  end

  defbuiltin "\\", [fc, a1, a2] do
    lambda(fc, nil, [a1, a2], subst())
  end

  defbuiltin "\\", [fc, a1, a2, a3] do
    lambda(fc, nil, [a1, a2, a3], subst())
  end

  defbuiltin "\\", [fc, a1, a2, a3, a4] do
    lambda(fc, nil, [a1, a2, a3, a4], subst())
  end

  defbuiltin "\\", [fc, a1, a2, a3, a4, a5] do
    lambda(fc, nil, [a1, a2, a3, a4, a5], subst())
  end

  defbuiltin "\\", [fc, a1, a2, a3, a4, a5, a6] do
    lambda(fc, nil, [a1, a2, a3, a4, a5, a6], subst())
  end

  defbuiltin "+\\", [gv, fc] do
    lambda(fc, gv, [], subst())
  end

  defbuiltin "+\\", [gv, fc, a1] do
    lambda(fc, gv, [a1], subst())
  end

  defbuiltin "+\\", [gv, fc, a1, a2] do
    lambda(fc, gv, [a1, a2], subst())
  end

  defbuiltin "+\\", [gv, fc, a1, a2, a3] do
    lambda(fc, gv, [a1, a2, a3], subst())
  end

  defbuiltin "+\\", [gv, fc, a1, a2, a3, a4] do
    lambda(fc, gv, [a1, a2, a3, a4], subst())
  end

  defbuiltin "+\\", [gv, fc, a1, a2, a3, a4, a5] do
    lambda(fc, gv, [a1, a2, a3, a4, a5], subst())
  end

  # ---------------------------------------------------------------------

  # \\Lambda bzw. Free+\\Lambda mit Argumenten
  defp lambda(fc, free, args, s) do
    {m, lam} = PrologEx.Builtins.Modules.strip(fc, "user", s)
    copy = if free, do: PrologEx.copy_fresh(lam, s, free), else: PrologEx.copy_fresh(lam, s)
    params(m, copy, args, s)
  end

  # V^Goal mit Argumenten A1, ...: ohne Kopie
  defp hat(v, goal, [a | rest], s) do
    case PrologEx.unify(v, a, s) do
      {:ok, s} ->
        {m, g} = PrologEx.Builtins.Modules.strip(goal, "user", s)
        params(m, g, rest, s)

      _ ->
        :fail
    end
  end

  # Parameter X^... der Reihe nach an die Argumente binden, dann den Rumpf
  # mit den übrigen Argumenten aufrufen
  defp params(m, t, args, s) do
    case {PrologEx.unmark_top(PrologEx.walk(t, s)), args} do
      {{:struct, "^", [v, body]}, [a | rest]} ->
        case PrologEx.unify(v, a, s) do
          {:ok, s} -> params(m, body, rest, s)
          _ -> :fail
        end

      {{:struct, "^", [_, _]} = g, []} ->
        Error.existence!("lambda_parameter", mk(":", [a(m), PrologEx.resolve(g, s)]))

      {{:var, _}, _} ->
        Error.instantiation!()

      {g, args} ->
        # unmarkiert bauen: add_args erwartet ein normales M:G
        {:call, PrologEx.add_args({:struct, ":", [a(m), g]}, args), s}
    end
  end
end
