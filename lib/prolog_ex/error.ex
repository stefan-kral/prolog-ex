defmodule PrologEx.Error do
  @moduledoc """
  Prolog-Ausnahme: `throw/1` und alle Fehler der Builtins.

  `term` ist der geworfene Ball, bei Fehlern wie in ISO
  `error(Formal, Kontext)`, z. B. `error(type_error(list, foo), _)`.

  Builtins werfen Fehler über die Hilfsfunktionen hier, z. B.

      PrologEx.Error.type!("list", culprit)
      PrologEx.Error.instantiation!()

  Variablen im Ball dürfen noch gebunden sein: die Maschine löst ihn beim
  Werfen unter der aktuellen Substitution auf und kopiert ihn (wie ISO).
  `catch/3` fängt ihn; ohne passendes catch kommt er beim Aufrufer als
  diese Elixir-Ausnahme an.
  """
  defexception [:term]

  # keine Importe aus PrologEx: das wäre eine Übersetzungszeit-Abhängigkeit
  # in beide Richtungen
  defp a(n), do: PrologEx.a(n)
  defp mk(f, args), do: PrologEx.mk(f, args)

  @impl true
  def message(%__MODULE__{term: t}) do
    case t do
      {tag, "error", [formal, _ctx]} when tag in [:struct, :gstruct] -> show(formal)
      other -> "unbehandelte Ausnahme: " <> show(other)
    end
  end

  # wie writeq, mit Leerzeichen nach Kommas (wie die Antworten)
  defp show(t),
    do: PrologEx.Writer.format(PrologEx.unmark(t), quoted: true, spacing: :next_argument)

  @doc "Ball werfen (ohne error/2-Hülle)"
  def throw!(ball), do: raise(%__MODULE__{term: ball})

  @doc "`error(Formal, _)` werfen"
  def error!(formal), do: throw!(mk("error", [formal, fresh()]))

  def instantiation!, do: error!(a("instantiation_error"))
  def uninstantiation!(culprit), do: error!(mk("uninstantiation_error", [culprit]))
  def type!(type, culprit), do: error!(mk("type_error", [atom(type), culprit]))
  def domain!(domain, culprit), do: error!(mk("domain_error", [atom(domain), culprit]))

  def existence!(kind, what), do: error!(mk("existence_error", [atom(kind), what]))

  def permission!(action, type, culprit),
    do: error!(mk("permission_error", [atom(action), atom(type), culprit]))

  def representation!(what), do: error!(mk("representation_error", [atom(what)]))
  def evaluation!(what), do: error!(mk("evaluation_error", [atom(what)]))
  def resource!(what), do: error!(mk("resource_error", [atom(what)]))
  def syntax!(what), do: error!(mk("syntax_error", [atom(what)]))

  @doc "Prädikatsindikator Name/Stelligkeit als Term"
  def indicator({name, arity}), do: indicator(name, arity)
  def indicator(name, arity), do: mk("/", [a(name), arity])

  @doc "Formaler Fehlerterm eines Balls `error(F, _)` (sonst nil)"
  def formal(%__MODULE__{term: {tag, "error", [f, _]}}) when tag in [:struct, :gstruct], do: f
  def formal(_), do: nil

  defp atom(name) when is_binary(name), do: a(name)
  defp atom(t), do: t

  defp fresh, do: {:var, "_E#{System.unique_integer([:positive])}"}
end
