defmodule PrologEx.Linda.Server do
  @moduledoc """
  Der Tupelraum von `library(linda)`: ein Prozess je Knoten, lokal unter
  `#{inspect(:prolog_ex_linda)}` registriert; Clients auf anderen Knoten
  (Erlang-Distribution) erreichen ihn als `{name, knoten}`.

  ## Protokoll

  Ein Client schickt `{:linda, pid, ref, anfrage}` (ref wählt er selbst)
  und bekommt `{:linda_reply, ref, antwort}`. Wer blockierend wartet
  (`in/1`, `rd/1`), bekommt die Antwort, sobald ein passendes Tupel kommt.

  Ein Tupel, das `in` herausnimmt, ist erst vorgemerkt: Der Client
  bestätigt es (`{:ack, ref}`), sobald er es hat, oder sagt ab
  (`{:cancel, ref}`, etwa nach Ctrl-C oder Zeitablauf). Bei Absage – oder
  wenn der Client-Prozess endet – kommt das Tupel an seine alte Stelle
  zurück. So geht kein Tupel verloren, wenn ein Client mitten im Warten
  abbricht. Nachrichten eines Prozesses an einen anderen kommen in der
  Reihenfolge an, in der sie geschickt wurden: Eine Absage nach der
  Anfrage findet sie also schon erledigt oder vorgemerkt vor.

  Anfragen:

    * `:hello` / `:bye` – Client an- bzw. abmelden (überwacht)
    * `{:out, t}` – `:ok`
    * `{:in, muster, block}` / `{:rd, muster, block}` – muster ist eine
      Liste; das älteste Tupel, das zu einem passt: `{:ok, tupel}`; sonst
      `:none` (block false) bzw. warten
    * `{:all, muster, entfernen}` – alle passenden Tupel (älteste zuerst)
    * `:shutdown` – keine neuen Clients mehr; ist der letzte abgemeldet,
      endet der Server

  Terme kommen als Kopien mit frischen Variablen an (`PrologEx.copy_fresh/2`
  beim Client) und werden hier noch einmal mit Variablen dieses Knotens
  versehen – die Kennungen verschiedener Knoten können sich sonst
  überschneiden. Passen heißt unifizierbar (ohne Bindungen zu behalten).

  Ablage: je Hauptfunktor (Name/Stelligkeit, bei atomaren Tupeln das
  Tupel selbst) ein `:gb_trees` Nummer → Tupel, dazu je Schlüssel des
  ersten Arguments (ebenso; `:var` für eine Variable dort) noch einer; die
  Nummer gibt die Reihenfolge des Eintreffens. Ein Muster mit festem
  ersten Argument sucht nur in dessen Fach und in dem mit Variable dort –
  `in(f(17))` unter 100 000 Tupeln `f(I)` kostet so O(log n) statt O(n).
  """
  use GenServer

  @name :prolog_ex_linda

  def name, do: @name

  @doc "Server auf diesem Knoten starten (nicht verbunden mit dem Aufrufer)"
  def start do
    GenServer.start(__MODULE__, nil, name: @name)
  end

  @impl true
  def init(_) do
    {:ok,
     %{
       # Fach => :gb_trees (Nummer => Tupel)
       space: %{},
       seq: 0,
       # wartende Anfragen in Ankunftsreihenfolge: {ref, pid, art, muster}
       waiters: [],
       # vorgemerkt: ref => {pid, [{fach, nummer, tupel}]}
       reserved: %{},
       # angemeldete Clients: pid => monitor
       clients: %{},
       shutdown: false
     }}
  end

  @impl true
  def handle_info({:linda, pid, ref, req}, st), do: request(req, pid, ref, st)

  def handle_info({:ack, ref}, st), do: {:noreply, %{st | reserved: Map.delete(st.reserved, ref)}}

  def handle_info({:cancel, ref}, st) do
    st = %{st | waiters: drop_waiter(st.waiters, ref)}

    case Map.pop(st.reserved, ref) do
      {nil, _} -> {:noreply, st}
      {{_pid, items}, reserved} -> {:noreply, put_back(items, %{st | reserved: reserved})}
    end
  end

  def handle_info({:DOWN, _mon, :process, pid, _}, st), do: maybe_stop(forget(pid, st))
  def handle_info(_, st), do: {:noreply, st}

  # --- Anfragen ---------------------------------------------------------------

  defp request(:hello, pid, ref, st) do
    cond do
      st.shutdown ->
        reply(pid, ref, {:error, :shutdown})
        {:noreply, st}

      Map.has_key?(st.clients, pid) ->
        reply(pid, ref, :ok)
        {:noreply, st}

      true ->
        reply(pid, ref, :ok)
        {:noreply, %{st | clients: Map.put(st.clients, pid, Process.monitor(pid))}}
    end
  end

  defp request(:bye, pid, ref, st) do
    case Map.pop(st.clients, pid) do
      {nil, _} -> :ok
      {mon, _} -> Process.demonitor(mon, [:flush])
    end

    st = forget(pid, st)
    reply(pid, ref, :ok)
    maybe_stop(st)
  end

  defp request(:shutdown, pid, ref, st) do
    reply(pid, ref, :ok)
    maybe_stop(%{st | shutdown: true})
  end

  defp request({:out, t}, pid, ref, st) do
    t = import_term(t)
    n = st.seq + 1
    st = deliver(key(t), n, t, %{st | seq: n})
    reply(pid, ref, :ok)
    {:noreply, st}
  end

  defp request({op, pats, block}, pid, ref, st) when op in [:in, :rd] do
    pats = Enum.map(pats, &import_term/1)

    case find(pats, st.space) do
      {key, n, t} when op == :in ->
        reply(pid, ref, {:ok, t})
        space = remove(st.space, key, n)

        {:noreply,
         %{st | space: space, reserved: Map.put(st.reserved, ref, {pid, [{key, n, t}]})}}

      {_key, _n, t} ->
        reply(pid, ref, {:ok, t})
        {:noreply, st}

      nil when block ->
        {:noreply, %{st | waiters: st.waiters ++ [{ref, pid, op, pats}]}}

      nil ->
        reply(pid, ref, :none)
        {:noreply, st}
    end
  end

  defp request({:all, pat, take}, pid, ref, st) do
    pat = import_term(pat)
    hits = find_all(pat, st.space)
    reply(pid, ref, {:ok, for({_, _, t} <- hits, do: t)})

    # entfernte sind vorgemerkt wie bei in
    if take and hits != [] do
      space = Enum.reduce(hits, st.space, fn {k, n, _}, sp -> remove(sp, k, n) end)
      {:noreply, %{st | space: space, reserved: Map.put(st.reserved, ref, {pid, hits})}}
    else
      {:noreply, st}
    end
  end

  defp reply(pid, ref, answer), do: send(pid, {:linda_reply, ref, answer})

  # --- Tupel ablegen und verteilen --------------------------------------------

  # ein neues (oder zurückgegebenes) Tupel: erst bekommt es jedes wartende
  # rd, zu dem es passt (es war ja da – auch wer nach einem wartenden in
  # kam), dann nimmt es das erste passende in (es bleibt vorgemerkt);
  # sonst in den Raum
  defp deliver(key, n, t, st) do
    {rds, rest} =
      Enum.split_with(st.waiters, fn {_, _, op, pats} -> op == :rd and fits_any?(pats, t) end)

    for {ref, pid, _, _} <- rds, do: reply(pid, ref, {:ok, t})
    take_in(rest, [], key, n, t, st)
  end

  defp take_in([], kept, key, n, t, st),
    do: %{st | waiters: Enum.reverse(kept), space: insert(st.space, key, n, t)}

  defp take_in([{ref, pid, op, pats} = w | ws], kept, key, n, t, st) do
    if op == :in and fits_any?(pats, t) do
      reply(pid, ref, {:ok, t})

      %{
        st
        | waiters: Enum.reverse(kept, ws),
          reserved: Map.put(st.reserved, ref, {pid, [{key, n, t}]})
      }
    else
      take_in(ws, [w | kept], key, n, t, st)
    end
  end

  defp fits_any?(pats, t), do: Enum.any?(pats, &fits?(&1, t))

  # vorgemerkte Tupel zurück an ihre Stelle (und an Wartende)
  defp put_back(items, st),
    do: Enum.reduce(items, st, fn {k, n, t}, st -> deliver(k, n, t, st) end)

  # Ablage: Hauptschlüssel => {alle, nach_erstem}; alle: :gb_trees Nummer
  # => Tupel; nach_erstem: Schlüssel des ersten Arguments => :gb_trees (ein
  # Tupel steht in beiden). Ein Muster mit festem erstem Argument sucht nur
  # in dessen Fach und in dem der Tupel mit Variable dort.
  defp insert(space, {fk, a1}, n, t) do
    {all, by1} = Map.get(space, fk, {:gb_trees.empty(), %{}})
    all = :gb_trees.insert(n, t, all)

    by1 =
      if a1 == nil,
        do: by1,
        else: Map.put(by1, a1, :gb_trees.insert(n, t, Map.get(by1, a1, :gb_trees.empty())))

    Map.put(space, fk, {all, by1})
  end

  defp remove(space, {fk, a1}, n) do
    {all, by1} = Map.fetch!(space, fk)
    all = :gb_trees.delete(n, all)

    by1 =
      if a1 == nil do
        by1
      else
        tree = :gb_trees.delete(n, Map.fetch!(by1, a1))
        if :gb_trees.is_empty(tree), do: Map.delete(by1, a1), else: Map.put(by1, a1, tree)
      end

    if :gb_trees.is_empty(all), do: Map.delete(space, fk), else: Map.put(space, fk, {all, by1})
  end

  # das älteste Tupel, das zu einem der Muster passt: {schlüssel, nummer, tupel}
  defp find(pats, space) do
    pats
    |> Enum.flat_map(fn p -> for tree <- trees_for(p, space), do: {tree, p} end)
    |> Enum.map(fn {tree, p} -> first_match(:gb_trees.next(:gb_trees.iterator(tree)), p) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.min_by(fn {_, n, _} -> n end, fn -> nil end)
  end

  defp first_match(:none, _pat), do: nil

  defp first_match({n, t, it}, pat) do
    if fits?(pat, t), do: {key(t), n, t}, else: first_match(:gb_trees.next(it), pat)
  end

  defp find_all(pat, space) do
    for tree <- trees_for(pat, space),
        {n, t} <- :gb_trees.to_list(tree),
        fits?(pat, t) do
      {key(t), n, t}
    end
    |> Enum.sort_by(fn {_, n, _} -> n end)
  end

  # die Bäume, in denen ein Muster Treffer haben kann (jedes Tupel in
  # höchstens einem davon)
  defp trees_for(pat, space) do
    vars = for {all, _} <- [Map.get(space, :var)], all != nil, do: all

    case key(pat) do
      {:var, _} ->
        for {_, {all, _}} <- space, do: all

      {fk, a1} when a1 in [nil, :var] ->
        for({all, _} <- [Map.get(space, fk)], all != nil, do: all) ++ vars

      {fk, a1} ->
        case Map.get(space, fk) do
          nil -> vars
          {_, by1} -> Enum.reject([Map.get(by1, a1), Map.get(by1, :var)], &is_nil/1) ++ vars
        end
    end
  end

  defp fits?(pat, t), do: PrologEx.unify_status(pat, t, %{}) != :no

  @doc false
  # {Hauptschlüssel, Schlüssel des ersten Arguments oder nil}
  def key(t) do
    case PrologEx.unmark_top(t) do
      {:var, _} -> {:var, nil}
      {:struct, f, [a | _] = args} -> {{f, length(args)}, arg_key(a)}
      [h | _] -> {{".", 2}, arg_key(h)}
      other -> {{:atomic, other}, nil}
    end
  end

  defp arg_key(a) do
    case PrologEx.unmark_top(a) do
      {:var, _} -> :var
      {:struct, f, args} -> {f, length(args)}
      [_ | _] -> {".", 2}
      other -> {:atomic, other}
    end
  end

  # mit Variablen dieses Knotens
  defp import_term(t), do: elem(PrologEx.copy_mapped(t, %{}), 0)

  # --- Prüfen (Tests) ---------------------------------------------------------

  @doc false
  # Verletzte Invarianten des Zustands (Liste von Texten, leer: in Ordnung):
  # jedes Tupel steht unter seinem Hauptschlüssel in alle und, hat es ein
  # erstes Argument, genau unter dessen Schlüssel in nach_erstem – und
  # nirgends sonst; keine leeren Bäume; Nummern eindeutig, höchstens seq,
  # nicht zugleich vorgemerkt; kein Wartender, den ein Tupel im Raum schon
  # bedienen könnte
  def invariants(st) do
    in_space =
      for {fk, {all, by1}} <- st.space, {n, t} <- :gb_trees.to_list(all) do
        {fk, by1, n, t}
      end

    by1_entries =
      for {_fk, {_all, by1}} <- st.space,
          {a1, tree} <- by1,
          {n, _} <- :gb_trees.to_list(tree),
          do: {a1, n}

    reserved = for {_, {_, items}} <- st.reserved, {_, n, _} <- items, do: n
    nums = for {_, _, n, _} <- in_space, do: n

    [
      for {fk, {all, by1}} <- st.space,
          :gb_trees.is_empty(all) or Enum.any?(by1, fn {_, t} -> :gb_trees.is_empty(t) end) do
        "leerer Baum unter #{inspect(fk)}"
      end,
      for {fk, _by1, n, t} <- in_space, {k, _a1} = key(t), k != fk do
        "Tupel #{n} unter #{inspect(fk)} statt #{inspect(k)}"
      end,
      for {fk, by1, n, t} <- in_space,
          {^fk, a1} = key(t),
          a1 != nil,
          not (Map.has_key?(by1, a1) and :gb_trees.is_defined(n, Map.fetch!(by1, a1))) do
        "Tupel #{n} fehlt unter erstem Argument #{inspect(a1)}"
      end,
      if(
        length(by1_entries) != Enum.count(in_space, fn {_, _, _, t} -> elem(key(t), 1) != nil end),
        do: ["nach_erstem hat Einträge, die nicht in alle stehen"],
        else: []
      ),
      if(length(Enum.uniq(nums)) != length(nums), do: ["Nummern doppelt"], else: []),
      for n <- nums ++ reserved, n > st.seq do
        "Nummer #{n} > seq #{st.seq}"
      end,
      for n <- reserved, n in nums do
        "Nummer #{n} vorgemerkt und im Raum"
      end,
      for {ref, _pid, op, pats} <- st.waiters, find(pats, st.space) != nil do
        "Wartender #{op} #{inspect(ref)} könnte bedient werden"
      end
    ]
    |> List.flatten()
  end

  # --- Clients ----------------------------------------------------------------

  # ein Client ist weg: seine Wartenden streichen, seine Vormerkungen
  # zurückgeben
  defp forget(pid, st) do
    st = %{
      st
      | clients: Map.delete(st.clients, pid),
        waiters: Enum.reject(st.waiters, &(elem(&1, 1) == pid))
    }

    {mine, others} = Enum.split_with(st.reserved, fn {_, {p, _}} -> p == pid end)
    items = mine |> Enum.flat_map(fn {_, {_, items}} -> items end) |> Enum.sort_by(&elem(&1, 1))
    put_back(items, %{st | reserved: Map.new(others)})
  end

  defp drop_waiter(ws, ref), do: Enum.reject(ws, &(elem(&1, 0) == ref))

  defp maybe_stop(%{shutdown: true, clients: c} = st) when map_size(c) == 0,
    do: {:stop, :normal, st}

  defp maybe_stop(st), do: {:noreply, st}
end
