defmodule PrologEx.Chaos do
  @moduledoc """
  Erzwungene Verzögerungen für Tests von `library(concurrent)`: an
  markierten Stellen (vor dem Senden einer Nachricht, vor einem Empfang,
  beim Beenden der Arbeiter) wartet ein Prozess zufällig – so kommen
  Nachrichten in Reihenfolgen an, die sonst nur selten vorkommen.

  `point(tag)` ist ein Makro: außerhalb von `MIX_ENV=test` wird daraus
  nichts (kein Aufruf, keine Kosten). In Tests kostet es einen Blick in
  `:persistent_term`, solange `enable/1` nicht gerufen wurde.

      PrologEx.Chaos.enable(seed: 7, p: 0.3, max_ms: 3)
      ... Läufe ...
      hits = PrologEx.Chaos.disable()   # %{tag => wie oft verzögert}

  Optionen: `p` Wahrscheinlichkeit je Stelle (Vorgabe 0.2), `max_ms`
  längste Verzögerung (Vorgabe 2; die Hälfte der Fälle nur
  `:erlang.yield/0`), `only` eine Liste von Tags (Vorgabe alle), `seed`
  Startwert (je Prozess abgeleitet; die Reihenfolge der Prozesse bleibt
  Sache des Schedulers, ein Lauf ist also nicht genau wiederholbar).
  """

  @enabled Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test
  @key {__MODULE__, :cfg}

  @tags [
    # im Arbeiter
    :w_start,
    :w_result,
    :w_offer,
    :w_part_recv,
    :w_part_done,
    :w_improve,
    :w_steal_node,
    # im Aufrufer
    :c_jobs,
    :c_stop,
    :c_part,
    :c_bound,
    :c_steal_req,
    :c_steal_cut,
    :c_loop,
    :c_kill
  ]

  @doc "die Tags aller Stellen"
  def tags, do: @tags

  @doc "Sind die Stellen in diesem Build vorhanden (MIX_ENV=test)?"
  def compiled?, do: @enabled

  defmacro point(tag) do
    if @enabled do
      unless tag in @tags, do: raise(ArgumentError, "unbekannte Stelle #{inspect(tag)}")
      quote(do: PrologEx.Chaos.hit(unquote(tag)))
    else
      :ok
    end
  end

  def enable(opts \\ []) do
    counters = :counters.new(length(@tags), [])
    index = @tags |> Enum.with_index(1) |> Map.new()
    only = Keyword.get(opts, :only, @tags)

    :persistent_term.put(@key, %{
      p: Keyword.get(opts, :p, 0.2),
      max_ms: Keyword.get(opts, :max_ms, 2),
      only: MapSet.new(only),
      seed: Keyword.get(opts, :seed, 1),
      counters: counters,
      index: index
    })

    :ok
  end

  def disable do
    case :persistent_term.get(@key, nil) do
      nil ->
        %{}

      cfg ->
        :persistent_term.erase(@key)
        for {t, i} <- cfg.index, (n = :counters.get(cfg.counters, i)) > 0, into: %{}, do: {t, n}
    end
  end

  @doc false
  def hit(tag) do
    case :persistent_term.get(@key, nil) do
      nil -> :ok
      cfg -> if MapSet.member?(cfg.only, tag), do: maybe_wait(cfg, tag), else: :ok
    end
  end

  defp maybe_wait(cfg, tag) do
    {x, st} = :rand.uniform_real_s(state(cfg))

    if x < cfg.p do
      :counters.add(cfg.counters, cfg.index[tag], 1)
      {y, st} = :rand.uniform_s(2 * cfg.max_ms, st)
      Process.put({__MODULE__, :rand}, st)

      if y <= cfg.max_ms do
        :erlang.yield()
      else
        receive do
        after
          y - cfg.max_ms -> :ok
        end
      end
    else
      Process.put({__MODULE__, :rand}, st)
    end

    :ok
  end

  # eigener Generator je Prozess (nicht der von :rand: Tests und Prolog
  # behalten ihre Folgen)
  defp state(cfg) do
    case Process.get({__MODULE__, :rand}) do
      {_, _} = st -> st
      _ -> :rand.seed_s(:exsss, {cfg.seed, :erlang.phash2(self()), 0x5EED})
    end
  end
end
