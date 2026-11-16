defmodule PrologEx.Shell.Sigterm do
  @moduledoc false
  # Handler für :erl_signal_server (PrologEx.Shell.trap_sigterm/0):
  # SIGTERM setzt das Ctrl-C-Flag, das die Maschine an ihren Prüfpunkten
  # liest, und schickt dem Toplevel :prolog_interrupt (für ein Lesen, auf
  # das er gerade wartet)
  @behaviour :gen_event

  @impl true
  def init({{ref, owner}, _}), do: {:ok, {ref, owner}}

  @impl true
  def handle_event(:sigterm, {ref, owner} = st) do
    :atomics.put(ref, 1, 1)
    send(owner, :prolog_interrupt)
    {:ok, st}
  end

  def handle_event(_, st), do: {:ok, st}

  @impl true
  def handle_call(_, st), do: {:ok, :ok, st}
end
