defmodule PrologEx.NeumerkelCleanupTest do
  # Beispiele aus Neumerkels Entwurf zu setup_call_cleanup/3 (7.8.11.4,
  # https://www.complang.tuwien.ac.at/ulrich/iso-prolog/cleanup). Wo der
  # Entwurf mehrere Ausgänge zulässt (c1: der Zeitpunkt nach der letzten
  # Lösung ist implementierungsabhängig), steht hier der von PrologEx: die
  # Aufräumung läuft, sobald das Ziel deterministisch fertig ist.
  # "System error due to uncaught E" ist hier der Fehler E.
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @v "_[A-Z0-9]*"

  @rows [
    {"setup_call_cleanup(fail, _, _)", :fails},
    {"setup_call_cleanup(throw(ex), _, _)", {:error, "ex"}},
    {"setup_call_cleanup(true, throw(unthrown),_)", {:error, "instantiation_error"}},
    {"setup_call_cleanup(true, true, ( true ; throw(x) ))", true},
    {"setup_call_cleanup(true, X = 1, X = 2)", ["X = 1"]},
    # Either: X = 2
    {"setup_call_cleanup(true, true, X = 2)", ["X = 2"]},
    {"setup_call_cleanup(true, X=true,X)", {:error, "instantiation_error"}},
    # Either: uncaught ex
    {"setup_call_cleanup(X=throw(ex), true, X)", {:error, "ex"}},
    {"setup_call_cleanup(true, true, fail)", true},
    # Either
    {"setup_call_cleanup(S=1, G=2, C=3)", ["C = 3, G = 2, S = 1"]},
    {"setup_call_cleanup((S=1;S=2), G=3, C=4)", ["C = 4, G = 3, S = 1"]},
    # Either: outputs '1+2'
    {"setup_call_cleanup(S=1,G=2,write(S+G))", {:out, "1+2", ["G = 2, S = 1"]}},
    # Either: outputs '1+3'
    {"setup_call_cleanup(S=1,(G=2;G=3),write(S+G))",
     {:out, "1+3", ["G = 2, S = 1", "G = 3, S = 1"]}},
    # Either: 1+2>_+_ before succeeding
    {"setup_call_cleanup(S=1,G=2,write(S+G>A+B)), A=3, B=4",
     {:out_re, "^1\\+2>#{@v}\\+#{@v}$", ["A = 3, B = 4, G = 2, S = 1"]}},
    {"setup_call_cleanup(S=1,(G=2;G=3,throw(x)),write(S+G))",
     {:out_re, "^1\\+#{@v}$", {:error, "x"}}},
    # Ereignisse in der Fortsetzung
    {"setup_call_cleanup(S=1,(G=2;G=3),write(S+G>B)), B=4, !",
     {:out, "1+2>4", ["B = 4, G = 2, S = 1"]}},
    # Either: '1+2>_'
    {"setup_call_cleanup(S=1,G=2,write(S+G>B)),B=3,!",
     {:out_re, "^1\\+2>#{@v}$", ["B = 3, G = 2, S = 1"]}},
    # Or: '1+2>3' (die Alternative bleibt bis zum Schnitt offen)
    {"setup_call_cleanup(S=1,(G=2;fail),write(S+G>B)), B=3, !",
     {:out, "1+2>3", ["B = 3, G = 2, S = 1"]}},
    {"setup_call_cleanup(S=1,(G=2;S=2),write(S+G>B)), B=3, !",
     {:out, "1+2>3", ["B = 3, G = 2, S = 1"]}},
    {"setup_call_cleanup(S=1,(G=2;G=3), write(S+G>B)), B=4, throw(x)",
     {:out_re, "^1\\+#{@v}>#{@v}$", {:error, "x"}}},
    {"setup_call_cleanup(S=1,(G=2;G=3), write(S+G>B)), B=4, !, throw(x)",
     {:out, "1+2>4", {:error, "x"}}},
    {"setup_call_cleanup(true, (X=1;X=2), write(a)), setup_call_cleanup(true,(Y=1;Y=2),write(b)), throw(x)",
     {:out, "ba", {:error, "x"}}},
    {"setup_call_cleanup(true, (X=1;X=2), write(a)), setup_call_cleanup(true,(Y=1;Y=2),write(b)), !",
     {:out, "ba", ["X = 1, Y = 1"]}},
    # mehrere Ausnahmen
    {"catch(setup_call_cleanup(true,throw(goal),throw(cl)), Pat, true)", ["Pat = goal"]},
    {"catch(( setup_call_cleanup(true,(G=1;G=2),throw(cl)), throw(cont)), Pat, true)",
     ["Pat = cont"]},
    {"catch(setup_call_cleanup(true, throw(a), setup_call_cleanup(true,fail,throw(b))), Pat, true)",
     ["Pat = a"]}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r, db: TableCase.db(r, ~w(iso_ext))}
  end

  for {q, expect} <- @rows do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
