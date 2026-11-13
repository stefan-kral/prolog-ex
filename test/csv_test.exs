defmodule PrologEx.CsvTest do
  # library(csv): SWIs Teil (Erwartungen: Ausgaben von SWI-Prolog 9.0.4,
  # über den Kern in Elixir und über die DCG für faule Listen) und
  # Scryers parse_csv//1,2 und write_csv/2,3 (Erwartungen: Scryer)
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    prog = """
    :- use_module(library(csv)).
    :- use_module(library(lists)).
    :- use_module(library(dcgs)).
    :- use_module(library(pio)).
    :- use_module(library(between)).
    :- use_module(library(swi)).
    :- use_module(library(iso_ext)).
    :- use_module(library(format)).
    r(A, O, R) :- atom_codes(A, Cs),
        ( catch(phrase(csv(R0, O), Cs), error(E, _), R0 = err(E)) -> R = R0 ; R = fail ).
    % dasselbe über die DCG (wie für eine faule Liste)
    rd(A, O, R) :- atom_chars(A, Cs), csv_options(Rec, O),
        ( catch(phrase((csv:csv_skip_header(Rec), csv:csv_data(R0, Rec)), Cs), error(E, _), R0 = err(E))
        -> R = R0 ; R = fail ).
    """

    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(r, prog))
    {:ok, reader: r, db: db}
  end

  defp check(c, q, expect) do
    Reader.put_current(c.reader)
    actual = TableCase.run(c.reader, c.db, q)

    assert TableCase.matches?(expect, actual),
           "#{q}\nerwartet: #{inspect(expect)}\nerhalten: #{inspect(actual)}"
  end

  defp tmp(name),
    do:
      Path.join(System.tmp_dir!(), "prolog_ex_csv_#{System.unique_integer([:positive])}_#{name}")

  @cases [
    {"'a,b,c\\n1,2,3\\n'-[]", "[row(a,b,c),row(1,2,3)]"},
    {"'a,b\\n1,2'-[]", "[row(a,b),row(1,2)]"},
    {"'a,\"b,c\",d\\n'-[]", "[row(a,'b,c',d)]"},
    {"'\"x\"\"y\",z\\r\\n1,2\\r\\n'-[]", "[row('x\"y',z),row(1,2)]"},
    {"'\"multi\\nline\",x\\n'-[]", "[row('multi\\nline',x)]"},
    {"'a,,b\\n'-[]", "[row(a,'',b)]"},
    {"'\\n\\n'-[]", "[row(''),row('')]"},
    {"''-[]", "[]"},
    {"'a\\n\\nb\\n'-[]", "[row(a),row(''),row(b)]"},
    {"'\"ab\"cd,e\\n'-[]", "fail"},
    {"'\"unterminated,x\\n'-[]", "fail"},
    {"'A,B\\r1,2\\r'-[]", "[row('A','B'),row(1,2)]"},
    {"'x;y\\n'-[]", "[row('x;y')]"},
    {"'a,b\\n1\\n'-[]", "err(domain_error(row_arity(2),1))"},
    {"' a , \"b\" ,c \\n'-[]", "[row(' a ',' \"b\" ','c ')]"},
    {"'Hello,World\\n'-[]", "[row('Hello','World')]"},
    {"'a,b,c\\n1,2,3\\n'-[strip(true)]", "[row(a,b,c),row(1,2,3)]"},
    {"'\"x\"\"y\",z\\r\\n1,2\\r\\n'-[strip(true)]", "[row('x\"y',z),row(1,2)]"},
    {"'\\n\\n'-[strip(true)]", "[row(''),row('')]"},
    {"'\"ab\"cd,e\\n'-[strip(true)]", "fail"},
    {"'x;y\\n'-[strip(true)]", "[row('x;y')]"},
    {"'Hello,World\\n'-[strip(true)]", "[row('Hello','World')]"},
    {"'a,\"b,c\",d\\n'-[convert(false)]", "[row(a,'b,c',d)]"},
    {"'a,,b\\n'-[convert(false)]", "[row(a,'',b)]"},
    {"'a\\n\\nb\\n'-[convert(false)]", "[row(a),row(''),row(b)]"},
    {"'A,B\\r1,2\\r'-[convert(false)]", "[row('A','B'),row('1','2')]"},
    {"' a , \"b\" ,c \\n'-[convert(false)]", "[row(' a ',' \"b\" ','c ')]"},
    {"'a,b\\n1,2'-[case(down)]", "[row(a,b),row(1,2)]"},
    {"'\"multi\\nline\",x\\n'-[case(down)]", "[row('multi\\nline',x)]"},
    {"''-[case(down)]", "[]"},
    {"'\"unterminated,x\\n'-[case(down)]", "fail"},
    {"'a,b\\n1\\n'-[case(down)]", "err(domain_error(row_arity(2),1))"},
    {"'a,b,c\\n1,2,3\\n'-[case(up),convert(false)]", "[row('A','B','C'),row('1','2','3')]"},
    {"'\"x\"\"y\",z\\r\\n1,2\\r\\n'-[case(up),convert(false)]", "[row('X\"Y','Z'),row('1','2')]"},
    {"'\\n\\n'-[case(up),convert(false)]", "[row(''),row('')]"},
    {"'\"ab\"cd,e\\n'-[case(up),convert(false)]", "fail"},
    {"'x;y\\n'-[case(up),convert(false)]", "[row('X;Y')]"},
    {"'Hello,World\\n'-[case(up),convert(false)]", "[row('HELLO','WORLD')]"},
    {"'a,\"b,c\",d\\n'-[separator(59)]", "[row('a,\"b,c\",d')]"},
    {"'a,,b\\n'-[separator(59)]", "[row('a,,b')]"},
    {"'a\\n\\nb\\n'-[separator(59)]", "[row(a),row(''),row(b)]"},
    {"'A,B\\r1,2\\r'-[separator(59)]", "[row('A,B'),row('1,2')]"},
    {"' a , \"b\" ,c \\n'-[separator(59)]", "[row(' a , \"b\" ,c ')]"},
    {"'a,b\\n1,2'-[match_arity(false)]", "[row(a,b),row(1,2)]"},
    {"'\"multi\\nline\",x\\n'-[match_arity(false)]", "[row('multi\\nline',x)]"},
    {"''-[match_arity(false)]", "[]"},
    {"'\"unterminated,x\\n'-[match_arity(false)]", "fail"},
    {"'a,b\\n1\\n'-[match_arity(false)]", "[row(a,b),row(1)]"},
    {"'a,b,c\\n1,2,3\\n'-[functor(r),arity(2)]", "err(domain_error(row_arity(2),3))"},
    {"'\"x\"\"y\",z\\r\\n1,2\\r\\n'-[functor(r),arity(2)]", "[r('x\"y',z),r(1,2)]"},
    {"'\\n\\n'-[functor(r),arity(2)]", "err(domain_error(row_arity(2),1))"},
    {"'\"ab\"cd,e\\n'-[functor(r),arity(2)]", "fail"},
    {"'x;y\\n'-[functor(r),arity(2)]", "err(domain_error(row_arity(2),1))"},
    {"'Hello,World\\n'-[functor(r),arity(2)]", "[r('Hello','World')]"},
    {"'a,\"b,c\",d\\n'-[ignore_quotes(true)]", "[row(a,'\"b','c\"',d)]"},
    {"'a,,b\\n'-[ignore_quotes(true)]", "[row(a,'',b)]"},
    {"'a\\n\\nb\\n'-[ignore_quotes(true)]", "[row(a),row(''),row(b)]"},
    {"'A,B\\r1,2\\r'-[ignore_quotes(true)]", "[row('A','B'),row(1,2)]"},
    {"' a , \"b\" ,c \\n'-[ignore_quotes(true)]", "[row(' a ',' \"b\" ','c ')]"},
    {"'a,b\\n1,2'-[skip_header(#)]", "[row(a,b),row(1,2)]"},
    {"'\"multi\\nline\",x\\n'-[skip_header(#)]", "[row('multi\\nline',x)]"},
    {"''-[skip_header(#)]", "[]"},
    {"'\"unterminated,x\\n'-[skip_header(#)]", "fail"},
    {"'a,b\\n1\\n'-[skip_header(#)]", "err(domain_error(row_arity(2),1))"},
    {"'# h1\\n#h2\\n\\n\\na,b\\n'-[skip_header(#)]", "[row(a,b)]"}
  ]

  for {{case_, expect}, i} <- Enum.with_index(@cases) do
    test "csv//2 #{i}: #{case_}", c do
      check(c, "X = (#{unquote(case_)}), X = A-O, r(A, O, R), R == #{unquote(expect)}", :succeeds)

      check(
        c,
        "X = (#{unquote(case_)}), X = A-O, rd(A, O, R), R == #{unquote(expect)}",
        :succeeds
      )
    end
  end

  test "Zahlen wie SWI (ohne Inf)", c do
    check(c, "r(' 42,42 ,+5,-5,- 5,0x1A,1e10,1.5,abc,007\\n', [], R)", [
      "R = [row(' 42','42 ',5,-5,'- 5',26,10000000000.0,1.5,abc,7)]"
    ])
  end

  test "Schreiben als DCG", c do
    check(
      c,
      "phrase(csv([row(a, 'b,c', 'q\"q', 1, 2.5, 'x\\ny', [])]), L), atom_codes(A, L)",
      {:any, [:succeeds]}
    )

    check(
      c,
      "phrase(csv([row(a, 'b,c', 'q\"q', 1, 2.5, 'x\\ny', [])]), L), atom_codes(A, L), " <>
        "A == 'a,\"b,c\",\"q\"\"q\",1,2.5,\"x\\ny\",[]\\r\\n'",
      :succeeds
    )

    check(
      c,
      "phrase(csv([row(a,b), row('',c)], [separator(0';)]), L), atom_codes(A, L), A == 'a;b\\r\\n;c\\r\\n'",
      :succeeds
    )
  end

  test "Dateien und Streams", c do
    f = tmp("t.csv")
    g = tmp("t.tsv")

    try do
      check(
        c,
        "csv_write_file('#{f}', [row(name, age, note), row('Anna', 31, 'a,b'), row('Bob', 2.5, 'say \"hi\"'), row(x, '', 'two\\nlines')])",
        :succeeds
      )

      rows =
        "[row(name,age,note),row('Anna',31,'a,b'),row('Bob',2.5,'say \"hi\"'),row(x,'','two\\nlines')]"

      check(c, "csv_read_file('#{f}', R), R == #{rows}", :succeeds)
      check(c, "phrase_from_file(csv(R), '#{f}'), R == #{rows}", :succeeds)

      check(
        c,
        "open('#{f}', read, S), csv_read_stream(S, R, []), close(S), R == #{rows}",
        :succeeds
      )

      check(
        c,
        "csv_read_file('#{f}', R, [functor(p), convert(false)]), " <>
          "R == [p(name,age,note),p('Anna','31','a,b'),p('Bob','2.5','say \"hi\"'),p(x,'','two\\nlines')]",
        :succeeds
      )

      check(
        c,
        "findall(L-R, csv_read_file_row('#{f}', R, [line(L)]), Rs), " <>
          "Rs == [1-row(name,age,note),2-row('Anna',31,'a,b'),3-row('Bob',2.5,'say \"hi\"'),4-row(x,'','two\\nlines')]",
        :succeeds
      )

      check(
        c,
        "open('#{f}', read, S), csv_options(O, []), csv_read_row(S, X1, O), csv_read_row(S, _, O), " <>
          "csv_read_row(S, _, O), csv_read_row(S, X4, O), csv_read_row(S, X5, O), close(S), " <>
          "X1 == row(name,age,note), X4 == row(x,'','two\\nlines'), X5 == end_of_file",
        :succeeds
      )

      # .tsv: Tab als Trenner
      check(
        c,
        "csv_write_file('#{g}', [row(a, 'b c', 1), row('x\\ty', z, 2)]), csv_read_file('#{g}', R)",
        ["R = [row(a,'b c',1),row('x\\ty',z,2)]"]
      )

      check(c, "catch(csv_write_file('#{f}', [row(f(x))]), error(E, _), true)", [
        "E = type_error(number,f(x))"
      ])
    after
      File.rm(f)
      File.rm(g)
    end
  end

  test "csv_write_stream/3", c do
    check(
      c,
      "csv_write_stream(user_output, [row(a,b), row(1,'q\"')], [separator(0';)])",
      {:out, "a;b\r\n1;\"q\"\"\"\r\n"}
    )
  end

  test "Optionen", c do
    check(c, "catch(csv_options(_, [case(foo)]), error(E, _), true)", [
      "E = type_error(oneof([down,preserve,up]),foo)"
    ])

    check(c, "catch(csv_options(_, [strip(maybe)]), error(E, _), true)", [
      "E = type_error(boolean,maybe)"
    ])

    check(
      c,
      "csv_options(R, [separator(0';), foo(1)]), R = csv_options(S, St, IQ, C, Ca, F, _, M, _)",
      :succeeds
    )

    check(c, "r('x;y\\n', [separator(';')], R)", ["R = [row(x,y)]"])
    check(c, "r('# h1\\n#h2\\n\\n\\na,b\\n', [skip_header('#')], R)", ["R = [row(a,b)]"])
    check(c, "rd('# h1\\n#h2\\n\\n\\na,b\\n', [skip_header('#')], R)", ["R = [row(a,b)]"])
    check(c, "r('a,b', [arity(3)], R)", ["R = err(domain_error(row_arity(3),2))"])
  end

  test "großer Text: Elixir und DCG gleich", c do
    check(
      c,
      "findall(L, (between(1, 300, I), atomic_list_concat([I, ',\"x', I, '\",', I, '.5,\"a\"\"b\",\\n'], L)), Ls), " <>
        "atomic_list_concat(Ls, A), r(A, [], R1), rd(A, [], R2), R1 == R2, length(R1, 300)",
      :succeeds
    )
  end

  # --- Scryer ------------------------------------------------------------------

  test "parse_csv//1,2 (Scryer)", c do
    check(
      c,
      "atom_chars('col1,col2,col3,col4\\none,2,,three', Cs), once(phrase(parse_csv(D), Cs)), " <>
        "D == frame([[c,o,l,'1'],[c,o,l,'2'],[c,o,l,'3'],[c,o,l,'4']], [[[o,n,e],2,[],[t,h,r,e,e]]])",
      :succeeds
    )

    check(
      c,
      "atom_chars('one;2;;three', Cs), once(phrase(parse_csv(D, [with_header(false), token_separator(';')]), Cs)), " <>
        "D == frame([], [[[o,n,e],2,[],[t,h,r,e,e]]])",
      :succeeds
    )

    check(
      c,
      "atom_chars('a,\"b,c\",3.5\\r\\nx,\"q\"\"q\",-7\\n', Cs), once(phrase(parse_csv(D), Cs)), " <>
        "D == frame([[a],[b,',',c],3.5], [[[x],[q,'\"',q],-7]])",
      :succeeds
    )
  end

  test "write_csv/2,3 (Scryer)", c do
    f = tmp("s.csv")

    try do
      check(
        c,
        "write_csv('#{f}', frame([[c,o,l,'1'],[c,o,l,'2']], [[[o,n,e],2],[[],[t,'\"',x]]]))",
        :succeeds
      )

      # wie Scryer: format/2 mit ~w schreibt Zeichenlisten als Listen
      assert File.read!(f) == "[c,o,l,1],[c,o,l,2]\n[o,n,e],2\n,[t,\",\",x]"

      check(
        c,
        "write_csv('#{f}', frame([[a],[b]], [[[o,n,e],[]]]), [with_header(false), line_separator('\\r\\n'), token_separator(';'), null_value('\\\\N')])",
        :succeeds
      )

      assert File.read!(f) == "[o,n,e];\\N"
    after
      File.rm(f)
    end
  end
end
