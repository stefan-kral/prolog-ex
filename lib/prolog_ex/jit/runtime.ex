defmodule PrologEx.Jit.Runtime do
  @moduledoc """
  Laufzeit des übersetzten Codes (PrologEx.Jit): Eintritt aus dem
  Interpreter (run/6, nd_run/6, nd_resume/5), Prüfpunkte (tick/0) und was
  der erzeugte Code ruft – Zerlegen (list/1, st/3), Tests und Vergleiche
  (tt/2, teq/2, tord/3, ueq/2, eqc/2), eingebaute Prädikate (b_*/n,
  nd_*/n) und die Verkettung nichtdeterministischer Lösungen (nd_tail/3,
  nd_first/2).
  """

  # --- Laufzeit -----------------------------------------------------------
  #
  # Während ein übersetztes Prädikat läuft, liegt unter @run_key
  # {Blockgröße, Prüffunktion, Bindungsspeicher, min_heap_size vorher | nil,
  # Ausgabevariablen} – ein Eintrag, einmal gesetzt und einmal entfernt.

  @run_key :prolog_ex_jit

  @doc false
  # Prüfpunkt: der laufende Block ist verbraucht. Die Prüffunktion verbucht
  # den Block, prüft die Grenzen (wirft wie der Interpreter) und gibt den
  # nächsten Block zurück (>= 1)
  def tick do
    {chunk, check, store, heap, outs} = Process.get(@run_key)
    next = check.(chunk)
    Process.put(@run_key, {next, check, store, deep_stack(heap), outs})
    next
  end

  # Tiefe Rekursion: jede Garbage Collection durchsucht den ganzen Stack.
  # Ist er tief, bekommt der Heap Luft im Verhältnis (min_heap_size), damit
  # die Collections selten bleiben; nach dem Aufruf wieder wie vorher.
  # heap: nil oder {min_heap_size vorher, jetzt}
  @deep 50_000
  defp deep_stack(heap) do
    {:stack_size, s} = Process.info(self(), :stack_size)
    want = 4 * s

    case heap do
      _ when s <= @deep ->
        heap

      nil ->
        {Process.flag(:min_heap_size, want), want}

      {old, have} when want > 2 * have ->
        Process.flag(:min_heap_size, want)
        {old, want}

      _ ->
        heap
    end
  end

  @doc false
  # ein übersetztes Prädikat rufen: {:ok, Ausgaben, verbraucht} |
  # {:fail, verbraucht} | :deopt | :warming | {:thrown, ball} (ein
  # Prolog-Fehler aus dem Code, wie guarded/1 der Maschine).
  #
  # Eine Liste aus der Eingabe oder einem Ergebnis ist ein gewöhnlicher Term
  # und wird erst beim Zerlegen gelesen: so viel wie der Interpreter auch
  # liest. Stößt der Code auf etwas, das er nicht kann (ein ungebundener
  # Rest, ein Element, das keine Zahl ist), gibt er auf (:deopt): er hat
  # nichts gebunden, der Interpreter fängt den Aufruf neu an. Noch nicht
  # übersetzt (das Modul fehlt): erst ab dem n-ten Aufruf (Flag
  # jit_threshold) übersetzen, vorher :warming – der Interpreter; selten
  # gerufene Prädikate kosten so keinen Compilerlauf.
  def run({mod, _, _, _, _} = m, ins, chunk, check, store, outs) do
    if :erlang.module_loaded(mod) or warm?(mod),
      do: go(m, ins, chunk, check, store, outs, true),
      else: :warming
  end

  # noch nicht geladen: zählen; an der Schwelle übersetzen (false: der
  # Compiler scheiterte – dann bleibt es beim Interpreter)
  defp warm?(mod) do
    case :persistent_term.get({PrologEx.Jit, mod}, nil) do
      {:ir, _, _, _, c} ->
        :atomics.add_get(c, 1, 1) >= PrologEx.Flags.get("jit_threshold") and
          PrologEx.Jit.Codegen.ensure(mod)

      _ ->
        false
    end
  end

  defp go({mod, entry, _, _, _} = m, ins, chunk, check, store, outs, retry) do
    Process.put(@run_key, {chunk, check, store, nil, outs})

    try do
      case apply(mod, entry, ins ++ [chunk]) do
        r when is_tuple(r) ->
          [b | outs] = Tuple.to_list(r)
          {:ok, outs, chunk_now() - b}

        b when b >= 0 ->
          {:fail, chunk_now() - b}

        b ->
          {:fail, chunk_now() + b + 1}
      end
    rescue
      e in PrologEx.Error ->
        thrown(e.term)

      e in UndefinedFunctionError ->
        cond do
          e.module != mod or not retry -> reraise e, __STACKTRACE__
          PrologEx.Jit.Codegen.ensure(mod) -> :retry
          true -> :deopt
        end
    catch
      :jit_deopt -> :deopt
    after
      case Process.delete(@run_key) do
        {_, _, _, {old, _}, _} -> Process.flag(:min_heap_size, old)
        _ -> :ok
      end
    end
    |> case do
      :retry -> go(m, ins, chunk, check, store, outs, false)
      r -> r
    end
  end

  # --- nichtdeterministisch übersetzte Prädikate ---------------------------
  #
  # Lösungen als Schritte: {:sol, b, Ausgaben, weiter} (weiter: fn b ->
  # Schritt end oder nil) oder {:none, b}. Der Interpreter legt für weiter
  # einen Choice Point an ({:jit_nd, ...}) und ruft es beim Zurücksetzen
  # über nd_resume/6 – mit neuem Block und neuem Eintrag unter @run_key.

  @doc false
  # Lösungen eines letzten Aufrufs (step) über mapf zu denen der Klausel,
  # danach die weiteren Klauseln (alt)
  def nd_tail({:none, b}, _mapf, nil), do: {:none, b}
  def nd_tail({:none, b}, _mapf, alt), do: alt.(b)
  def nd_tail({:sol, _, _, _} = step, nil, nil), do: step
  def nd_tail({:sol, b, outs, nx}, nil, alt), do: {:sol, b, outs, nd_chain(nx, nil, alt)}

  def nd_tail({:sol, b, outs, nx}, mapf, alt) do
    case mapf.(outs, b) do
      {b, houts} ->
        {:sol, b, houts, nd_chain(nx, mapf, alt)}

      b ->
        case nx do
          nil -> nd_tail({:none, b}, mapf, alt)
          f -> nd_tail(f.(b), mapf, alt)
        end
    end
  end

  @doc false
  # die erste Lösung, deren Ausgaben f passen: {:ok, b, Werte} | {:none, b}
  def nd_first({:none, b}, _f), do: {:none, b}

  def nd_first({:sol, b, outs, nx}, f) do
    case f.(outs, b) do
      {:ok, _, _} = r -> r
      b when nx == nil -> {:none, b}
      b -> nd_first(nx.(b), f)
    end
  end

  defp nd_chain(nil, _mapf, alt), do: alt
  defp nd_chain(nx, mapf, alt), do: fn b -> nd_tail(nx.(b), mapf, alt) end

  @doc false
  # erster Aufruf: {:sol, Ausgaben, verbraucht, weiter} | {:fail, verbraucht}
  # | :deopt | :warming | {:thrown, ball}
  def nd_run({mod, entry, _, _, _}, ins, chunk, check, store, outs) do
    if :erlang.module_loaded(mod) or warm?(mod),
      do: nd_go(fn b -> apply(mod, entry, ins ++ [b]) end, chunk, check, store, outs),
      else: :warming
  end

  @doc false
  # beim Zurücksetzen: die nächste Lösung (wie nd_run/6)
  def nd_resume(next, chunk, check, store, outs), do: nd_go(next, chunk, check, store, outs)

  defp nd_go(f, chunk, check, store, outs) do
    Process.put(@run_key, {chunk, check, store, nil, outs})

    try do
      case f.(chunk) do
        {:sol, b, vals, nx} -> {:sol, vals, chunk_now() - b, nx}
        {:none, b} -> {:fail, chunk_now() - b}
      end
    rescue
      e in PrologEx.Error -> thrown(e.term)
      ArithmeticError -> :deopt
      SystemLimitError -> nd_error(fn -> PrologEx.Error.resource!("memory") end)
      UndefinedFunctionError -> :deopt
    catch
      :jit_deopt -> :deopt
    after
      case Process.delete(@run_key) do
        {_, _, _, {old, _}, _} -> Process.flag(:min_heap_size, old)
        _ -> :ok
      end
    end
  end

  # Ein Fehler aus dem Code: aufgeben – der Interpreter rechnet neu und
  # meldet ihn, mit seinen Inferenzen bis dahin (die des Codes bis zum Fehler
  # sind nicht bekannt) und seinem Kontext. Nicht für die Bälle der
  # Prüfpunkte (Grenzen, Abbruch; dort ist der Verbrauch verbucht) und für
  # Speicherfehler.
  defp thrown({:struct, "error", [{:struct, "resource_error", _}, _]} = b), do: {:thrown, b}
  defp thrown({:struct, "error", [_, _]}), do: :deopt
  defp thrown(b), do: {:thrown, b}

  defp nd_error(f) do
    f.()
  rescue
    e in PrologEx.Error -> {:thrown, e.term}
  end

  defp chunk_now, do: elem(Process.get(@run_key), 0)

  defp store, do: elem(Process.get(@run_key), 2)

  @doc false
  # ungebunden?
  def var?({:var, _} = v), do: match?({:var, _}, PrologEx.Store.walk(v, store()))
  def var?(_), do: false

  @doc false
  # Typtest auf einem Term (wie der Interpreter): false oder der gelesene
  # Term. Ist er eine Ausgabevariable des Aufrufs (oder enthält is_list/1
  # eine als Rest), aufgeben: der Interpreter hätte sie vielleicht schon
  # gebunden, der übersetzte Code bindet erst am Ende
  def tt(t, x) do
    {_, _, store, _, outs} = Process.get(@run_key)
    w = PrologEx.Store.walk(x, store)
    if outs != [] and :lists.member(w, outs), do: throw(:jit_deopt)

    ok =
      case t do
        "is_list" ->
          {_, rest} = PrologEx.Builtins.Lists.skip_list(w, store)
          if outs != [] and :lists.member(rest, outs), do: throw(:jit_deopt)
          rest == []

        _ ->
          PrologEx.type_test(t, w)
      end

    if ok, do: w, else: false
  end

  @doc false
  # ==/2 wie der Interpreter; enthält ein Term eine Ausgabevariable:
  # aufgeben (wie tt/2; die Variablen wie term_variables/2, auch zyklisch)
  def teq(a, b) do
    {_, _, store, _, outs} = Process.get(@run_key)

    if outs != [] and
         Enum.any?(PrologEx.Builtins.Order.variables([a, b], store), &:lists.member(&1, outs)),
       do: throw(:jit_deopt)

    PrologEx.Order.equal?(a, b, store)
  end

  @doc false
  # @<, @>, @=<, @>= wie der Interpreter (Standardordnung); eine
  # Ausgabevariable darin: aufgeben (wie teq/2)
  def tord(op, a, b) do
    store = outs_free!([a, b])

    case PrologEx.Order.compare(a, b, store) do
      :lt -> op in ["@<", "@=<"]
      :eq -> op in ["@=<", "@>="]
      :gt -> op in ["@>", "@>="]
    end
  end

  # die Bindungen; aufgeben, wenn eine Ausgabevariable des Aufrufs in den
  # Termen vorkommt (der Interpreter hätte sie schon gebunden)
  defp outs_free!(ts) do
    {_, _, store, _, outs} = Process.get(@run_key)

    if outs != [] and
         Enum.any?(PrologEx.Builtins.Order.variables(ts, store), &:lists.member(&1, outs)),
       do: throw(:jit_deopt)

    store
  end

  # der Term gebunden (sonst – Fehler, functor/3 zum Bauen – aufgeben)
  defp bound!(t) do
    case PrologEx.Store.walk(t, store()) do
      {:var, _} -> throw(:jit_deopt)
      w -> w
    end
  end

  @doc false
  # arg/3: {A} oder :no; N keine Ganzzahl ab 0 oder T nicht zusammengesetzt
  # (Fehler im Interpreter): aufgeben
  def b_arg(n, t) do
    t = bound!(t)
    if not PrologEx.Builtins.Core.compound?(t), do: throw(:jit_deopt)

    case PrologEx.Store.walk(n, store()) do
      0 ->
        :no

      k when is_integer(k) and k > 0 ->
        case PrologEx.Builtins.Terms.nth_arg(elem(PrologEx.Builtins.Terms.parts(t), 1), k) do
          {:ok, a} -> {a}
          :none -> :no
        end

      _ ->
        throw(:jit_deopt)
    end
  end

  @doc false
  # functor/3 zum Zerlegen: {Name, Stelligkeit}
  def b_functor(t) do
    {f, args} = PrologEx.Builtins.Terms.parts(bound!(t))
    {f, length(args)}
  end

  @doc false
  # =../2 zum Zerlegen: {[Name | Argumente]}
  def b_univ(t) do
    {f, args} = PrologEx.Builtins.Terms.parts(bound!(t))
    {PrologEx.list([f | args])}
  end

  @doc false
  # memberchk/2: das erste Element, das ohne Binden gleich ist – {}; eines,
  # das nur durch Binden gleich würde (der Interpreter bände es), ein
  # offener Rest oder keine Liste: aufgeben; sonst :no
  def b_memberchk(x, l) do
    s = store()

    case PrologEx.Store.walk(x, s) do
      a when is_number(a) or (is_tuple(a) and elem(a, 0) == :atom) ->
        chk_atomic(a, PrologEx.Store.walk(l, s), s)

      x ->
        chk(x, PrologEx.Store.walk(l, s), s)
    end
  end

  # Zahl oder Atom: Elemente direkt vergleichen (1 und 1.0 verschieden, wie
  # die Unifikation); ein ungebundenes Element: aufgeben
  defp chk_atomic(a, [h | t], s) do
    case h do
      ^a ->
        {}

      {:var, _} ->
        case PrologEx.Store.walk(h, s) do
          ^a -> {}
          {:var, _} -> throw(:jit_deopt)
          _ -> chk_atomic(a, t, s)
        end

      _ ->
        chk_atomic(a, t, s)
    end
  end

  # eine ground markierte Liste: ohne Variablen (lists:member/2 der BEAM,
  # exakter Vergleich wie die Unifikation)
  defp chk_atomic(a, {:glist, l}, _s), do: if(:lists.member(a, l), do: {}, else: :no)
  defp chk_atomic(_, [], _), do: :no

  defp chk_atomic(a, {:var, _} = v, s) do
    case PrologEx.Store.walk(v, s) do
      {:var, _} -> throw(:jit_deopt)
      t -> chk_atomic(a, t, s)
    end
  end

  defp chk_atomic(_, _, _), do: throw(:jit_deopt)

  defp chk(x, [h | t], s) do
    cond do
      PrologEx.Order.equal?(x, h, s) -> {}
      PrologEx.unify(x, h, s) == :error -> chk(x, PrologEx.Store.walk(t, s), s)
      true -> throw(:jit_deopt)
    end
  end

  defp chk(x, {:glist, l}, s), do: chk(x, l, s)
  defp chk(_, [], _), do: :no
  defp chk(_, _, _), do: throw(:jit_deopt)

  @doc false
  # length/2 einer echten Liste: {N}; sonst aufgeben
  def b_length(l) do
    case PrologEx.Builtins.Lists.skip_list(l, store()) do
      {n, []} -> {n}
      _ -> throw(:jit_deopt)
    end
  end

  @doc false
  # sort/2, msort/2 einer echten Liste wie der Interpreter (Standardordnung
  # mit dem Bindungsspeicher); eine Ausgabevariable des Aufrufs darin:
  # aufgeben (der Interpreter hätte sie schon gebunden)
  def b_sort(l), do: {PrologEx.list(PrologEx.Order.sort_unique(sort_items(l), store()))}
  def b_msort(l), do: {PrologEx.list(PrologEx.Order.sort(sort_items(l), store()))}

  defp sort_items(l) do
    s = outs_free!([l])

    case PrologEx.Builtins.Lists.skip_list(l, s) do
      {_, []} -> PrologEx.Builtins.Lists.items(l, s)
      _ -> throw(:jit_deopt)
    end
  end

  @doc false
  # member/2 als nichtdeterministisch übersetztes Prädikat (Schritte wie
  # nd_tail/3): die Elemente der Reihe nach; nach dem letzten einer echten
  # Liste keine Fortsetzung; ein offener Rest: aufgeben (beim Weiterlesen)
  def nd_member(l, b) do
    case list(l) do
      [h | t] ->
        nx = if last_cell?(t), do: nil, else: fn b -> nd_member(t, b) end
        {:sol, b, [h], nx}

      _ ->
        {:none, b}
    end
  end

  defp last_cell?([]), do: true
  defp last_cell?({:glist, []}), do: true

  defp last_cell?({:var, _} = v) do
    case PrologEx.Store.walk(v, store()) do
      {:var, _} -> false
      t -> last_cell?(t)
    end
  end

  defp last_cell?(_), do: false

  @doc false
  # between/3 ebenso (L, H Ganzzahlen, sonst aufgeben)
  def nd_between(l, h, b) when is_integer(l) and is_integer(h) do
    cond do
      l > h -> {:none, b}
      l == h -> {:sol, b, [l], nil}
      true -> {:sol, b, [l], fn b -> nd_between(l + 1, h, b) end}
    end
  end

  def nd_between(_, _, _), do: throw(:jit_deopt)

  @doc false
  # bit_is_set/2: {} oder :no; keine Ganzzahlen oder K < 0: aufgeben
  def b_bit_is_set(n, k) when is_integer(n) and is_integer(k) and k >= 0,
    do: if(PrologEx.Arith.getbit(n, k) == 1, do: {}, else: :no)

  def b_bit_is_set(_, _), do: throw(:jit_deopt)

  @doc false
  # append/3 mit echter Liste vorn: {Z}; sonst (offenes Ende, keine Liste:
  # der Interpreter zählt auf oder scheitert) aufgeben
  def b_append(x, y) do
    case PrologEx.Builtins.Lists.append_det(x, y, store()) do
      {:ok, z} -> {z}
      :partial -> throw(:jit_deopt)
    end
  end

  # --- library(lfsr) ----------------------------------------------------

  @doc false
  # lfsr_next/3: {X, St} oder :no (alle gezogen); kein fertiger Zustand:
  # aufgeben (der Interpreter meldet den Fehler)
  def b_lfsr_next(st) do
    case PrologEx.Builtins.Lfsr.fields(bound!(st), store()) do
      f when is_tuple(f) -> PrologEx.Builtins.Lfsr.next(f)
      _ -> throw(:jit_deopt)
    end
  end

  @doc false
  # lfsr_done/1: {} oder :no
  def b_lfsr_done(st) do
    case PrologEx.Builtins.Lfsr.fields(bound!(st), store()) do
      f when is_tuple(f) -> if PrologEx.Builtins.Lfsr.done?(f), do: {}, else: :no
      _ -> throw(:jit_deopt)
    end
  end

  # --- library(bytes) ---------------------------------------------------

  defp bin!(t) do
    case bound!(t) do
      {:bytes, b} -> b
      _ -> throw(:jit_deopt)
    end
  end

  defp idx!(t) do
    case bound!(t) do
      k when is_integer(k) -> k
      _ -> throw(:jit_deopt)
    end
  end

  @doc false
  # bytes_length/2: {N}
  def b_bytes_length(b), do: {byte_size(bin!(b))}

  @doc false
  # bytes_at/3 mit bestimmtem Index: {Byte} oder :no
  def b_bytes_at(i, b) do
    a = bin!(b)

    case idx!(i) do
      k when k >= 0 and k < byte_size(a) -> {:binary.at(a, k)}
      _ -> :no
    end
  end

  @doc false
  # bytes_bit/3 mit bestimmtem Index: {Bit} oder :no
  def b_bytes_bit(i, b) do
    a = bin!(b)

    case idx!(i) do
      k when k >= 0 and k < bit_size(a) ->
        <<_::bits-size(^k), x::1, _::bits>> = a
        {x}

      _ ->
        :no
    end
  end

  @doc false
  # bytes_next_bit/3: {P} oder :no; Von negativ: aufgeben (Fehler)
  def b_bytes_next_bit(b, from) do
    a = bin!(b)

    case idx!(from) do
      k when k >= 0 ->
        case PrologEx.Builtins.Bytes.next_bit(a, k) do
          nil -> :no
          q -> {q}
        end

      _ ->
        throw(:jit_deopt)
    end
  end

  @doc false
  # bytes_integer/2 von der Folge zur Zahl: {I}
  def b_bytes_integer(b) do
    case bin!(b) do
      <<>> -> {0}
      a -> {:binary.decode_unsigned(a)}
    end
  end

  @doc false
  # compare/3: {<, = oder >}
  def b_compare(a, b) do
    store = outs_free!([a, b])

    case PrologEx.Order.compare(a, b, store) do
      :lt -> {{:atom, "<"}}
      :eq -> {{:atom, "="}}
      :gt -> {{:atom, ">"}}
    end
  end

  @doc false
  # eine Listenzelle lesen: [K | R], [] oder ein anderer Term (dann passt
  # kein Muster); ein ungebundener Rest: aufgeben
  def list([_ | _] = l), do: l
  def list([]), do: []
  def list({:glist, l}), do: l

  def list({:var, _} = v) do
    case PrologEx.Store.walk(v, store()) do
      {:var, _} -> throw(:jit_deopt)
      t -> list(t)
    end
  end

  def list(t), do: t

  @doc false
  # eine Struktur f/n lesen: ihre Argumente, oder :no (passt nicht); eine
  # ungebundene Variable: aufgeben (der Interpreter bände sie)
  def st({tag, f, args}, f, n) when tag in [:struct, :gstruct],
    do: if(length(args) == n, do: args, else: :no)

  def st({:var, _} = v, f, n) do
    case PrologEx.Store.walk(v, store()) do
      {:var, _} -> throw(:jit_deopt)
      t -> st(t, f, n)
    end
  end

  def st(_, _, _), do: :no

  @doc false
  # zwei Werte wie die Unifikation im Kopf: identisch – ja; nicht
  # unifizierbar – nein; sonst bände sie eine Variable: aufgeben
  def ueq(a, b) do
    s = store()

    cond do
      PrologEx.Order.equal?(a, b, s) -> true
      PrologEx.unify(a, b, s) == :error -> false
      true -> throw(:jit_deopt)
    end
  end

  @doc false
  # gleich der Konstanten (Zahl oder Atom)? Ungebunden: aufgeben
  def eqc({:var, _} = v, c) do
    case PrologEx.Store.walk(v, store()) do
      {:var, _} -> throw(:jit_deopt)
      t -> t === c
    end
  end

  def eqc(t, c), do: t === c

  @doc false
  # ein Element als Zahl (num) bzw. Ganzzahl (int); sonst aufgeben – der
  # Interpreter meldet dann den Fehler oder scheitert an derselben Stelle
  def num(n) when is_integer(n) or is_float(n), do: n
  def num({:var, _} = v), do: walked(v, &(is_integer(&1) or is_float(&1)))
  def num(_), do: throw(:jit_deopt)

  def int(n) when is_integer(n), do: n
  def int({:var, _} = v), do: walked(v, &is_integer/1)
  def int(_), do: throw(:jit_deopt)

  defp walked(v, ok?) do
    x = PrologEx.Store.walk(v, store())
    if ok?.(x), do: x, else: throw(:jit_deopt)
  end
end
