# Gemeinsam für bench/prof/*.exs: Programm und Fälle der Suite
# (bench/suite.exs), dazu aus der Umgebung
#   PRELUDE  weitere Klauseln/Direktiven, etwa ":- use_module(library(swi))."
#   EXTRA    weitere Fälle "name=Ziel@@name=Ziel…" (@@ trennt, weil Ziele
#            ; und | enthalten)
System.put_env("SUITE_NO_MAIN", "1")
Code.require_file(Path.join(__DIR__, "../suite.exs"))

defmodule Prof do
  def setup do
    db = PrologEx.use_library(%{}, "lists", "user")
    prelude = Suite.prelude() <> "\n" <> System.get_env("PRELUDE", "")
    {db, []} = PrologEx.Consult.load(db, PrologEx.Parser.read_terms(prelude))
    PrologEx.put_db(db)
    {db, []} = PrologEx.Consult.load(db, PrologEx.Parser.read_terms(Suite.program()))

    db =
      Enum.reduce(Suite.extra(), db, fn f, db ->
        {db, _warnings} = PrologEx.Consult.load(db, PrologEx.Parser.read_terms(File.read!(f)))
        db
      end)

    PrologEx.put_db(db)

    extra =
      for x <- String.split(System.get_env("EXTRA", ""), "@@", trim: true) do
        [n, q] = String.split(x, "=", parts: 2)
        {String.trim(n), q}
      end

    {db, Suite.cases() ++ extra}
  end

  def goal(q) do
    [{:term, g, _}] = PrologEx.Parser.read_terms(q <> " .")
    g
  end

  def run(db, g), do: PrologEx.query(db, g) |> Enum.take(1)
end
