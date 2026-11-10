defmodule PrologEx.DcgBytesTest do
  # library(dcg/bytes): DCGs über Byte-Folgen als faule Liste
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @grammar ~S"""
  gif(W, H) --> "GIF89a", u16le(W), u16le(H).
  gifv(V, W) --> "GIF", ( "87a", { V = 87 } ; "89a", { V = 89 } ), u16le(W), ... .
  bl(B, L) :- bytes_list(B, L).
  gifb(B) :- bytes_list(B, [0'G,0'I,0'F,0'8,0'9,0'a,64,1,200,0,1,2,3]).
  png(Cs) --> [137,80,78,71,13,10,26,10], chunks(Cs).
  chunks([T-Len|Cs]) --> u32be(Len), take(4, Tb), { bytes_latin1(Tb, Tc), atom_chars(T, Tc) },
     take(Len, _), u32be(_), !, chunks(Cs).
  chunks([]) --> eos.
  """

  @png "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

  @rows [
    # Präfix, Felder, der Rest wieder als Byte-Folge
    {"gifb(B), phrase_bytes(gif(W, H), B, R), bl(R, L)",
     ["B = '$bytes'(13), H = 200, L = [1,2,3], R = '$bytes'(3), W = 320"]},
    {"gifb(B), phrase_bytes(gif(_, _), B)", :fails},
    # Alternativen und ...//0: gewöhnliche Grammatik
    {"gifb(B), phrase_bytes(gifv(V, W), B)", ["B = '$bytes'(13), V = 89, W = 320"]},
    {"gifb(B), phrase_bytes(([_], seq(S), [3]), B), length(S, N)",
     ["B = '$bytes'(13), N = 11, S = [73,70,56,57,97,64,1,200,0,1,2]"]},
    # Sichten
    {"bytes_list(B, [71,200]), phrase_bytes((seq(L), eos), B, _, [as(latin1)])",
     ["B = '$bytes'(2), L = ['G','È']"]},
    {"bytes_list(B, [71,200]), phrase_bytes((seq(L), eos), B, _, [as(codes)])",
     ["B = '$bytes'(2), L = [71,200]"]},
    {"bytes_utf8(B, \"€ä\"), phrase_bytes((seq(L), eos), B, _, [as(utf8)])",
     ["B = '$bytes'(5), L = ['€',ä]"]},
    {"bytes_utf8(B, \"x€ä\"), phrase_bytes(([_], seq(_), [ä]), B, R, [as(utf8)]), bl(R, L)",
     ["B = '$bytes'(6), L = [], R = '$bytes'(0)"]},
    {"bytes_list(B, [0xFF]), phrase_bytes((seq(_), eos), B, _, [as(utf8)])",
     {:error, "representation_error(character)"}},
    {"bytes_list(B, [71]), phrase_bytes(seq(_), B, _, [as(foo)])",
     {:error, "domain_error(oneof([codes,latin1,utf8]),foo)"}},
    {"phrase_bytes(seq(_), foo)", {:error, "type_error(bytes,foo)"}},
    {"phrase_bytes(seq(_), _)", {:error, "instantiation_error"}},
    # Zahlen
    {"bytes_list(B, [0xFE, 0xFF, 1, 2, 3, 4]), phrase_bytes((s16le(A), u32be(C)), B), " <>
       "phrase_bytes((u16be(D), s8(E), s8(F), ...), B)",
     ["A = -2, B = '$bytes'(6), C = 16909060, D = 65279, E = 1, F = 2"]},
    {"bytes_list(B, [0, 0, 0, 0x80]), phrase_bytes(s32le(X), B), phrase_bytes(u32le(Y), B)",
     ["B = '$bytes'(4), X = -2147483648, Y = 2147483648"]},
    {"bytes_list(B, [71, 73]), phrase_bytes((u8(X), u8(Y)), B, _, [as(latin1)])",
     ["B = '$bytes'(2), X = 71, Y = 73"]},
    # über Blockgrenzen (4096)
    {"bytes_fill(10000, 0'x, B), phrase_bytes((take(5000, T), [C]), B, R), " <>
       "bytes_length(T, N), bytes_length(R, M)",
     ["B = '$bytes'(10000), C = 120, M = 4999, N = 5000, R = '$bytes'(4999), T = '$bytes'(5000)"]},
    {"bytes_fill(9000, 0'x, B), phrase_bytes((..., [0'x], eos), B)", :succeeds},
    # ein UTF-8-Zeichen über der Blockgrenze
    {"bytes_fill(4095, 0'x, X), bytes_utf8(E, \"€y\"), bytes_concat(X, E, B), " <>
       "phrase_bytes((seq(L), [Y]), B, R, [as(utf8)]), length(L, N), nth0(4095, L, C), bytes_length(R, M)",
     :succeeds},
    {"bytes_list(B, [1]), phrase_bytes(take(-1, _), B, _)",
     {:error, "domain_error(not_less_than_zero,-1)"}},
    # ein Binärformat: PNG in Chunks
    {"bytes_base64(B, '#{@png}'), phrase_bytes(png(Cs), B)",
     ["B = '$bytes'(70), Cs = ['IHDR'-13,'IDAT'-13,'IEND'-0]"]}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    PrologEx.Flags.set("double_quotes", {:atom, "codes"})
    db = TableCase.db(r, ~w(lists bytes dcg/bytes dcgs))
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, @grammar))
    {:ok, reader: r, db: db}
  end

  for {q, expect} <- @rows do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
