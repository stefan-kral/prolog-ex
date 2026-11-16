defmodule PrologEx.Shell.Sigterm do
  @moduledoc false
  # Handler für :erl_signal_server (PrologEx.Shell.trap_sigterm/0):
  # SIGTERM setzt das Ctrl-C-Flag, das die Maschine an ihren Prüfpunkten
  # liest
  @behaviour :gen_event

  @impl true
  def init({ref, _}), do: {:ok, ref}
  def init(ref), do: {:ok, ref}

  @impl true
  def handle_event(:sigterm, ref) do
    :atomics.put(ref, 1, 1)
    {:ok, ref}
  end

  def handle_event(_, ref), do: {:ok, ref}

  @impl true
  def handle_call(_, ref), do: {:ok, :ok, ref}
end
