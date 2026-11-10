defmodule PrologEx.BytesTest do
  # library(bytes): Byte-Folgen als atomarer Typ
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  # b(Liste) als Abkürzung: bytes_list(B, Liste)
  @rows [
    # Typ
    {"bytes_list(B, [1,2]), bytes(B)", :succeeds},
    {"bytes(a)", :fails},
    {"bytes(\"ab\")", :fails},
    {"bytes_list(B, []), atomic(B), \\+ atom(B), \\+ compound(B), \\+ callable(B), ground(B)",
     :succeeds},
    {"bytes_list(B, [1]), functor(B, N, A), N == B", ["A = 0, B = '$bytes'(1), N = '$bytes'(1)"]},
    {"bytes_list(B, [1]), B =.. [X], X == B", :succeeds},
    {"bytes_list(B, [1]), call(B)", {:error, "type_error(callable,'$bytes'(1))"}},
    # Ausgabe: nicht einlesbar, wie Streams
    {"bytes_list(B, [1,2,3]), write(B), write(' '), writeq(f(B))",
     {:out, "$bytes(3) f('$bytes'(3))"}},
    # Gleichheit und Ordnung
    {"bytes_list(A, [1,2]), bytes_list(B, [1,2]), A == B, A = B", :succeeds},
    {"bytes_list(A, [1,2]), bytes_list(B, [1,3]), A = B", :fails},
    {"bytes_list(A, [1]), A = '$bytes'(1)", :fails},
    {"bytes_list(A, [1]), A = f(_)", :fails},
    {"bytes_list(A, [2]), bytes_list(B, [1,9]), bytes_list(C, [2,0]), " <>
       "msort([f(x), C, zz, A, 1, B], L), L == [1, zz, B, A, C, f(x)]", :succeeds},
    {"bytes_list(A, [1]), compare(O1, zzz, A), compare(O2, A, f(x))",
     ["A = '$bytes'(1), O1 = (<), O2 = (<)"]},
    {"bytes_list(A, [1]), X = f(A, Y), copy_term(X, Z), Z = f(B, _), A == B, " <>
       "term_variables(X, Vs), length(Vs, 1)", :succeeds},
    {"bytes_list(A, [1,2]), assertz(st(A)), st(B), A == B", :succeeds},
    # Umwandeln
    {"bytes_list(B, [104,105]), bytes_list(B, L)", ["B = '$bytes'(2), L = [104,105]"]},
    {"bytes_list(B, [1,256])", {:error, "type_error(byte,256)"}},
    {"bytes_list(B, [1,a])", {:error, "type_error(byte,a)"}},
    {"bytes_list(B, [1|_])", {:error, "instantiation_error"}},
    {"bytes_list(B, foo)", {:error, "type_error(list,foo)"}},
    {"bytes_list(foo, _)", {:error, "type_error(bytes,foo)"}},
    {"bytes_utf8(B, \"äö€\"), bl(B, L), bytes_utf8(B, T), atom_chars(A, T)",
     ["A = 'äö€', B = '$bytes'(7), L = [195,164,195,182,226,130,172], T = [ä,ö,'€']"]},
    {"bytes_utf8(B, 'hé'), bl(B, L)", ["B = '$bytes'(3), L = [104,195,169]"]},
    {"bytes_utf8(B, [h,i]), bl(B, L)", ["B = '$bytes'(2), L = [104,105]"]},
    {"bytes_list(B, [255]), bytes_utf8(B, _)", {:error, "representation_error(character)"}},
    {"bytes_latin1(B, \"äb\"), bl(B, L), bytes_latin1(B, T), atom_chars(A, T)",
     ["A = äb, B = '$bytes'(2), L = [228,98], T = [ä,b]"]},
    {"bytes_latin1(B, \"€\")", {:error, "representation_error(character)"}},
    {"bytes_list(B, [0,171,255]), bytes_hex(B, H), atom_chars(A, H)",
     ["A = '00abff', B = '$bytes'(3), H = ['0','0',a,b,f,f]"]},
    {"bytes_hex(B, 'ABcd'), bl(B, L)", ["B = '$bytes'(2), L = [171,205]"]},
    {"bytes_hex(B, abc)", {:error, "domain_error(hex_encoding,abc)"}},
    {"bytes_hex(B, xy)", {:error, "domain_error(hex_encoding,xy)"}},
    {"bytes_utf8(B, \"hi!\"), bytes_base64(B, T), atom_chars(A, T), bytes_base64(C, A), B == C",
     ["A = aGkh, B = '$bytes'(3), C = '$bytes'(3), T = [a,'G',k,h]"]},
    {"bytes_base64(B, 'a*')", {:error, "domain_error(base64_encoding,'a*')"}},
    # Größe und Zugriff
    {"bytes_list(B, [7,8,9]), bytes_length(B, N)", ["B = '$bytes'(3), N = 3"]},
    {"bytes_length(_, _)", {:error, "instantiation_error"}},
    {"bytes_length(x, _)", {:error, "type_error(bytes,x)"}},
    {"bytes_list(B, [7]), bytes_length(B, a)", {:error, "type_error(integer,a)"}},
    {"bytes_list(B, [7,8,9]), bytes_at(1, B, X), \\+ bytes_at(3, B, _), \\+ bytes_at(-1, B, _)",
     ["B = '$bytes'(3), X = 8"]},
    {"bytes_list(B, [7,8]), findall(I-X, bytes_at(I, B, X), L)",
     ["B = '$bytes'(2), L = [0-7,1-8]"]},
    # Teilstücke wie sub_atom/5
    {"bytes_utf8(B, \"abcab\"), findall(P-A-T, (sub_bytes(B, P, 2, A, S), bl(S, T)), L)",
     ["B = '$bytes'(5), L = [0-3-[97,98],1-2-[98,99],2-1-[99,97],3-0-[97,98]]"]},
    {"bytes_utf8(B, \"ab\"), findall(P-N-A, sub_bytes(B, P, N, A, _), L)",
     ["B = '$bytes'(2), L = [0-0-2,0-1-1,0-2-0,1-0-1,1-1-0,2-0-0]"]},
    {"bytes_utf8(B, \"abcd\"), sub_bytes(B, 1, _, 1, S), bl(S, T)",
     ["B = '$bytes'(4), S = '$bytes'(2), T = [98,99]"]},
    {"bytes_utf8(B, \"aaa\"), bytes_utf8(P, \"aa\"), findall(I, sub_bytes(B, I, _, _, P), L)",
     ["B = '$bytes'(3), L = [0,1], P = '$bytes'(2)"]},
    {"bytes_utf8(B, \"ab\"), sub_bytes(B, 3, _, _, _)", :fails},
    {"bytes_utf8(B, \"ab\"), sub_bytes(B, a, _, _, _)", {:error, "type_error(integer,a)"}},
    # Zusammenfügen
    {"bytes_utf8(A, \"ab\"), bytes_utf8(B, \"c\"), bytes_concat(A, B, C), bl(C, L)",
     ["A = '$bytes'(2), B = '$bytes'(1), C = '$bytes'(3), L = [97,98,99]"]},
    {"bytes_utf8(C, \"ab\"), findall(X-Y, (bytes_concat(A, B, C), bl(A, X), bl(B, Y)), L)",
     ["C = '$bytes'(2), L = [[]-[97,98],[97]-[98],[97,98]-[]]"]},
    {"bytes_utf8(C, \"abc\"), bytes_utf8(A, \"a\"), bytes_concat(A, B, C), bl(B, L)",
     ["A = '$bytes'(1), B = '$bytes'(2), C = '$bytes'(3), L = [98,99]"]},
    {"bytes_utf8(C, \"abc\"), bytes_utf8(B, \"bc\"), bytes_concat(A, B, C), bl(A, L)",
     ["A = '$bytes'(1), B = '$bytes'(2), C = '$bytes'(3), L = [97]"]},
    {"bytes_utf8(C, \"abc\"), bytes_utf8(A, \"b\"), bytes_concat(A, _, C)", :fails},
    {"bytes_concat(_, _, _)", {:error, "instantiation_error"}},
    {"bytes_list(A, [1]), bytes_list(B, [2,3]), bytes_concat_list([A,B,A], C), bl(C, L)",
     ["A = '$bytes'(1), B = '$bytes'(2), C = '$bytes'(4), L = [1,2,3,1]"]},
    {"bytes_concat_list([], C), bl(C, L)", ["C = '$bytes'(0), L = []"]},
    {"bytes_concat_list([a], _)", {:error, "type_error(bytes,a)"}},
    # Suchen
    {"bytes_utf8(B, \"abab\"), bytes_utf8(P, \"ab\"), findall(I, bytes_search(P, B, I), L)",
     ["B = '$bytes'(4), L = [0,2], P = '$bytes'(2)"]},
    {"bytes_utf8(B, \"aaaa\"), bytes_utf8(P, \"aa\"), findall(I, bytes_search(P, B, I), L)",
     ["B = '$bytes'(4), L = [0,1,2], P = '$bytes'(2)"]},
    {"bytes_utf8(B, \"ab\"), bytes_list(P, []), findall(I, bytes_search(P, B, I), L)",
     ["B = '$bytes'(2), L = [0,1,2], P = '$bytes'(0)"]},
    {"bytes_utf8(B, \"abab\"), bytes_utf8(P, \"ab\"), bytes_search(P, B, 2), \\+ bytes_search(P, B, 1)",
     :succeeds},
    {"bytes_utf8(B, \"ab\"), bytes_utf8(P, \"x\"), bytes_search(P, B, _)", :fails}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = TableCase.db(r, ~w(lists apply bytes))
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, "bl(B, L) :- bytes_list(B, L)."))
    {:ok, reader: r, db: db}
  end

  for {q, expect} <- @rows do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end

  @tag :tmp_dir
  test "Dateien und Streams", c do
    path = Path.join(c.tmp_dir, "d.bin")
    File.write!(path, <<0, 1, 2, 255, ?E, ?E>>)
    out = Path.join(c.tmp_dir, "o.bin")

    q =
      "read_file_to_bytes('#{path}', B), bl(B, L), " <>
        "open('#{out}', write, S, [type(binary)]), write_bytes(S, B), write_bytes(S, B), close(S), " <>
        "open('#{out}', read, I, [type(binary)]), get_bytes(I, 4, X), get_bytes(I, 100, Y), " <>
        "get_bytes(I, 3, Z), close(I), bl(X, LX), bl(Y, LY), bl(Z, LZ)"

    {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    assert a =~ "L = [0,1,2,255,69,69]"
    assert a =~ "LX = [0,1,2,255], LY = [69,69,0,1,2,255,69,69], LZ = []"
    assert File.read!(out) == <<0, 1, 2, 255, ?E, ?E, 0, 1, 2, 255, ?E, ?E>>

    assert {_, {:error, "existence_error(source_sink,nope)"}} =
             TableCase.run(c.reader, c.db, "read_file_to_bytes(nope, _)")

    assert {_, {:error, "permission_error(output,text_stream,user_output)"}} =
             TableCase.run(c.reader, c.db, "bytes_list(B, [1]), write_bytes(user_output, B)")
  end

  test "Kinder von library(concurrent) teilen große Folgen", c do
    db = TableCase.db(c.reader, ~w(lists apply bytes concurrent lambda))

    q =
      "length(L, 1000), maplist(=(7), L), bytes_list(B, L), " <>
        "concurrent_maplist(\\I^N^(sub_bytes(B, I, 10, _, S), bytes_length(S, N)), [0, 500, 990], Ns), " <>
        "concurrent_maplist(\\_^R^bytes_list(R, [1,2]), [a], [R]), bytes_list(R, LR)"

    {_, {:answers, [a]}} = TableCase.run(c.reader, db, q)
    assert a =~ "Ns = [10,10,10]"
    assert a =~ "LR = [1,2]"
  end
end
