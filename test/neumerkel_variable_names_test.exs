defmodule PrologEx.NeumerkelVariableNamesTest do
  # Beispiele und Fehlerfälle zu den Optionen variable_names/1 (write_term,
  # read_term) und zu Stream-Optionen
  # (https://www.complang.tuwien.ac.at/ulrich/iso-prolog/variable_names).
  # Dateien liegen im Testverzeichnis: f steht für eine Datei dort, in1 bis
  # in3 enthalten die gelesenen Texte der Tabelle.
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @moduletag :tmp_dir

  @wt "write_term(T,[quoted(true), variable_names([N=T])])"
  @xyz "write_term(T,[quoted(true), variable_names(['X'=X,'Y'=Y,'Z'=Z])])"
  @zyx "write_term(T,[quoted(true), variable_names(['Z'=Z,'Y'=Y,'X'=X])])"
  @xxx "write_term(T,[quoted(true), variable_names(['X'=Z,'X'=Y,'X'=X])])"
  @vn "write_term(T,[variable_names(VN_list)])"
  @sn "write_term(S,[quoted(true), variable_names([N=T])])"
  @wopt "domain_error(write_option,"
  @sopt "domain_error(stream_option,"
  @inst "instantiation_error"

  @rows [
    {@wt, {:error, @inst}},
    {"N = 'X', " <> @wt, {:out, "X"}},
    {"N = T, " <> @wt, {:error, @inst}},
    {"N = '_', " <> @wt, {:out, "_"}},
    {"N = '_/*.*/', " <> @wt, {:out, "_/*.*/"}},
    {"N = x, " <> @wt, {:out, "x"}},
    {"N = 'x+y', " <> @wt, {:out, "x+y"}},
    {"N = '))', " <> @wt, {:out, "))"}},
    {"N = 7, " <> @wt, {:error, @wopt}},
    {"N = 1+2, " <> @wt, {:error, @wopt}},
    {"N = '$VAR'(9), " <> @wt, {:error, @wopt}},
    {"T = a, " <> @wt, {:error, @inst}},
    {"T = a, N = 'Any', " <> @wt, {:out, "a"}},
    {"T = '$VAR'(9), N = '_', " <> @wt, {:out, "'$VAR'(9)"}},
    {"T = f(_), N = 'Bad', " <> @wt, {:out_re, "^f\\(_\\w*\\)$"}},
    {"freeze(T,throw(g(T))), N = 'X', " <> @wt, {:out, "X"}},
    {@xyz, {:out_re, "^_\\w*$"}},
    {"T=(X,Y,Z), " <> @xyz, {:out, "X,Y,Z"}},
    {"Z=Y, T=(X,Y,Z), " <> @xyz, {:out, "X,Y,Y"}},
    {"Z=Y, Y=X, T=(X,Y,Z), " <> @xyz, {:out, "X,X,X"}},
    {"T=(Y,Z), " <> @xyz, {:out, "Y,Z"}},
    {"T=(Z,Y), " <> @xyz, {:out, "Z,Y"}},
    {"T=(X,Y,Z), " <> @zyx, {:out, "X,Y,Z"}},
    {"Z=Y, T=(X,Y,Z), " <> @zyx, {:out, "X,Z,Z"}},
    {"Z=Y, Y=X, T=(X,Y,Z), " <> @zyx, {:out, "Z,Z,Z"}},
    {"T=(X,Y,Z), " <> @xxx, {:out, "X,X,X"}},
    {"T=(1,2,3), T=(X,Y,Z), " <> @xxx, {:out, "1,2,3"}},
    {@vn, {:error, @inst}},
    {"VN_list = 1, " <> @vn, {:error, @wopt}},
    {"VN_list = [[]], " <> @vn, {:error, @wopt}},
    {"VN_list = non_list, " <> @vn, {:error, @wopt}},
    {"VN_list = [T='T'|non_list], " <> @vn, {:error, @wopt}},
    {"VN_list = ['T'=T|_], " <> @vn, {:error, @inst}},
    {"VN_list = ['T'=T|non_list], " <> @vn, {:error, @wopt}},
    {"VN_list = [T-'T'], " <> @vn, {:error, @wopt}},
    {"VN_list = [_,a], " <> @vn, {:error, @inst}},
    {"VN_list = [a,_], " <> @vn, {:error, @wopt}},
    {"VN_list = [a|_], " <> @vn, {:error, @inst}},
    {"VN_list = [i=i,7=i], " <> @vn, {:error, @wopt}},
    {"VN_list = [_,_], " <> @vn, {:error, @inst}},
    # -X^2 ist -(X^2); die Seite zeigt -X^2, der neuere Entwurf zu 7.10.5
    # (WDCor.3, h 2 iv) verlangt Klammern nach dem Präfix -: - (X^2)
    {"write_term(-X^2,[variable_names(['X'=X])])", {:out, "- (X^2)"}},
    {"X=1, write_term(-X^2,[variable_names(['X'=X])])", {:out, "- (1^2)"}},
    {@sn, {:error, @inst}},
    {"S=1+T,N='/*r*/V', " <> @sn, {:out, "1+ /*r*/V"}},
    {"S=1+T,N=' /*r*/V', " <> @sn, {:out, "1+ /*r*/V"}},
    {"S=1+T,N=(+), " <> @sn, {:out, "1+ +"}},
    {"S=T+1,N=(+), " <> @sn, {:out, "+ +1"}},
    {"S=(1 is T),N='X', " <> @sn, {:out, "1 is X"}},
    # mehrfach angegeben: die letzte Option gilt
    {"write_term(T,[variable_names(['Bad'=T]), variable_names(['Good'=T])])", {:out, "Good"}},
    {"open(f,write,_,[O])", {:error, @inst}},
    {"O = 1, open(f,write,_,[O])", {:error, "domain_error(stream_option,1)"}},
    {"O = typex(_), open(f,write,_,[O])", {:error, @sopt}},
    {"O = typex(1), open(f,write,_,[O])", {:error, "domain_error(stream_option,typex(1))"}},
    {"O = typex(s(_)), open(f,write,_,[O])", {:error, @sopt}},
    {"O = type(text), open(f,write,St,[O]), close(St)", :succeeds},
    {"O = type(1), open(f,write,_,[O])", {:error, "domain_error(stream_option,type(1))"}},
    {"O = type(_), open(f,write,_,[O])", {:error, @inst}},
    {"O = alias(_), open(f,write,_,[O])", {:error, @inst}},
    {"O = type(nontype), open(f,write,_,[O])",
     {:error, "domain_error(stream_option,type(nontype))"}},
    {"O = alias(1), open(f,write,_,[O])", {:error, "domain_error(stream_option,alias(1))"}},
    # read_term: Namen in der Reihenfolge des ersten Auftretens
    {"open(in1, read, S), read_term(S, T, [variable_names(VN_list)]), " <>
       "VN_list=[_=1,_=2,_=3], writeq(VN_list), close(S)", {:out, "['B'=1,'C'=2,'A'=3]"}},
    {"open(in2, read, S), read_term(S, T, [variable_names(VN_list)]), close(S)", :succeeds},
    # Optionswerte werden erst nach dem Lesen unifiziert; ein Syntaxfehler
    # geht vor
    {"open(in2, read, S), VN_list = 42, read_term(S, T, [variable_names(VN_list)])", :fails},
    {"open(in3, read, S), VN_list = 42, read_term(S, T, [variable_names(VN_list)])",
     {:error, "syntax_error("}},
    {"open(in2, read, S), read_term(S, T, [singletons(1)])", :fails},
    {"open(in2, read, S), read_term(S, T, [singletons([]), variable_names([])]), close(S)",
     :succeeds},
    {"open(in1, read, S), read_term(S, T, [singletons(Ss), variable_names(Vs), " <>
       "variables(Vars)]), close(S), Ss == [], Vars = [B,C,A], Vs == ['B'=B,'C'=C,'A'=A], " <>
       "T == B+C+A+B+C+A", :succeeds}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r, db: TableCase.db(r, ~w(lists between apply iso_ext))}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Stream.reset()
    File.write!(Path.join(c.tmp_dir, "in1"), "B+C+A+B+C+A.")
    File.write!(Path.join(c.tmp_dir, "in2"), "a.")
    File.write!(Path.join(c.tmp_dir, "in3"), "a b.")
    :ok
  end

  for {q, expect} <- @rows do
    test q, c do
      # Dateinamen auf das Testverzeichnis beziehen (kein File.cd!: async)
      q =
        Regex.replace(~r/open\((f|in\d),/, unquote(q), fn _, name ->
          # der Pfad enthält den Testnamen, also auch ' und \\
          path = c.tmp_dir |> Path.join(name) |> String.replace(~w(\\ '), &"\\#{&1}")
          "open('#{path}',"
        end)

      actual = TableCase.run(c.reader, c.db, q)
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
