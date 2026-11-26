defmodule PrologEx.Jit do
  @moduledoc """
  Übersetzt deterministische Prädikate über Zahlen, Listen, Atome und
  Strukturen in BEAM-Code.
  Innerhalb des übersetzten Stücks liegen die Werte in Erlang-Variablen:
  keine Bindungen, kein Zielstapel, keine Kompaktierung. Gebunden wird nur
  an den Rändern: beim Aufruf die Eingaben lesen (Zahlen, echte Listen
  einmal aufgelöst, sonst Terme, die nur durchgereicht werden), am Ende
  die Ausgaben binden (frische Variablen). Passt ein Aufruf nicht dazu,
  nimmt ihn der Interpreter.

  Was übersetzt wird – jede Klausel:

    * Kopf: Zahlen, Atome, Variablen, `[]`, `[E1, ..., En | T]` und
      Strukturen `f(A1, ..., An)` (Elemente, Argumente, Rest wieder
      solche Terme)
    * Rumpf: `V is E`, arithmetische Vergleiche, `X = Y` (Terme wie im
      Kopf), `!`, `true`, `fail`, `( C -> T ; E )`, `( C -> T )`, `\\+ G`,
      Typtests, `==`, `\\==`, `@<`, `@>`, `@=<`, `@>=`, `compare/3`,
      `arg/3`, `functor/3` und `=../2` (diese drei nur zum Zerlegen),
      `(A ; B), !` (wie `(A -> true ; B -> true), !`, ohne Schnitt in A
      und B) und Aufrufe des Prädikats selbst oder anderer übersetzter
      (Argumente Terme wie im Kopf)
    * E aus Zahlen, Variablen, `pi`, `e`, `epsilon` und den auswertbaren
      Funktoren (außer random/random_float)

  Werte haben einen Typ: Zahl, Liste, Liste von Zahlen oder beliebig
  (nur durchgereicht – auch eine ungebundene Variable). Listen und
  Strukturen werden erst beim Zerlegen gelesen (Runtime.list/1, st/3); ein
  Argument einer Struktur, mit dem gerechnet wird, dort zur Zahl gemacht
  (Herkunft {:sub, ...}, je Funktor). Konstanten auf Werten, die nicht schon Zahlen
  sind, und zweimal vorkommende Variablen prüft der Code zur Laufzeit wie
  die Unifikation (Runtime.eqc/2, ueq/2): bände sie etwas, gibt er auf. Was ein Wert sein
  muss, ergibt sich aus dem Gebrauch (gerechnet: Zahl; zerlegt: Liste;
  verglichen: Zahl oder Liste von Zahlen) und wird für Eingaben beim
  Aufruf geprüft. Ausgabetypen dürfen von Eingaben abhängen: app/3 gibt
  eine Liste, wenn das zweite Argument eine ist.

  Kommen nur Ganzzahlen und ganzzahlige Operationen vor (+ - * // mod rem
  div min max >> << /\\ \\/ xor gcd, einstellig - + abs sign msb \\),
  rechnet der Code mit + - * direkt und nimmt nur ganzzahlige Zahlen;
  sonst rechnet er alles mit PrologEx.Arith (wie der Interpreter, auch
  rationale Zwischenwerte) und nimmt Ganzzahlen und Floats.

  Das Prädikat ist nachweislich deterministisch: je zwei Klauseln
  schließen sich aus – durch einen Schnitt in der früheren, verschiedene
  Muster im Kopf (Konstanten, `[]` gegen `[_|_]`; auch `X = c` am Anfang
  des Rumpfs), einen Vergleich am Anfang, der für die Konstante der
  anderen falsch ist, oder einander ausschließende Vergleiche am Anfang
  (`X > 0` / `X =< 0`). Vor dem ausschließenden Vergleich der späteren
  Klausel darf nichts einen Fehler werfen können (der Interpreter würde
  sie beim Zurücksetzen versuchen).

  Schließen sich die Klauseln nicht aus, wird ein Prädikat
  nichtdeterministisch übersetzt (Flag jit_nondet), wenn jeder Rumpf wie
  oben ist und höchstens als letztes Ziel ein nichtdeterministisches
  Prädikat ruft (Types.nd_irs!/3): Lösungen als Schritte samt Fortsetzung
  (Runtime.nd_tail/3), die der Interpreter als Choice Point hält. Wo nur die erste
  Lösung zählt (Schnitt gleich danach, letztes Ziel einer Bedingung, unter
  \\+), rufen auch deterministische Prädikate solche ({:call1, ...}).

  Die Modi (Eingabe/Ausgabe je Argument): steht eine Kopfvariable zuerst
  in einem Vergleich oder rechts in `is`, ist sie Eingabe, links in `is`
  Ausgabe, als Argument eines Aufrufs wie dort. Die übrigen Positionen
  werden durchprobiert: zuerst, wie die Aufrufstellen das Prädikat rufen
  (Hints.call_prefs/3), dann mehr Ausgaben zuerst, Ausgaben eher rechts.

  Gleich wie im Interpreter: Antworten, Fehler (dieselben
  Arithmetik-Funktionen), Inferenzen (jeder Aufruf und jedes eingebaute
  Ziel zählt eins; Schnitt, `,`, `;` und `->` nicht) und Grenzen
  (Inferenz-, Zeit-, Speichergrenzen an denselben Prüfpunkten, siehe
  Runtime.tick/0).

  Die Module heißen nach einem Hash ihres Inhalts: dasselbe Programm
  wieder geladen nimmt das vorhandene Modul.

  Aufbau: hier die Schnittstelle und der Ablauf (Komponenten, Modi); die
  Teile in PrologEx.Jit.Parse (Zerlegen in die Zwischenform), .Hints
  (Modi aus den Aufrufstellen und is-Deklarationen), .Types (Typen,
  Datenfluss, nichtdeterministische Prädikate), .Excl
  (Ausschließlichkeit), .Codegen (Elixir-AST, Module, Laden), .Runtime
  (was der erzeugte Code und der Interpreter zur Laufzeit rufen), .Util
  (gemeinsame Hilfen).
  """

  alias PrologEx.Jit.{Codegen, Excl, Hints, Parse, Types, Util}

  # höchstens so viele Positionen ohne Hinweis werden durchprobiert
  @max_enum 6
  @why_key :prolog_ex_jit_why

  # --- Schnittstelle ------------------------------------------------------

  @doc """
  Übersetzt die Prädikate eines Ladeschritts (eines Moduls), soweit sie
  passen. `preds`: [{{name, stelligkeit}, [{kopf, rumpf}]}]. `ext`: für ein
  schon geladenes, übersetztes, statisches Prädikat außerhalb des Schritts
  `%{mod: modul, p: funktion, sig: signatur}`, sonst nil. `dynamic`: die
  dynamischen unter `preds` – andere dürfen sie nicht rufen (nach einem
  assert wäre ihr Code falsch).

  Ergebnis: %{{name, stelligkeit} => {{modul, eintritt, p, gerufen, sig},
  eingaben, ausgaben}}: eingaben [{k, prüfung}] mit prüfung :int, :num,
  :list, :ilist (Ganzzahlen), :nlist (Zahlen) oder :any; ausgaben [k];
  gerufen: die anderen Prädikate, die der Code direkt ruft.

  `force`: Modi, die ein Prädikat haben muss, %{{name, stelligkeit} =>
  %{k => :in | :out}} (anders als decl kein Hinweis – passen sie nicht,
  wird es nicht übersetzt; für die Varianten, PrologEx.jit_variant/7).
  `nums`: Prädikate, die auch Floats sehen (nicht ganzzahlig übersetzt,
  wie ihr Teil des Aufrufgraphen; PrologEx.jit_renum/4).
  """
  def compile_batch(
        preds,
        ext \\ fn _ -> nil end,
        dynamic \\ MapSet.new(),
        decl \\ %{},
        force \\ %{},
        nums \\ MapSet.new()
      ) do
    case settle(preds, ext, dynamic, decl, force, nums) do
      %{solved: solved} when map_size(solved) == 0 -> %{}
      s -> Codegen.build(s, :load)
    end
  end

  @doc """
  Wie compile_batch/4, aber nur die Analyse: %{{name, stelligkeit} =>
  {:ok, signatur} | {:no, grund}} (für jit_listing).
  """
  def explain(preds, ext \\ fn _ -> nil end, dynamic \\ MapSet.new(), decl \\ %{}) do
    s = settle(preds, ext, dynamic, decl, %{}, MapSet.new())

    Map.new(preds, fn {k, _} ->
      case s.solved do
        %{^k => r} -> {k, {:ok, r.sig}}
        _ -> {k, {:no, Map.get(s.why, k, "?")}}
      end
    end)
  end

  @doc "Ein einzelnes Prädikat (Aufrufe nur von sich selbst), sonst :no"
  def compile(source) do
    with {:ok, key} <- key_of(source),
         %{^key => {mod, ins, outs}} <- compile_batch([{key, source}]) do
      {:ok, mod, ins, outs}
    else
      _ -> :no
    end
  end

  @doc false
  # der erzeugte Elixir-Code (zum Nachsehen); preds wie compile_batch/3
  def code(preds) do
    case settle(preds, fn _ -> nil end, MapSet.new(), %{}, %{}, MapSet.new()) do
      %{solved: solved} when map_size(solved) == 0 -> :no
      s -> Codegen.build(s, :show)
    end
  end

  defp key_of([{h, _} | _]) do
    case Util.plain(h) do
      {:struct, f, a} -> {:ok, {f, length(a)}}
      _ -> :no
    end
  end

  defp key_of(_), do: :no

  # --- Ablauf -------------------------------------------------------------
  #
  # Zerlegen; ganzzahlig oder nicht je zusammenhängendem Aufrufgraphen;
  # dann die stark zusammenhängenden Komponenten, Gerufene zuerst: Modi,
  # Typen, Fluss, Ausschließlichkeit. Was nicht passt, fällt heraus, und
  # mit ihm, wer es ruft.

  # decl: Modi aus is-Deklarationen (PrologEx.Builtins.IsDirectives.jit_modes/2),
  # %{{name, stelligkeit} => %{k => :in | :out}}: Hinweise vor denen der
  # Aufrufstellen (call_prefs/3)
  defp settle(preds, ext0, dynamic, decl, force, nums) do
    Process.put(@why_key, %{})

    try do
      force = for {k, ms} <- force, {i, m} <- ms, into: %{}, do: {{k, i}, m}
      settle_(preds, ext0, dynamic, decl, force, nums)
    after
      Process.delete(@why_key)
    end
  end

  defp settle_(preds, ext0, dynamic, decl, force, nums) do
    batch = MapSet.new(for {k, _} <- preds, do: k)
    ext = fn k -> if MapSet.member?(batch, k), do: nil, else: ext0.(k) end

    callable = fn k ->
      cond do
        MapSet.member?(dynamic, k) -> :dynamic
        MapSet.member?(batch, k) -> true
        true -> if (e = ext.(k)) == :builtin, do: :builtin, else: e != nil
      end
    end

    parsed =
      for {k, src} <- preds, p = Parse.parse(k, src, callable), p != nil, into: %{}, do: {k, p}

    pref = Hints.call_prefs(preds, parsed, decl)
    {parsed, num} = kinds(drop_orphans(parsed, ext), ext, nums)

    solved =
      parsed
      |> Util.sccs()
      |> Enum.reduce(%{}, fn scc, solved ->
        ready =
          Enum.all?(scc, fn k ->
            Enum.all?(parsed[k].deps, &(&1 in scc or Map.has_key?(solved, &1) or ext.(&1) != nil))
          end)

        if not ready do
          for k <- scc,
              d <- parsed[k].deps,
              not (d in scc or Map.has_key?(solved, d) or ext.(d) != nil),
              do: Util.why(k, "ruft #{Util.pi(d)}, das nicht übersetzt wird")
        end

        case ready && solve(scc, parsed, solved, ext, num, pref, force) do
          {:ok, res} -> Map.merge(solved, res)
          _ -> solved
        end
      end)

    %{parsed: parsed, solved: solved, ext: ext, why: Process.get(@why_key)}
  end

  # wer etwas ruft, das weder übersetzt wird noch schon übersetzt ist
  defp drop_orphans(parsed, ext) do
    bad =
      for {k, p} <- parsed,
          Enum.any?(p.deps, &(not Map.has_key?(parsed, &1) and ext.(&1) == nil)),
          do: k

    for k <- bad,
        d <- parsed[k].deps,
        not Map.has_key?(parsed, d) and ext.(d) == nil,
        do: Util.why(k, "ruft #{Util.pi(d)}, das nicht übersetzt wird")

    if bad == [], do: parsed, else: drop_orphans(Map.drop(parsed, bad), ext)
  end

  # Ganzzahlig oder nicht: über Aufrufe hinweg einheitlich (ein Ergebnis
  # kann ein Float sein, ein Argument auch) – je zusammenhängendem Teil
  # des Aufrufgraphen; ein ganzzahliges schon übersetztes Prädikat darf
  # von einem nicht ganzzahligen nicht gerufen werden
  defp kinds(parsed, ext, nums) do
    ext_num = fn d ->
      case ext.(d) do
        nil -> nil
        e -> e.sig.num
      end
    end

    seed =
      for {k, p} <- parsed,
          MapSet.member?(nums, k) or not Parse.int_only?(p.clauses) or
            Enum.any?(p.deps, &(ext_num.(&1) == true)),
          into: MapSet.new(),
          do: k

    edges = for {k, p} <- parsed, d <- p.deps, Map.has_key?(parsed, d), do: {k, d}
    num = spread(seed, edges)

    case for k <- num, d <- parsed[k].deps, ext_num.(d) == false, do: {k, d} do
      [] ->
        {parsed, num}

      bad ->
        for {k, d} <- bad,
            do: Util.why(k, "ruft #{Util.pi(d)}: übersetzt nur für Ganzzahlen, hier auch Floats")

        bad = Enum.map(bad, &elem(&1, 0))
        kinds(drop_orphans(Map.drop(parsed, bad), ext), ext, nums)
    end
  end

  defp spread(set, edges) do
    set2 =
      Enum.reduce(edges, set, fn {a, b}, acc ->
        cond do
          MapSet.member?(acc, a) -> MapSet.put(acc, b)
          MapSet.member?(acc, b) -> MapSet.put(acc, a)
          true -> acc
        end
      end)

    if MapSet.equal?(set2, set), do: set, else: spread(set2, edges)
  end

  # --- Eine Komponente lösen ----------------------------------------------
  #
  # Modi aus Hinweisen im Rumpf (erster Gebrauch einer Kopfvariablen); die
  # übrigen Positionen durchprobieren. Je Versuch Typen bis zum Fixpunkt,
  # dann die Ausschließlichkeit.

  defp solve(scc, parsed, solved, ext, num, pref, force) do
    if endless?(scc, parsed) do
      for k <- scc, do: Util.why(k, "jede Klausel ruft sich selbst, ohne zu scheitern: endlos")
      nil
    else
      solve_(scc, parsed, solved, ext, num, pref, force)
    end
  end

  # Kann keine Klausel zurückkehren – Kopf nur Variablen, Rumpf nur Aufrufe
  # im Zusammenhang (und Schnitte) –, macht der Erlang-Compiler den Aufruf
  # zum Endaufruf (er kehrt ja nie zurück): der Code liefe als flache
  # Schleife, wo der Interpreter an die Speichergrenze stößt
  # (p(X) :- p(X), p(X).)
  defp endless?(scc, parsed) do
    Enum.all?(scc, fn k ->
      Enum.all?(parsed[k].clauses, fn {head, gs} ->
        Enum.all?(head, &match?({:var, _}, &1)) and gs != [] and
          Enum.all?(gs, fn
            :cut -> true
            {tag, ck, _} when tag in [:call, :callo] -> ck in scc
            _ -> false
          end) and Enum.any?(gs, &match?({_, _, _}, &1))
      end)
    end)
  end

  defp solve_(scc, parsed, solved, ext, num, pref, force) do
    other = fn ck ->
      case solved do
        %{^ck => r} -> r.sig
        _ -> ext.(ck).sig
      end
    end

    # deterministisch, wo es geht; sonst (ein Prädikat, Klauseln, die sich
    # nicht ausschließen) nichtdeterministisch (siehe nd_irs!/3)
    case Hints.evidence(scc, parsed, other, false) do
      :no ->
        for k <- scc, do: Util.why(k, "Modi widersprechen sich")
        nd_solve(scc, parsed, other, num, pref, force)

      {:ok, fixed} ->
        with {:ok, fixed} <- forced(fixed, scc, force, parsed) do
          solve_modes(scc, parsed, other, num, fixed, false, pref)
        end ||
          nd_solve(scc, parsed, other, num, pref, force)
    end
  end

  # die festen Modi (force) zu denen aus den Klauseln: widersprechen sie
  # sich, nil
  defp forced(fixed, scc, force, parsed) do
    f =
      for key <- scc,
          k <- 0..(parsed[key].arity - 1),
          m = force[{key, k}],
          m != nil,
          into: %{},
          do: {{key, k}, m}

    if Enum.all?(f, fn {p, m} -> Map.get(fixed, p, m) == m end) do
      {:ok, Map.merge(fixed, f)}
    else
      for key <- scc,
          map_size(f) > 0,
          do: Util.why(key, "die verlangten Modi widersprechen den Klauseln")

      nil
    end
  end

  # Hinweise auf Modi hier nur von der ersten Stelle einer Kopfvariablen
  # (btw(L, H, L): die dritte Stelle ist Ausgabe, auch wenn L verglichen
  # wird)
  # (ohne Hinweise der Aufrufstellen: eine Ausgabe dient hier auch dem
  # Prüfen – Lösungen nach dem Muster gefiltert –, mem(-any, +list) taugt
  # also auch für mem(1, L), umgekehrt nicht)
  defp nd_solve([_] = scc, parsed, other, num, _pref, force) do
    if PrologEx.Flags.get("jit_nondet") == {:atom, "true"} do
      with {:ok, fixed} <- Hints.evidence(scc, parsed, other, true),
           {:ok, fixed} <- forced(fixed, scc, force, parsed) do
        solve_modes(scc, parsed, other, num, fixed, true, %{})
      else
        _ -> nil
      end
    end
  end

  defp nd_solve(_, _, _, _, _, _), do: nil

  defp solve_modes(scc, parsed, other, num, fixed, nd, pref) do
    open =
      for key <- scc,
          k <- 0..(parsed[key].arity - 1),
          not Map.has_key?(fixed, {key, k}),
          do: {key, k}

    # gemeldet wird, warum der gemeinte Modus nicht geht: mit Hinweisen der
    # Aufrufstellen (call_prefs/3) der erste Kandidat, sonst der letzte (die
    # meisten Eingaben)
    first? = Enum.any?(open, &Map.has_key?(pref, &1))
    seen = make_ref()

    open
    |> candidates(pref)
    |> nd_find_value(scc, fn assign ->
      modes = Map.merge(fixed, assign)

      try do
        {reqs, outs, irs} = Types.types(scc, parsed, modes, other, num, nd)

        irs =
          if nd do
            Map.new(irs, fn {key, cs} -> {key, Types.nd_irs!(cs, scc, other)} end)
          else
            for key <- scc,
                do: Excl.exclusive!(Enum.map(irs[key], & &1.ir), MapSet.member?(num, key))

            irs
          end

        {:ok,
         Map.new(scc, fn key ->
           p = parsed[key]

           sig = %{
             modes: Map.new(0..(p.arity - 1), &{&1, modes[{key, &1}]}),
             req:
               for(
                 k <- 0..(p.arity - 1),
                 modes[{key, k}] == :in,
                 into: %{},
                 do: {k, reqs[{key, k}]}
               ),
             out:
               for(
                 k <- 0..(p.arity - 1),
                 modes[{key, k}] == :out,
                 into: %{},
                 do: {k, outs[{key, k}]}
               ),
             num: MapSet.member?(num, key),
             nd: nd,
             # ein Schnitt in einer Klausel (call_flow/4)
             cut: Enum.any?(p.clauses, fn {_, gs} -> Types.has_cut?(gs) end)
           }

           {key, %{sig: sig, irs: Enum.map(irs[key], & &1.ir), p: p}}
         end)}
      catch
        {:no, r} ->
          # (die nichtdeterministische Analyse nach der deterministischen:
          # deren Grund bleibt)
          if not (first? and Process.get(seen) == true) do
            Process.put(seen, true)
            put = if nd, do: &Map.put_new/3, else: &Map.put/3
            for k <- scc, do: Process.put(@why_key, put.(Process.get(@why_key), k, r))
          end

          nil
      end
    end)
    |> tap(fn _ -> Process.delete(seen) end)
  end

  # wie Enum.find_value/2; {:nd_stop, Grund} bricht ab (nil)
  defp nd_find_value(cands, scc, f) do
    Enum.find_value(cands, f)
  catch
    {:nd_stop, r} ->
      for k <- scc, do: Process.put(@why_key, Map.put(Process.get(@why_key), k, r))
      nil
  end

  # alle Belegungen der offenen Positionen: zuerst die, die am meisten
  # Hinweisen der Aufrufstellen folgen (call_prefs/2), sonst mehr Ausgaben
  # zuerst, dann Ausgaben eher rechts. Die alte letzte (die meisten
  # Eingaben) bleibt die letzte: ihr Grund wird gemeldet, wenn keine passt
  # (solve_modes/7). Zu viele offene: die bevorzugte, dann alle Ausgaben.
  defp candidates(open, pref) when length(open) > @max_enum do
    all_out = Map.new(open, &{&1, :out})
    Enum.uniq([Map.new(open, &{&1, Map.get(pref, &1, :out)}), all_out])
  end

  defp candidates(open, pref) do
    n = length(open)

    cands =
      for mask <- 0..(Bitwise.bsl(1, n) - 1) do
        outs =
          for {pos, i} <- Enum.with_index(open),
              Bitwise.band(mask, Bitwise.bsl(1, i)) != 0,
              do: pos

        {mask, outs}
      end
      |> Enum.sort_by(fn {mask, outs} -> {-length(outs), -mask} end)
      |> Enum.map(fn {_, outs} ->
        Map.new(open, &{&1, if(&1 in outs, do: :out, else: :in)})
      end)

    if Enum.any?(open, &Map.has_key?(pref, &1)) do
      agree = fn a -> Enum.count(open, &(Map.get(pref, &1) == a[&1])) end
      ranked = cands |> Enum.with_index() |> Enum.sort_by(fn {a, i} -> {-agree.(a), i} end)
      ranked = Enum.map(ranked, &elem(&1, 0))
      last = List.last(cands)
      if List.last(ranked) == last, do: ranked, else: ranked ++ [last]
    else
      cands
    end
  end
end
