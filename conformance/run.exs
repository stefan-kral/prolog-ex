# ISO-Konformität: die Testsammlung von Logtalk (tests/prolog) direkt in
# PrologEx ausführen – ohne Logtalk, mit einem Nachbau des nötigen Teils
# von lgtunit (conformance/lgtunit.pl).
#
#   git clone --depth 1 https://github.com/LogtalkDotOrg/logtalk3 /pfad/logtalk3
#   mix run conformance/run.exs /pfad/logtalk3 [Filter] [--failures datei]
#
# Filter: Teil des Pfads unter tests/prolog, z. B. predicates/atom_length_2
# oder syntax. Ausgabe: Zusammenfassung je Bereich und je Testdatei; mit
# --failures alle fehlgeschlagenen Tests mit Grund in eine Datei.
#
# Jeder Test läuft in einem eigenen Prozess (Zeitlimit 5 s, Ausgabe wird
# verschluckt); die Datenbank einer Testdatei wird von Test zu Test
# weitergereicht (wie in lgtunit).

alias PrologEx.Reader
import PrologEx, only: [a: 1, mk: 2]

{opts, args, _} = OptionParser.parse(System.argv(), strict: [failures: :string])

[lgt_root | filter] = args
filter = List.first(filter) || ""
tests_root = Path.join(Path.expand(lgt_root), "tests/prolog")
harness = Path.expand("lgtunit.pl", __DIR__)
work_root = Path.join(System.tmp_dir!(), "prolog_ex_conformance")
File.rm_rf!(work_root)

files =
  Path.wildcard(Path.join(tests_root, "**/tests*.lgt"))
  |> Enum.filter(&String.contains?(Path.relative_to(&1, tests_root), filter))
  |> Enum.sort()

# Operatoren von Logtalk (core/core.pl) und lgtunit
lgt_ops = [
  {600, "xfy", "::"},
  {600, "fy", "::"},
  {600, "fy", "^^"},
  {200, "fy", "?"},
  {200, "fy", "@"},
  {200, "fy", "++"},
  {200, "fy", "--"},
  {700, "xfx", "as"},
  {700, "xfx", "=~="}
]

defmodule Conf do
  import PrologEx, only: [a: 1, mk: 2]

  # Ziel übersetzen: {G} läuft in user, ^^G und lokale Ziele im Modul lgt
  def tr({:struct, "{}", [g]}), do: mk(":", [a("user"), g])
  def tr({:struct, "^^", [g]}), do: g

  def tr({:struct, op, [x, y]}) when op in [",", ";", "->", "*->"],
    do: mk(op, [tr(x), tr(y)])

  def tr({:struct, op, [g]}) when op in ["\\+", "once", "ignore", "call", "assertion"],
    do: mk(op, [tr(g)])

  def tr({:struct, "assertion", [n, g]}), do: mk("assertion", [n, tr(g)])
  def tr({:struct, "catch", [g, c, r]}), do: mk("catch", [tr(g), c, tr(r)])
  def tr({:struct, "findall", [t, g, l]}), do: mk("findall", [t, tr(g), l])
  def tr({:struct, "forall", [c, act]}), do: mk("forall", [tr(c), tr(act)])
  def tr(g), do: g

  # Klauseln außerhalb eines Objekts gehören zu user
  def target, do: if(Process.get(:lgt_in_object), do: "lgt", else: "user")

  def logtalk?({:struct, "::", _}), do: true
  def logtalk?({:struct, _, args}), do: Enum.any?(args, &logtalk?/1)
  def logtalk?([h | t]), do: logtalk?(h) or logtalk?(t)
  def logtalk?(_), do: false

  # Testklausel -> {name, outcome, options, body} | {:skip, name} | nil
  def test_clause({:struct, ":-", [head, body]}), do: test_head(head, body)
  def test_clause({:struct, ":-", [_]}), do: nil
  def test_clause(head), do: test_head(head, a("true"))

  defp test_head({:struct, "-", [h]}, _body) do
    case test_head(h, a("true")) do
      {name, _, _, _} -> {:skip, name}
      _ -> nil
    end
  end

  defp test_head({:struct, "test", [n]}, b), do: {n, a("true"), [], b}
  defp test_head({:struct, "test", [n, o]}, b), do: {n, o, [], b}
  defp test_head({:struct, "test", [n, o, opts]}, b), do: {n, o, opts, b}
  defp test_head({:struct, "succeeds", [n]}, b), do: {n, a("true"), [], b}
  defp test_head({:struct, "deterministic", [n]}, b), do: {n, a("deterministic"), [], b}
  defp test_head({:struct, "fails", [n]}, b), do: {n, a("false"), [], b}

  defp test_head({:struct, "throws", [n, ball]}, b) do
    o = if is_list(ball), do: mk("balls", [ball]), else: mk("ball", [ball])
    {n, o, [], b}
  end

  defp test_head(_, _), do: nil

  # Optionen übersetzen (Ziele in condition/setup/cleanup)
  def tr_opts(opts) when is_list(opts) do
    Enum.map(opts, fn
      {:struct, k, [g]} when k in ["condition", "setup", "cleanup"] -> mk(k, [tr(g)])
      o -> o
    end)
  end

  def tr_opts(_), do: []

  # eine Anfrage in einem eigenen Prozess: {:ok, antworten, db} | :timeout
  def run(db, goal, reader, timeout \\ 5000) do
    parent = self()

    pid =
      spawn(fn ->
        Reader.put_current(reader)
        {:ok, io} = StringIO.open("")
        Process.group_leader(self(), io)

        res =
          try do
            ans = db |> PrologEx.query(goal) |> Enum.take(1)
            {:ok, ans, PrologEx.current_db()}
          rescue
            e -> {:error, Exception.message(e) |> String.slice(0, 300)}
          catch
            k, e -> {:error, inspect({k, e}) |> String.slice(0, 300)}
          end

        send(parent, {:done, self(), res})
      end)

    receive do
      {:done, ^pid, res} -> res
    after
      timeout ->
        Process.exit(pid, :kill)
        :timeout
    end
  end
