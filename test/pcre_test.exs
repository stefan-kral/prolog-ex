defmodule PrologEx.PcreTest do
  # library(pcre): Schnittstelle wie SWI-Prolog, über Erlangs :re (PCRE2)
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @inst "instantiation_error"

  # Subjekte als Atome (Ergebnisse dann als Atome); Zeichen- und
  # Codelisten eigens unten
  @rows [
    # re_match/2,3
    {"re_match('^needle'/i, 'Needle in a haystack')", true},
    {"re_match(x, abc)", :fails},
    {"re_match('^b', 'a\\nb')", :fails},
    {"re_match('^b'/m, 'a\\nb')", true},
    {"re_match('a.b', 'a\\nb')", :fails},
    {"re_match('a.b'/s, 'a\\nb')", true},
    {"re_match('a b'/x, ab)", true},
    {"re_match('^b', 'a\\r\\nb', [multiline(true), newline(crlf)])", true},
    {"re_match('^a', a, [bol(false)])", :fails},
    {"re_match('^a', a, [bol(true)])", true},
    {"re_match('a$', a, [eol(true)])", true},
    {"re_match('x*', abc, [empty(true)])", true},
    {"re_match('^b', 'a\\rb', [multiline(true)])", :fails},
    {"re_match('^b', 'a\\rb', [multiline(true), newline(cr)])", true},
    {"re_match('^b', 'a\\rb', [multiline(true), newline2(anycrlf)])", true},
    {"re_match('a\\\\Rb', 'a\\r\\nb', [bsr(anycrlf)])", true},
    {"re_match('a\\\\Rb', 'a\\x85\\b')", true},
    {"re_match('a\\\\Rb', 'a\\x85\\b', [bsr(anycrlf)])", :fails},
    {"re_match('a$', a, [eol(false)])", :fails},
    {"re_match('x*', abc, [empty(false)])", :fails},
    {"re_match('x*', abc)", true},
    {"re_match(b, abc, [anchored(true)])", :fails},
    {"re_match(b, abc, [start(1), anchored(true)])", true},
    {"re_match('ä', 'äb', [start(1)])", :fails},
    {"re_match(b, 'äb', [start(1), anchored(true)])", true},
    {"re_match(b, ab, [start(10)])", :fails},
    {"re_match('^\\\\w+$', 'äöü')", :fails},
    {"re_match('^\\\\w+$', 'äöü', [ucp(true)])", true},
    {"re_match('a+?$', aaa, [greedy(false)])", true},
    {"re_match(a, 'A', [caseless(true), caseless(false)])", true},
    {"re_match(a, 'A', [caseless(false), caseless(true)])", :fails},
    {"re_match(a/i, 'A', [caseless(false)])", true},
    {"re_match(a, a, [optimise(true), jit(false), utf_check(true)])", true},
    # Fehler
    {"re_match(_, a)", {:error, @inst}},
    {"re_match(a, _)", {:error, @inst}},
    {"re_match(a, f(x))", {:error, "type_error(text,f(x))"}},
    {"re_match(f(x), a)", {:error, "type_error(text,f(x))"}},
    {"re_match(a, 1)", {:error, "type_error(text,1)"}},
    {"re_match(a, [a|_])", {:error, @inst}},
    {"re_match(a, [a|b])", {:error, "type_error(text,[a|b])"}},
    {"re_match(a, [a,1])", {:error, "type_error(text,[a,1])"}},
    {"re_match(a, [a,_])", {:error, @inst}},
    {"re_match(a, [ab])", {:error, "type_error(text,[ab])"}},
    {"re_match(a, [-1])", {:error, "type_error(text,[-1])"}},
    {"re_match(a/_, a)", {:error, @inst}},
    {"re_match(a/q, a)", {:error, "domain_error(re_flag,q)"}},
    {"re_match(a/1, a)", {:error, "type_error(text,1)"}},
    {"re_match('a(b', ab)", {:error, "syntax_error('missing closing parenthesis at 3')"}},
    {"re_match('(a+)+$', aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab)",
     {:error, "resource_error(match_limit)"}},
    {"re_match(a, a, foo)", {:error, "type_error(list,foo)"}},
    {"re_match(a, a, [a|_])", {:error, @inst}},
    {"re_match(a, a, _)", {:error, @inst}},
    {"re_match(a, a, [_])", {:error, @inst}},
    {"re_match(a, a, [foo(1)])", {:error, "domain_error(re_option,foo(1))"}},
    {"re_match(a, a, [foo])", {:error, "domain_error(re_option,foo)"}},
    {"re_match(a, a, [compat(javascript)])",
     {:error, "domain_error(re_option,compat(javascript))"}},
    {"re_match(a, a, [caseless(maybe)])", {:error, "type_error(bool,maybe)"}},
    {"re_match(a, a, [caseless(_)])", {:error, @inst}},
    {"re_match(a, a, [newline(foo)])", {:error, "domain_error(re_option,newline(foo))"}},
    {"re_match(a, a, [newline(1)])", {:error, "domain_error(re_option,newline(1))"}},
    {"re_match(a, a, [capture_type(foo)])",
     {:error, "domain_error(re_option,capture_type(foo))"}},
    {"re_match(a, a, [start(-1)])", {:error, "domain_error(not_less_than_zero,-1)"}},
    {"re_match(a, a, [start(x)])", {:error, "type_error(integer,x)"}},
    # re_matchsub/3,4: 0, nicht benannte Gruppen, benannte nach Name
    {"re_matchsub('(\\\\w+)@(\\\\w+)', 'mail: jan@swi', S)", ["S = [0-'jan@swi',1-jan,2-swi]"]},
    {"re_matchsub(x, abc, S)", :fails},
    {"re_matchsub('(?<date>(?<year_I>(?:\\\\d\\\\d)?\\\\d\\\\d)-(?<month_I>\\\\d\\\\d)-" <>
       "(?<day_I>\\\\d\\\\d))', '2017-04-20', S)",
     ["S = [0-'2017-04-20',date-'2017-04-20',day-20,month-4,year-2017]"]},
    {"re_matchsub('(?<n_A>\\\\d+)', x12, S)", ["S = [0-'12',n-'12']"]},
    {"re_matchsub('(?<n_A>\\\\d+)', \"x12\", S)", ["S = [0-[49,50],n-'12']"]},
    {"re_matchsub('(?<n_S>\\\\d+)', \"x12\", S)", ["S = [0-[49,50],n-[49,50]]"]},
    {"re_matchsub('(?<v_T>\\\\w+\\\\(\\\\w+\\\\))', 'x foo(Bar) y', S)",
     ["S = [0-'foo(Bar)',v-foo(_A)]"]},
    {"re_matchsub('(?<n_R>b+)', 'äabbc', S)", ["S = [0-bb,n-(2-2)]"]},
    {"re_matchsub('b+'/r, 'äabbbc', S)", ["S = [0-(2-3)]"]},
    {"re_matchsub('b+', 'äabbbc', S, [capture_type(range)])", ["S = [0-(2-3)]"]},
    {"re_matchsub('\\\\w+'/t, 'foo(X)', S)", ["S = [0-foo]"]},
    {"re_matchsub('\\\\d+'/t, 'x 42', S)", ["S = [0-42]"]},
    {"re_matchsub(b, abc, S, [capture_type(chars)])", ["S = [0-[b]]"]},
    {"re_matchsub(b, abc, S, [capture_type(codes)])", ["S = [0-[98]]"]},
    {"re_matchsub(b, abc, S, [capture_type(atom)])", ["S = [0-b]"]},
    {"re_matchsub('(x)?b', ab, S)", ["S = [0-b]"]},
    {"re_matchsub('(?<a>x)|(?<b>y)', y, S)", ["S = [0-y,b-y]"]},
    {"re_matchsub('(?<n>a)\\\\k<n>', aa, S)", ["S = [0-aa,n-a]"]},
    # Nummern benannter Gruppen aus dem Muster gelesen (Klassen, Escapes,
    # Kommentare zählen nicht) ...
    {"re_matchsub('[[:alpha:]](?<x>\\\\d)', a1, S)", ["S = [0-a1,x-'1']"]},
    {"re_matchsub('\\\\((?<x>a)', '(a', S)", ["S = [0-'(a',x-a]"]},
    {"re_matchsub('\\\\Q(\\\\E(?<x>a)', '(a', S)", ["S = [0-'(a',x-a]"]},
    {"re_matchsub('[\\\\]](?<x>a)', ']a', S)", ["S = [0-']a',x-a]"]},
    {"re_matchsub('[]](?<x>a)', ']a', S)", ["S = [0-']a',x-a]"]},
    {"re_matchsub('[^]](?<x>a)', 'ba', S)", ["S = [0-ba,x-a]"]},
    {"re_matchsub('(?#(x)(?<x>a)', a, S)", ["S = [0-a,x-a]"]},
    {"re_matchsub('[(](a)(?<x>b)', '(ab', S)", ["S = [0-'(ab',1-a,x-b]"]},
    {"re_matchsub('[](](?<x>a)', '(a', S)", ["S = [0-'(a',x-a]"]},
    {"re_matchsub('[^](](?<x>a)', 'ba', S)", ["S = [0-ba,x-a]"]},
    {"re_matchsub('[[:alpha:](](?<x>\\\\d)', '(1', S)", ["S = [0-'(1',x-'1']"]},
    {"re_matchsub('\\\\Q(\\\\E(a)(?<x>b)', '(ab', S)", ["S = [0-'(ab',1-a,x-b]"]},
    {"re_matchsub('# (b)\\n(?<x>a)'/x, a, S)", ["S = [0-a,x-a]"]},
    {"re_matchsub('(?<n>c)(?|(a)|(b))(x)', cbx, S)", ["S = [0-cbx,1-c,2-b,3-x,n-c]"]},
    {"re_matchsub('(?i)(a)(?<x>b)', ab, S)", ["S = [0-ab,1-a,x-b]"]},
    {"re_matchsub(' (?<x>a) # (b)'/x, a, S)", ["S = [0-a,x-a]"]},
    {"re_matchsub('(*UTF)(a)(?<x>b)', ab, S)", ["S = [0-ab,1-a,x-b]"]},
    {"re_matchsub(\"(?'x'a)(?P<y>b)(c)\", abc, S)", ["S = [0-abc,3-c,x-a,y-b]"]},
    {"re_matchsub('(?<=a)(?<x>b)', ab, S)", ["S = [0-b,x-b]"]},
    {"re_matchsub('(a)(?<x>b)', ab, S, [auto_capture(false)])", ["S = [0-ab,x-b]"]},
    # ... wo das nicht sicher geht, auch mit Nummer
    {"re_matchsub('(?x) (?<x>a) # (b)', a, S)", ["S = [0-a,1-a,x-a]"]},
    {"re_matchsub('(?|(a)|(b))(?<n>c)', bc, S)", ["S = [0-bc,1-b,2-c,n-c]"]},
    # re_foldl/6
    {"re_foldl(zaehle, a, aap, 0, N, [])", ["N = 2"]},
    {"re_foldl(sammle, '(?<z_I>\\\\d+)', 'a1b22c333', [], L, [])",
     ["L = [[0-'333',z-333],[0-'22',z-22],[0-'1',z-1]]"]},
    {"re_foldl(zaehle, x, aap, 0, N, [])", ["N = 0"]},
    # re_split/3,4: abwechselnd Zwischenstück und Treffer, ungerade Länge
    {"re_split('a+', abaac, L)", ["L = ['',a,b,aa,c]"]},
    {"re_split(':\\\\s*'/n, 'Age: 33', L)", ["L = ['Age',': ',33]"]},
    {"re_split('/', '/home//jan', L)", ["L = ['',/,home,/,'',/,jan]"]},
    {"re_split(x, abc, L)", ["L = [abc]"]},
    {"re_split(x, '', L)", ["L = ['']"]},
    {"re_split('', ab, L)", ["L = ['','',a,'',b,'','']"]},
    {"re_split('\\\\s+'/a, \"a b\", L)", ["L = [a,' ',b]"]},
    {"re_split(a/i, 'A', L)", {:error, "domain_error(re_flag,i)"}},
    # re_replace/4,5
    {"re_replace(a, x, abab, R)", ["R = xbab"]},
    {"re_replace(a/g, x, abab, R)", ["R = xbxb"]},
    {"re_replace('.', '$$', abc, R)", ["R = '$bc'"]},
    {"re_replace('.'/g, '\\\\\\\\', ab, R)", ["R = \\\\"]},
    {"re_replace('(a)(b)', '\\\\2\\\\1', abc, R)", ["R = bac"]},
    {"re_replace('(\\\\w+)'/g, '<\\\\{1}>', 'ab cd', R)", ["R = '<ab> <cd>'"]},
    {"re_replace('(\\\\w+)'/g, '<${1}>', 'ab cd', R)", ["R = '<ab> <cd>'"]},
    {"re_replace('(\\\\w+)'/g, '<$1>', 'ab cd', R)", ["R = '<ab> <cd>'"]},
    {"re_replace('(?<y_I>\\\\d+)-(?<m_I>\\\\d+)-(?<d_I>\\\\d+)'/g, '$d.$m.${y}', " <>
       "'2017-04-20, 2026-11-01', R)", ["R = '20.4.2017, 1.11.2026'"]},
    {"re_replace('(a)?b'/g, '[\\\\1]', 'ab b', R)", ["R = '[a] []'"]},
    {"re_replace(''/g, '-', ab, R)", ["R = '-a-b-'"]},
    {"re_replace(x, y, abc, R)", ["R = abc"]},
    {"re_replace(b/a, x, \"abc\", R)", ["R = axc"]},
    {"re_replace(b/s, x, abc, R)", ["R = axc"]},
    {"re_replace(b, x, \"abc\", R), atom_codes(A, R)", ["A = axc, R = [97,120,99]"]},
    {"re_replace(b, x, \"abc\", R, [capture_type(atom)])", ["R = axc"]},
    {"re_replace('(?<x>a)', '\\\\1', abc, R)", {:error, "existence_error(re_group,1)"}},
    {"re_replace(a, '$nope', abc, R)", {:error, "existence_error(re_group,nope)"}},
    {"re_replace(a/i, x, abc, R)", {:error, "domain_error(re_flag,i)"}},
    {"re_replace(a, _, abc, R)", {:error, @inst}},
    # re_compile/3 und '$regex'/2
    {"re_compile('a+b'/im, R, [greedy(false)])",
     ["R = '$regex'('a+b',[caseless(true),greedy(false),multiline(true)])"]},
    {"re_compile('a+b', R, [caseless(true), caseless(false)])",
     ["R = '$regex'('a+b',[caseless(true)])"]},
    {"re_compile('a+b', R, [caseless(false), greedy(true), capture_type(string)])",
     ["R = '$regex'('a+b',[])"]},
    {"re_compile(a/a, R, [])", ["R = '$regex'(a,[capture_type(atom)])"]},
    {"re_compile(a, R, [start(1)])", ["R = '$regex'(a,[])"]},
    {"re_compile(a/g, R, [])", {:error, "domain_error(re_flag,g)"}},
    {"re_compile('a(', R, [])", {:error, "syntax_error("}},
    {"re_compile(a, R, []), re_compile(R, R2, [caseless(true)])",
     ["R = '$regex'(a,[]), R2 = '$regex'(a,[])"]},
    {"re_compile(a/i, R, []), re_match(R, 'A')", ["R = '$regex'(a,[caseless(true)])"]},
    {"re_compile(a/i, R, []), re_match(R, 'A', [caseless(false)])",
     ["R = '$regex'(a,[caseless(true)])"]},
    {"re_compile(a/a, R, []), re_matchsub(R, \"a\", S)",
     ["R = '$regex'(a,[capture_type(atom)]), S = [0-a]"]},
    {"re_compile('(?<x>a)', R, []), copy_term(R, R2), re_matchsub(R2, a, S)",
     ["R = '$regex'('(?<x>a)',[]), R2 = '$regex'('(?<x>a)',[]), S = [0-a,x-a]"]},
    # selbst gebaute '$regex'-Terme: gültig nur in kanonischer Form
    {"re_match('$regex'('a+b', [caseless(true)]), 'AAB')", true},
    {"re_match('$regex'(a, []), a)", true},
    {"re_match('$regex'(a, [multiline(true), caseless(true)]), a)",
     {:error, "domain_error(regex,'$regex'(a,[multiline(true),caseless(true)]))"}},
    {"re_match('$regex'(a, [caseless(false)]), a)",
     {:error, "domain_error(regex,'$regex'(a,[caseless(false)]))"}},
    {"re_match('$regex'(a, [caseless(true), caseless(true)]), a)",
     {:error, "domain_error(regex,"}},
    {"re_match('$regex'(a, [start(1)]), a)", {:error, "domain_error(regex,"}},
    {"re_match('$regex'(a, [foo]), a)", {:error, "domain_error(regex,"}},
    {"re_match('$regex'(a, [caseless(_)]), a)", {:error, "domain_error(regex,"}},
    {"re_match('$regex'(a, x), a)", {:error, "domain_error(regex,'$regex'(a,x))"}},
    {"re_match('$regex'(a, [_|_]), a)", {:error, "domain_error(regex,"}},
    {"re_match('$regex'(f(x), []), a)", {:error, "domain_error(regex,'$regex'(f(x),[]))"}},
    {"re_match('$regex'(\"a\", []), a)", {:error, "domain_error(regex,"}},
    {"re_match('$regex'(_, []), a)", {:error, "domain_error(regex,"}},
    {"re_match('$regex'('a(', []), a)", {:error, "syntax_error("}},
    {"re_match('$regex'(a, [])/i, a)", {:error, "type_error(text,'$regex'(a,[]))"}},
    # re_config/1, re_flush/0
    {"re_config(version(V)), atom(V)", :succeeds},
    {"re_config(unicode(B))", ["B = true"]},
    {"re_config(foo(_))", :fails},
    {"re_config(foo)", :fails},
    {"findall(K, (re_config(T), functor(T, K, _)), Ks)",
     ["Ks = [version,unicode,utf8,unicode_properties,jit]"]},
    {"re_flush, re_match(a, a)", true}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    text = """
    :- use_module(library(pcre)).
    :- use_module(library(lists)).
    zaehle(_, N0, N) :- N is N0 + 1.
    sammle(S, L, [S|L]).
    """

    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(r, text))
    {:ok, reader: r, db: db}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  for {q, expect} <- @rows do
    test q, c do
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end

  defp ask(c, q, dq) do
    Task.async(fn ->
      Reader.put_current(c.reader)
      PrologEx.Flags.set("double_quotes", {:atom, dq})
      PrologEx.put_db(c.db)
      [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

      c.db
      |> PrologEx.query(g)
      |> Enum.take(2)
      |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
    end)
    |> Task.await()
  end

  test "Textart: das Ergebnis hat die Art des Subjekts", c do
    assert ask(c, ~s|re_matchsub("b+", "abbc", S)|, "chars") == [~s|S = [0-"bb"]|]
    assert ask(c, ~s|re_matchsub("b+", "abbc", S)|, "codes") == ["S = [0-[98,98]]"]
    assert ask(c, ~s|re_matchsub("b+", abbc, S)|, "chars") == ["S = [0-bb]"]
    assert ask(c, ~s|re_replace("b", "x", "abc", R)|, "chars") == [~s|R = "axc"|]
    assert ask(c, ~s|re_split("b", "abc", L)|, "chars") == [~s|L = ["a","b","c"]|]
    assert ask(c, ~s|re_split("b", "abc", L)|, "atom") == ["L = [a,b,c]"]
    # [] als Subjekt: die Art von double_quotes
    assert ask(c, ~s|re_split("x", [], L)|, "codes") == ["L = [[]]"]
    assert ask(c, ~s|re_split("x", [], L)|, "atom") == ["L = ['']"]

    assert ask(c, ~s|re_matchsub("ä", "aä", S, [capture_type(range)])|, "chars") ==
             ["S = [0-(1-1)]"]
  end

  test "der Cache ist beschränkt; re_flush/0 leert ihn", c do
    Task.async(fn ->
      Reader.put_current(c.reader)
      PrologEx.put_db(c.db)

      for i <- 1..300 do
        assert {_, {:answers, ["true"]}} = TableCase.run(c.reader, c.db, "re_match(a#{i}, a#{i})")
      end

      assert map_size(Process.get(:prolog_ex_re_cache)) <= 256
      assert {_, {:answers, ["true"]}} = TableCase.run(c.reader, c.db, "re_flush")
      assert Process.get(:prolog_ex_re_cache) == nil
    end)
    |> Task.await()
  end

  test "Kompilat aus dem Cache, nicht aus dem Term", c do
    Task.async(fn ->
      Reader.put_current(c.reader)
      PrologEx.put_db(c.db)
      TableCase.run(c.reader, c.db, "re_match(a, a)")
      cache = Process.get(:prolog_ex_re_cache)
      assert [{{"a", []}, %{mp: {:re_pattern, _, _, _, _}}}] = Map.to_list(cache)
    end)
    |> Task.await()
  end
end
