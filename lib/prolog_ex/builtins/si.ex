defmodule PrologEx.Builtins.Si do
  @moduledoc """
  `library(si)` – "sufficiently instantiated" (Neumerkel, Scryer): sichere
  Typtests und Vergleiche. Statt bei zu wenig gebundenen Argumenten zu
  scheitern (wie `atom/1`), werfen sie einen Instanziierungsfehler. Sie

    * gelingen, wenn die Aussage für jede weitere Bindung gilt,
    * scheitern, wenn sie für keine gilt,
    * werfen sonst `instantiation_error`.

  Typtests (wie die Urfassung und Scryer):

    * `atom_si/1`, `integer_si/1`, `atomic_si/1`: Variable → Fehler.
    * `list_si/1`: Liste → ja (Elemente egal), Teilliste `[a|_]` → Fehler,
      sonst nein (`[a|b]`, `foo`).
    * `character_si/1`: Ein-Zeichen-Atom.
    * `chars_si/1`: wie `list_si/1`, dann die Elemente der Reihe nach wie
      `character_si/1` (die erste Variable vor einem Nicht-Zeichen gibt den
      Fehler: `chars_si([_, ab])` wirft, `chars_si([ab, _])` scheitert).

  Vergleiche:

    * `dif_si(X, Y)`: gelingt, wenn X und Y nie unifizierbar sind
      (`f(_, a)`, `f(_, b)`), scheitert bei X == Y, sonst Fehler – wie
      Neumerkels `X \\== Y, (X \\= Y -> true ; throw(...))`.
    * `compare_si(O, A, B)`: wie `compare/3`, aber nur, wenn die Ordnung
      unter jeder weiteren Bindung dieselbe bliebe (`f(a, X)` @< `f(b, Y)`;
      `f(X, a)` gegen `f(Y, b)` → Fehler). Siehe `PrologEx.Order.compare_si/3`.
      O wird wie bei `compare/3` geprüft.
    * `sort_si/2`, `msort_si/2`, `keysort_si/2`: wie `sort/2`, `msort/2`,
      `keysort/2`, aber nur, wenn das Ergebnis für jede weitere Bindung
      dasselbe wäre: jedes benachbarte Paar des Ergebnisses (bei keysort
      die Schlüssel) muss mit `compare_si` entschieden sein – dann ist es,
      wegen der Transitivität, die ganze Reihenfolge. `sort_si([X, a], L)`
      und `sort_si([X, Y], L)` werfen, `sort_si([X, X], L)` gibt `[X]`.
      Fehler sonst wie bei `sort/2` (Teilliste: instantiation_error,
      keine Liste: type_error(list, …)).

  Steuerung:

    * `when_si(Bedingung, Ziel)`: wie `when/2`, aber ohne zu warten – ist
      die Bedingung schon wahr, läuft Ziel sofort, sonst
      `instantiation_error`. Bedingungen wie bei `when/2` (`nonvar/1`,
      `ground/1`, `?=/2`, `,`, `;`; sonst domain_error(when_condition, …)).
      Da eine wahre Bedingung bei jeder weiteren Bindung wahr bleibt, gibt
      when_si/2 nie eine Antwort, die when/2 nicht auch gäbe. Die Tests
      oben lassen sich so ausdrücken: `atom_si(X) :- when_si(nonvar(X),
      atom(X))`, `dif_si(X, Y) :- when_si(?=(X, Y), X \\== Y)`.

  Grundterme und Negation:

    * `term_si(T)`: T ground → ja, sonst `instantiation_error`.
    * `not_si(G)`: wie `\\+ G`, aber nur für ground G (sonst
      `instantiation_error`) – erst dann ist das Ergebnis logisch
      (unabhängig von weiteren Bindungen). Wie Scryer: „True if Goal is
      not provable. Instantiation error if Goal is not ground.“
  """
  use PrologEx.Builtin, module: "si"
  alias PrologEx.{Error, Order}
  alias PrologEx.Builtins.Lists

  # --- Typtests ----------------------------------------------------------------

  defbuiltin "atom_si", [x] do
    case deref(x) do
      {:var, _} -> Error.instantiation!()
      {:atom, _} -> :ok
      [] -> :ok
      _ -> :fail
    end
  end

  defbuiltin "integer_si", [x] do
    case deref(x) do
      {:var, _} -> Error.instantiation!()
      n -> is_integer(n)
    end
  end

  defbuiltin "atomic_si", [x] do
    case deref(x) do
      {:var, _} -> Error.instantiation!()
      t -> atomic?(t)
    end
  end

  defbuiltin "list_si", [l] do
    list_si(l, subst())
  end

  defbuiltin "character_si", [c] do
    character_si(deref(c))
  end

  defbuiltin "chars_si", [l] do
    s = subst()

    with :ok <- list_si(l, s) do
      l |> Lists.items(s) |> chars_si(s)
    end
  end

  # --- Vergleiche ----------------------------------------------------------------

  defbuiltin "dif_si", [x, y] do
    s = subst()

    cond do
      Order.compare(x, y, s) == :eq ->
        :fail

      PrologEx.unify(x, y, s) == :error ->
        :ok

      true ->
        Error.instantiation!()
    end
  end

  defbuiltin "compare_si", [order, x, y] do
    case deref(order) do
      {:var, _} -> :ok
      {:atom, o} when o in ["<", "=", ">"] -> :ok
      {:atom, _} = o -> Error.domain!("order", o)
      [] -> Error.domain!("order", [])
      other -> Error.type!("atom", resolve(other))
    end

    case Order.compare_si(x, y, subst()) do
      :undecided -> Error.instantiation!()
      r -> {:unify, [{order, a(symbol(r))}]}
    end
  end

  defbuiltin "sort_si", [l, sorted] do
    s = subst()
    items = proper_list!(l, s)
    check_partial_list!(sorted, s)
    result = Order.sort_unique(items, s)
    decided!(result, s, [:lt])
    {:unify, [{sorted, list(result)}]}
  end

  defbuiltin "msort_si", [l, sorted] do
    s = subst()
    items = proper_list!(l, s)
    check_partial_list!(sorted, s)
    result = Order.sort(items, s)
    decided!(result, s, [:lt, :eq])
    {:unify, [{sorted, list(result)}]}
  end

  defbuiltin "keysort_si", [l, sorted] do
    s = subst()
    items = proper_list!(l, s)
    check_partial_list!(sorted, s)

    keyed =
      Enum.map(items, fn item ->
        case PrologEx.unmark_top(PrologEx.walk(item, s)) do
          {:struct, "-", [k, _v]} -> {k, item}
          {:var, _} -> Error.instantiation!()
          other -> Error.type!("pair", PrologEx.resolve(other, s))
        end
      end)

    result = Order.keysort(keyed, s)

    keys =
      Enum.map(result, fn item ->
        {:struct, "-", [k, _]} = PrologEx.unmark_top(PrologEx.walk(item, s))
        k
      end)

    decided!(keys, s, [:lt, :eq])
    {:unify, [{sorted, list(result)}]}
  end

  def meta, do: [{"si", "not_si", [0]}]

  defbuiltin "term_si", [x] do
    if PrologEx.Builtins.Order.variables(x, subst()) == [], do: :ok, else: Error.instantiation!()
  end

  defbuiltin "not_si", [g] do
    # g kommt als M:G (meta_predicate 0); M:G ist ground genau dann, wenn G es ist
    if PrologEx.Builtins.Order.variables(g, subst()) == [],
      do: {:call, mk("\\+", [g])},
      else: Error.instantiation!()
  end

  # --- Steuerung ----------------------------------------------------------------

  defbuiltin "when_si", [c, g] do
    s = subst()
    goal = PrologEx.Builtins.Coroutining.qualify(g, context_module(), s)

    case PrologEx.Builtins.Coroutining.condition(c, s) do
      true -> {:call, goal}
      {:wait, _} -> Error.instantiation!()
    end
  end

  # ---------------------------------------------------------------------

  defp list_si(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> :ok
      {_, {:var, _}} -> Error.instantiation!()
      _ -> :fail
    end
  end

  defp chars_si([], _s), do: :ok

  defp chars_si([c | rest], s) do
    case character_si(PrologEx.walk(c, s)) do
      :ok -> chars_si(rest, s)
      :fail -> :fail
    end
  end

  defp character_si({:var, _}), do: Error.instantiation!()

  defp character_si({:atom, name}),
    do: if(match?([_], String.to_charlist(name)), do: :ok, else: :fail)

  defp character_si(_), do: :fail

  defp atomic?({:atom, _}), do: true
  defp atomic?([]), do: true
  defp atomic?(n) when is_number(n), do: true
  defp atomic?(_), do: false

  defp symbol(:lt), do: "<"
  defp symbol(:eq), do: "="
  defp symbol(:gt), do: ">"

  # jedes benachbarte Paar mit compare_si entschieden (und erlaubt)?
  defp decided!([x, y | rest], s, allowed) do
    if Order.compare_si(x, y, s) in allowed,
      do: decided!([y | rest], s, allowed),
      else: Error.instantiation!()
  end

  defp decided!(_, _s, _allowed), do: :ok

  defp proper_list!(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> Lists.items(l, s)
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(l, s))
    end
  end

  defp check_partial_list!(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> :ok
      {_, {:var, _}} -> :ok
      _ -> Error.type!("list", PrologEx.resolve(l, s))
    end
  end
end
