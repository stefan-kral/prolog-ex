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
  Tupel selbst, bei einer Variablen `:var`) ein `:gb_trees` Nummer →
  Tupel; die Nummer gibt die Reihenfolge des Eintreffens. Ein Muster mit
  Hauptfunktor sucht nur in seinem Fach und in `:var`.
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

  defp insert(space, key, n, t) do
    Map.update(space, key, :gb_trees.insert(n, t, :gb_trees.empty()), &:gb_trees.insert(n, t, &1))
  end

  defp remove(space, key, n) do
    tree = :gb_trees.delete(n, Map.fetch!(space, key))
    if :gb_trees.is_empty(tree), do: Map.delete(space, key), else: Map.put(space, key, tree)
  end

  # das älteste Tupel, das zu einem der Muster passt: {fach, nummer, tupel}
  defp find(pats, space) do
    pats
    |> Enum.flat_map(fn p -> for k <- keys_for(p, space), do: {k, p} end)
    |> Enum.uniq()
    |> Enum.map(fn {k, p} -> first_in(k, p, space) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.min_by(fn {_, n, _} -> n end, fn -> nil end)
  end

  defp first_in(key, pat, space) do
    case Map.fetch(space, key) do
      {:ok, tree} -> first_match(:gb_trees.next(:gb_trees.iterator(tree)), key, pat)
      :error -> nil
    end
  end

  defp first_match(:none, _key, _pat), do: nil

  defp first_match({n, t, it}, key, pat) do
    if fits?(pat, t), do: {key, n, t}, else: first_match(:gb_trees.next(it), key, pat)
  end

  defp find_all(pat, space) do
    for k <- keys_for(pat, space),
        {n, t} <- :gb_trees.to_list(Map.fetch!(space, k)),
        fits?(pat, t) do
      {k, n, t}
    end
    |> Enum.sort_by(fn {_, n, _} -> n end)
  end

  # die Fächer, in denen ein Muster Treffer haben kann
  defp keys_for(pat, space) do
    case key(pat) do
      :var -> Map.keys(space)
      k -> Enum.filter([k, :var], &Map.has_key?(space, &1))
    end
  end

  defp fits?(pat, t), do: PrologEx.unify_status(pat, t, %{}) != :no

  @doc false
  def key(t) do
    case PrologEx.unmark_top(t) do
      {:var, _} -> :var
      {:struct, f, args} -> {f, length(args)}
      [_ | _] -> {".", 2}
      other -> {:atomic, other}
    end
  end

  # mit Variablen dieses Knotens
  defp import_term(t), do: elem(PrologEx.copy_mapped(t, %{}), 0)

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