end

alias PrologEx.Reader

new_reader = fn ->
  {:ok, r} = Reader.start_link()
  Reader.put_current(r)
  PrologEx.Ops.reset()
  for {p, t, n} <- lgt_ops, do: Reader.op(r, p, t, n)
  r
end

# Grund-Datenbank: Gerüst (Modul lgt), dazu lists/apply in user
base_db = fn reader ->
  Reader.put_current(reader)
  PrologEx.put_db(Enum.reduce(["lists", "apply"], %{}, &PrologEx.use_library(&2, &1, "user")))
  {:ok, _} = PrologEx.Consult.load_file(harness)
  PrologEx.current_db()
end

results =
  for file <- files do
    rel = Path.relative_to(file, tests_root) |> String.replace_suffix("/tests.lgt", "")
    work = Path.join(work_root, rel)
    File.mkdir_p!(work)
    File.cp_r!(Path.dirname(file), work)

    reader = new_reader.()
    db = base_db.(reader)
    Process.put(:lgt_in_object, false)

    {:ok, _, db} =
      Conf.run(db, mk(":", [a("lgt"), mk("assertz", [mk("lgt_dir", [a(work <> "/")])])]), reader)

    # Datei lesen; op-Direktiven wirken sofort
    :ok = Reader.open_file(reader, Path.join(work, Path.basename(file)))

    items =
      Stream.unfold(:go, fn
        :eof ->
          nil

        :go ->
          {items, status} = Reader.next_chunk(reader)

          items =
            Enum.map(items, fn
              {:term, t, _} ->
                t = PrologEx.unmark(t)

                case t do
                  {:struct, ":-", [{:struct, "op", [p, ty, n]}]} ->
                    ns = if is_list(n), do: n, else: [n]

                    for {:atom, name} <- ns,
                        do:
                          (try do
                             Reader.op(reader, p, elem(ty, 1), name)
                           rescue
                             _ -> :ok
                           end)

                  _ ->
                    :ok
                end

                {:term, t}

              other ->
                other
            end)

          {items, if(status == :pause, do: :go, else: :eof)}
      end)
      |> Enum.flat_map(& &1)

    # bedingte Übersetzung (:- if/elif/else/endif), Klauseln und Tests
    eval_cond = fn db, c ->
      if Conf.logtalk?(c),
        do: false,
        else:
          match?(
            {:ok, [_], _},
            Conf.run(
              db,
              mk(":", [a("lgt"), mk("catch", [Conf.tr(c), a("_"), a("fail")])]),
              reader
            )
          )
    end

    # Zustand: stack (if-Ebenen: :on, :off, :done, :dead), db, in Objekt?,
    # Terme für user (außerhalb des Objekts), Tests, unlesbare Klauseln
    st0 = %{stack: [], db: db, obj: false, user: [], tests: [], unr: 0}

    st =
      Enum.reduce(items, st0, fn
        {:error, _msg}, st ->
          if Enum.all?(st.stack, &(&1 == :on)), do: %{st | unr: st.unr + 1}, else: st

        {:term, t}, st ->
          active = Enum.all?(st.stack, &(&1 == :on))

          case t do
            {:struct, ":-", [{:struct, "if", [c]}]} ->
              top =
                cond do
                  not active -> :dead
                  eval_cond.(st.db, c) -> :on
                  true -> :off
                end

              %{st | stack: [top | st.stack]}

            {:struct, ":-", [{:struct, "elif", [c]}]} ->
              [top | rest] = st.stack

              top =
                cond do
                  top in [:on, :done] -> :done
                  top == :dead -> :dead
                  eval_cond.(st.db, c) -> :on
                  true -> :off
                end

              %{st | stack: [top | rest]}

            {:struct, ":-", [{:atom, "else"}]} ->
              [top | rest] = st.stack
              top = %{off: :on, on: :done, done: :done, dead: :dead}[top]
              %{st | stack: [top | rest]}

            {:struct, ":-", [{:atom, "endif"}]} ->
              %{st | stack: tl(st.stack)}

            _ when not active ->
              st

            {:struct, ":-", [{:struct, "object", _}]} ->
              %{st | obj: true}

            {:struct, ":-", [{:atom, "end_object"}]} ->
              %{st | obj: false}

            # außerhalb des Objekts: gewöhnliche Prolog-Datei für user
            _ when not st.obj ->
              %{st | user: [t | st.user]}

            # im Objekt: dynamic für lokale Prädikate, sonst Direktiven ignorieren
            {:struct, ":-", [{:struct, "dynamic", [spec]}]} ->
              case Conf.run(st.db, mk(":", [a("lgt"), mk("dynamic", [spec])]), reader) do
                {:ok, _, db} -> %{st | db: db}
                _ -> st
              end

            {:struct, ":-", [_]} ->
              st

            clause ->
              case Conf.test_clause(clause) do
                nil ->
                  # lokales Prädikat des Testobjekts
                  c =
                    case clause do
                      {:struct, ":-", [h, b]} -> mk(":-", [h, Conf.tr(b)])
                      h -> h
                    end

                  case Conf.run(st.db, mk(":", [a("lgt"), mk("assertz", [c])]), reader) do
                    {:ok, _, db} -> %{st | db: db}
                    _ -> st
                  end

                test ->
                  %{st | tests: [test | st.tests]}
              end
          end
      end)

    # den user-Teil als echte Datei laden (Direktiven wie multifile,
    # discontiguous, op, initialization wirken wie bei uns üblich)
    user_file = Path.join(work, "lgt_user_part.pl")

    File.write!(
      user_file,
      for t <- Enum.reverse(st.user), into: "" do
        PrologEx.format(t, quoted: true, ignore_ops: true) <> ".\n"
      end
    )

    db =
      case Conf.run(st.db, mk("consult", [a(user_file)]), reader) do
        {:ok, _, db} -> db
        _ -> st.db
      end

    tests = st.tests
    unreadable = st.unr
    tests = Enum.reverse(tests)

    {rs, db_final} =
      Enum.map_reduce(tests, db, fn
        {:skip, name}, db ->
          {{PrologEx.format(name, quoted: true), :skipped, "disabled"}, db}

        {name, o, opts, body}, db ->
          nm = PrologEx.format(name, quoted: true)

          if Conf.logtalk?(body) or Conf.logtalk?(opts) do
            {{nm, :skipped, "logtalk"}, db}
          else
            res = {:var, "LgtResult"}

            goal =
              mk(":", [
                a("lgt"),
                mk("$lgt_run", [o, Conf.tr(body), Conf.tr_opts(opts), res])
              ])

            case Conf.run(db, goal, reader) do
              {:ok, [ans], db2} ->
                case ans["LgtResult"] do
                  {:atom, "passed"} -> {{nm, :passed, ""}, db2}
                  {:atom, "skipped"} -> {{nm, :skipped, "condition"}, db2}
                  r -> {{nm, :failed, PrologEx.format(r, quoted: true)}, db2}
                end

              {:ok, [], db2} ->
                {{nm, :failed, "harness failed"}, db2}

              {:error, msg} ->
                {{nm, :failed, "crash: " <> msg}, db}

              :timeout ->
                {{nm, :failed, "timeout"}, db}
            end
          end
      end)

    _ = db_final
    GenServer.stop(reader)
    {rel, rs, unreadable}
  end

