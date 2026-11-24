# langsame Tests (Minuten): mix test --include slow
ExUnit.start(exclude: [:slow])

# keine Meldungen beim Laden (Flag verbose_load, Vorgabe full), außer ein
# Test setzt das Flag
Application.put_env(:prolog_ex, :verbose_load, :silent)

# gprolog-Orakel für Aufzeichnungen (GPROLOG_RECORD=1), siehe tools/gprolog
Code.require_file("../tools/gprolog/gprolog.ex", __DIR__)

defmodule PrologEx.TestLibs do
  @moduledoc false
  # wie :- use_module(library(lists)), use_module(library(apply)) in user
  def libs(db), do: db |> PrologEx.use_library("lists") |> PrologEx.use_library("apply")
end

defmodule PrologEx.TableCase do
  @moduledoc false
  # Tabellengetriebene Tests (Neumerkels ISO-Seiten): eine Zeile ist
  # {Anfrage, Erwartung}. Erwartungen:
  #   :fails | :true | :succeeds (genau eine Antwort, Bindungen egal)
  #   ["X = 1", ...]          genau diese Antworten
  #   {:first, [...]}         die ersten Antworten (unendlich viele)
  #   {:error, "präfix"}      Fehler, error(E, _): E beginnt so
  #   {:out, "text"}          genau eine Antwort mit dieser Ausgabe
  #   {:out_re, "regex"}      ebenso, die Ausgabe passt zum Muster
  #   {:out, "text", e}       Ausgabe und Erwartung e
  #   {:out_re, "regex", e}   ebenso mit Muster
  #   {:any, [e1, e2, ...]}   die Tabelle lässt mehrere Antworten zu
  import ExUnit.CaptureIO
  alias PrologEx.Reader

  def db(reader, libs) do
    text = Enum.map_join(libs, "\n", &":- use_module(library(#{&1})).")
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(reader, text))
    db
  end

  # Antworten mit double_quotes=codes (Listen bleiben Listen, wie in den
  # Tabellen); das Flag gilt nur im Testprozess
  def run(reader, db, query) do
    PrologEx.Flags.set("double_quotes", {:atom, "codes"})
    [{:term, g, _}] = Reader.read_terms(reader, query <> ".")
    names = PrologEx.query_var_names(g)
    me = self()

    out =
      capture_io(fn ->
        r =
          try do
            {:answers,
             db
             |> PrologEx.query(g)
             |> Enum.take(5)
             |> Enum.map(&PrologEx.format_answer(&1, names))}
          rescue
            e in PrologEx.Error ->
              ball =
                case PrologEx.unmark(e.term) do
                  {:struct, "error", [formal, _]} -> formal
                  other -> other
                end

              {:error, PrologEx.Writer.format(ball, quoted: true)}
          end

        send(me, {:result, r})
      end)

    receive do
      {:result, r} -> {out, r}
    end
  end

  def matches?(expect, {out, r} = actual) do
    case {expect, r} do
      {{:any, alts}, _} -> Enum.any?(alts, &matches?(&1, actual))
      {{:out_re, re}, _} -> out =~ Regex.compile!(re) and matches?(:succeeds, actual)
      {{:out_re, re, e}, _} -> out =~ Regex.compile!(re) and matches?(e, actual)
      {{:out, text}, _} -> out == text and matches?(:succeeds, actual)
      {{:out, text, e}, _} -> out == text and matches?(e, actual)
      {:fails, {:answers, as}} -> as == []
      {true, {:answers, as}} -> as == ["true"]
      {:succeeds, {:answers, as}} -> length(as) == 1
      {{:first, l}, {:answers, as}} -> List.starts_with?(as, l)
      {l, {:answers, as}} when is_list(l) -> as == l
      {{:error, prefix}, {:error, msg}} -> String.starts_with?(msg, prefix)
      _ -> false
    end
  end
end

defmodule PrologEx.TestEnv do
  @moduledoc """
  Einstellungen für Belastungsläufe (bench/stress/run.sh) über
  Umgebungsvariablen – ohne sie ändert sich nichts.

  `CONC_JIT`: `on` (Vorgabe), `off` (jit aus), `eager` (Prädikate gleich
  beim ersten Aufruf übersetzt), `clause` (dazu Klauseln als BEAM-Code,
  im Hintergrund übersetzt, nach 1 Aufruf), `clause_sync` (dasselbe, beim
  Aufruf). Die Flags gelten je Prozess und gehen an die Kinder von
  library(concurrent) weiter; clause_jit wird beim Laden gelesen – darum
  auch im Prozess, der die Bibliotheken lädt (setup_all).
  """

  def apply_jit do
    set = fn k, v -> PrologEx.Flags.set(k, v) end

    case System.get_env("CONC_JIT", "on") do
      "on" ->
        :ok

      "off" ->
        set.("jit", {:atom, "false"})

      "eager" ->
        set.("jit_threshold", 1)

      "clause" ->
        set.("jit_threshold", 1)
        set.("clause_jit", {:atom, "true"})
        set.("clause_jit_threshold", 1)

      "clause_sync" ->
        set.("jit_threshold", 1)
        set.("clause_jit", {:atom, "sync"})
        set.("clause_jit_threshold", 1)

      other ->
        raise ArgumentError, "CONC_JIT: on, off, eager, clause, clause_sync – nicht #{other}"
    end
  end
end
