defmodule PrologEx.Builtins.Trace do
  @moduledoc """
  Der Tracer, die Prädikate (system): `leash/1`, `visible/1`, `tracing/0`,
  `debugging/0`. `trace/0`, `notrace/0`, `nodebug/0`, `debug/0`, `spy/1`,
  `nospy/1` und `nospyall/0` führt die Maschine selbst aus (sie setzen den
  Prüfpunkt, siehe `PrologEx.Trace`).
  """
  use PrologEx.Builtin

  alias PrologEx.Trace

  defbuiltin "tracing", [] do
    if Trace.mode() == :trace, do: true, else: :fail
  end

  defbuiltin "debugging", [] do
    Trace.debugging()
    true
  end

  # leash(+Ports): an welchen Ports der Tracer fragt (an den anderen zeigt
  # er nur). Ports: ein Port (call, exit, redo, fail, exception), eine
  # Liste davon, all, none, full (= all), half (call, redo); +P und -P
  # nehmen einen dazu bzw. weg. leash(-L) mit Variable: die aktuellen.
  defbuiltin "leash", [ports] do
    case deref(ports) do
      {:var, _} ->
        {:unify, [{ports, port_list(Trace.leash())}]}

      spec ->
        Trace.put_leash(leash_spec(resolve(spec), Trace.leash()))
        true
    end
  end

  # visible(+Ports): welche Ports der Tracer überhaupt zeigt (wie leash/1)
  defbuiltin "visible", [ports] do
    case deref(ports) do
      {:var, _} ->
        {:unify, [{ports, port_list(Trace.visible())}]}

      spec ->
        Trace.put_visible(leash_spec(resolve(spec), Trace.visible()))
        true
    end
  end

  defp port_list(set),
    do: for(p <- Trace.ports(), MapSet.member?(set, p), do: a(Atom.to_string(p)))

  defp leash_spec({tag, "+", [p]}, cur) when tag in [:struct, :gstruct],
    do: MapSet.union(cur, MapSet.new(ports_of(p)))

  defp leash_spec({tag, "-", [p]}, cur) when tag in [:struct, :gstruct],
    do: MapSet.difference(cur, MapSet.new(ports_of(p)))

  defp leash_spec(p, _cur), do: MapSet.new(ports_of(p))

  defp ports_of(l) when is_list(l), do: Enum.flat_map(l, &ports_of/1)
  defp ports_of({:atom, "all"}), do: Trace.ports()
  defp ports_of({:atom, "full"}), do: Trace.ports()
  defp ports_of({:atom, "none"}), do: []
  defp ports_of({:atom, "off"}), do: []
  defp ports_of({:atom, "half"}), do: [:call, :redo]

  defp ports_of({:atom, p} = t) do
    case Enum.find(Trace.ports(), &(Atom.to_string(&1) == p)) do
      nil -> PrologEx.Error.domain!("leash_port", t)
      port -> [port]
    end
  end

  defp ports_of({:var, _}), do: PrologEx.Error.instantiation!()
  defp ports_of(t), do: PrologEx.Error.domain!("leash_port", t)
end