count = fn rs, k -> Enum.count(rs, fn {_, s, _} -> s == k end) end

IO.puts(
  String.pad_trailing("Testdatei", 48) <>
    "  ok  fehl  übersp  unlesbar"
)

for {rel, rs, unr} <- results do
  IO.puts(
    String.pad_trailing(rel, 48) <>
      String.pad_leading("#{count.(rs, :passed)}", 4) <>
      String.pad_leading("#{count.(rs, :failed)}", 6) <>
      String.pad_leading("#{count.(rs, :skipped)}", 8) <>
      String.pad_leading("#{unr}", 10)
  )
end

all = Enum.flat_map(results, fn {_, rs, _} -> rs end)
unr = Enum.sum(Enum.map(results, fn {_, _, u} -> u end))

IO.puts(
  "\nGesamt: #{count.(all, :passed)} bestanden, #{count.(all, :failed)} fehlgeschlagen, " <>
    "#{count.(all, :skipped)} übersprungen, #{unr} Klauseln unlesbar (#{length(files)} Dateien)"
)

if f = opts[:failures] do
  text =
    for {rel, rs, _} <- results, {nm, :failed, why} <- rs, into: "" do
      "#{rel}  #{nm}\n    #{why}\n"
    end

  File.write!(f, text)
  IO.puts("Fehlschläge: #{f}")
end
