defmodule PrologEx.Builtins.Yall do
  @moduledoc """
  `library(yall)` wie in SWI-Prolog („Yet Another Lambda Library“, Paulo
  Moura, Jan Wielemaker), in Elixir (schnelle Variante; dieselbe
  Bibliothek in reinem Prolog: `library(yall_pl)`).

      ?- use_module(library(yall)), use_module(library(apply)).
      ?- maplist([X, Y]>>(Y is X * 2), [1, 2, 3], L).
      L = [2,4,6].
      ?- maplist({N}/[X]>>(X > N), [3, 4]), N = 2.

    * `[X1,...]>>Rumpf` – Lambda: beim Aufruf mit A1, ... wird es kopiert
      (frische Variablen, ohne Attribute: copy_term_nat), Xi = Ai, die
      übrigen Argumente an den Rumpf angehängt (wie call/N).
    * `Free/[X1,...]>>Rumpf` – die Variablen von Free (`{V1,...}` oder
      `{}`) werden nicht kopiert: nur sie tragen Bindungen nach außen.
    * `Free/Rumpf` – wie `Free/[]>>Rumpf`.
    * Fehler wie SWI: Parameter ungebunden: instantiation_error; keine
      Liste: type_error(list, Ps); Free kein `{...}`: type_error(lambda_free,
      Free); weniger Argumente als Parameter: domain_error(lambda_parameters,
      Ps).

  Prädikate: `(>>)/2..9`, `(/)/2..9` (meta_predicate), `is_lambda/1`.

  Unterschied zur Prolog-Variante: Kopie, Parameterbindung und Aufruf des
  Rumpfs in einem Schritt, ohne `=..` und `call/N`. Wie dort, anders als
  SWI: Lambdas werden nicht beim Laden übersetzt, sie kopieren immer.
  """
  use PrologEx.Builtin, module: "yall"
  alias PrologEx.Error
  alias PrologEx.Store

  def meta do
    gts =
      for n <- 0..7,
          do: {"yall", ">>", ["?", if(n == 0, do: 0, else: ":") | List.duplicate("?", n)]}

    sls = for n <- 0..7, do: {"yall", "/", ["?", n | List.duplicate("?", n)]}
    gts ++ sls
  end

  defbuiltin ">>", [ps, lam] do
    call_lambda(ps, lam, [], subst())
  end

  defbuiltin ">>", [ps, lam, a1] do
    call_lambda(ps, lam, [a1], subst())
  end

  defbuiltin ">>", [ps, lam, a1, a2] do
    call_lambda(ps, lam, [a1, a2], subst())
  end

  defbuiltin ">>", [ps, lam, a1, a2, a3] do
    call_lambda(ps, lam, [a1, a2, a3], subst())
  end

  defbuiltin ">>", [ps, lam, a1, a2, a3, a4] do
    call_lambda(ps, lam, [a1, a2, a3, a4], subst())
  end

  defbuiltin ">>", [ps, lam, a1, a2, a3, a4, a5] do
    call_lambda(ps, lam, [a1, a2, a3, a4, a5], subst())
  end

  defbuiltin ">>", [ps, lam, a1, a2, a3, a4, a5, a6] do
    call_lambda(ps, lam, [a1, a2, a3, a4, a5, a6], subst())
  end

  defbuiltin ">>", [ps, lam, a1, a2, a3, a4, a5, a6, a7] do
    call_lambda(ps, lam, [a1, a2, a3, a4, a5, a6, a7], subst())
  end

  defbuiltin "/", [free, lam] do
    call_free(free, lam, [], subst())
  end

  defbuiltin "/", [free, lam, a1] do
    call_free(free, lam, [a1], subst())
  end

  defbuiltin "/", [free, lam, a1, a2] do
    call_free(free, lam, [a1, a2], subst())
  end

  defbuiltin "/", [free, lam, a1, a2, a3] do
    call_free(free, lam, [a1, a2, a3], subst())
  end

  defbuiltin "/", [free, lam, a1, a2, a3, a4] do
    call_free(free, lam, [a1, a2, a3, a4], subst())
  end

  defbuiltin "/", [free, lam, a1, a2, a3, a4, a5] do
    call_free(free, lam, [a1, a2, a3, a4, a5], subst())
  end

  defbuiltin "/", [free, lam, a1, a2, a3, a4, a5, a6] do
    call_free(free, lam, [a1, a2, a3, a4, a5, a6], subst())
  end

  defbuiltin "/", [free, lam, a1, a2, a3, a4, a5, a6, a7] do
    call_free(free, lam, [a1, a2, a3, a4, a5, a6, a7], subst())
  end

  defbuiltin "is_lambda", [t] do
    s = subst()

    case PrologEx.unmark_top(Store.walk(t, s)) do
      {:struct, ">>", [ps, _ | _]} -> if(lambda_params?(ps, s), do: :ok, else: :fail)
      {:struct, "/", [free, _ | _]} -> if(free?(free, s), do: :ok, else: :fail)
      _ -> :fail
    end
  end

  # ---------------------------------------------------------------------

  # Params>>Lambda mit Argumenten
  defp call_lambda(ps, lam, args, s) do
    {free, plist} =
      case PrologEx.unmark_top(Store.walk(ps, s)) do
        {:var, _} -> Error.instantiation!()
        {:struct, "/", [free, pl]} -> {free!(free, s), pl}
        pl -> {nil, pl}
      end

    list!(plist, s)
    whole = mk(">>", [plist, lam])
    copy = if free, do: PrologEx.copy_fresh(whole, s, free), else: PrologEx.copy_fresh(whole, s)
    {:struct, ">>", [pc, body]} = PrologEx.unmark_top(copy)
    bind(pc, args, body, ps, s)
  end

  # Free/Lambda mit Argumenten
  defp call_free(free, lam, args, s) do
    free = free!(free, s)
    body = PrologEx.copy_fresh(lam, s, free)
    {:call, PrologEx.add_args(PrologEx.unmark_top(body), args, s), s}
  end

  # Parameter der Reihe nach an die Argumente binden, dann den Rumpf mit
  # den übrigen Argumenten aufrufen
  defp bind(pc, args, body, culprit, s) do
    case {PrologEx.uncons(Store.walk(pc, s)), args} do
      {:empty, _} ->
        {:call, PrologEx.add_args(PrologEx.unmark_top(Store.walk(body, s)), args, s), s}

      {{:cons, p, rest}, [a | as]} ->
        case PrologEx.unify(p, a, s) do
          {:ok, s} -> bind(rest, as, body, culprit, s)
          _ -> :fail
        end

      _ ->
        Error.domain!("lambda_parameters", PrologEx.resolve(culprit, s))
    end
  end

  defp free!(free, s) do
    case PrologEx.unmark_top(Store.walk(free, s)) do
      {:var, _} -> Error.instantiation!()
      {:struct, "{}", [_]} = f -> f
      {:atom, "{}"} = f -> f
      other -> Error.type!("lambda_free", PrologEx.resolve(other, s))
    end
  end

  defp free?(free, s) do
    case PrologEx.unmark_top(Store.walk(free, s)) do
      {:struct, "{}", [_]} -> true
      {:atom, "{}"} -> true
      _ -> false
    end
  end

  defp list!(l, s) do
    case PrologEx.Builtins.Lists.skip_list(l, s) do
      {_, []} -> :ok
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(l, s))
    end
  end

  defp lambda_params?(ps, s) do
    case PrologEx.unmark_top(Store.walk(ps, s)) do
      {:var, _} -> false
      {:struct, "/", [free, pl]} -> free?(free, s) and proper?(pl, s)
      pl -> proper?(pl, s)
    end
  end

  defp proper?(l, s), do: match?({_, []}, PrologEx.Builtins.Lists.skip_list(l, s))
end
