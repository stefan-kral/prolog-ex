defmodule PrologEx.AbnfTest do
  # library(serialization/abnf) aus Scryer: die Kernregeln von RFC 5234
  # (Anhang B.1) als DCGs über Zeichen
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r, db: TableCase.db(r, ~w(serialization/abnf dcgs))}
  end

  defp ok?(c, q) do
    case TableCase.run(c.reader, c.db, q) do
      {_, {:answers, [_ | _]}} -> true
      {_, {:answers, []}} -> false
    end
  end

  # phrase(NT, Zeichen) mit den Zeichen als Liste von Codes
  defp p(nt, text),
    do:
      "atom_codes(A, [#{Enum.join(String.to_charlist(text), ",")}]), atom_chars(A, Cs), phrase(#{nt}, Cs)"

  test "jede Kernregel nimmt, was RFC 5234 sagt, und nichts sonst", c do
    yes = [
      {"abnf_alpha(_)", "q"},
      {"abnf_alpha(_)", "Q"},
      {"abnf_bit(_)", "1"},
      {"abnf_char(_)", "~"},
      {"abnf_cr", "\r"},
      {"abnf_crlf", "\r\n"},
      {"abnf_ctl(_)", <<127>>},
      {"abnf_digit(_)", "7"},
      {"abnf_dquote", "\""},
      {"abnf_hexdig(_)", "F"},
      {"abnf_htab", "\t"},
      {"abnf_lf", "\n"},
      {"abnf_lwsp", " \r\n\t"},
      {"abnf_octet(_)", "ÿ"},
      {"abnf_sp", " "},
      {"abnf_vchar(_)", "!"},
      {"abnf_wsp", "\t"}
    ]

    no = [
      {"abnf_alpha(_)", "1"},
      {"abnf_bit(_)", "2"},
      {"abnf_char(_)", <<0>>},
      {"abnf_ctl(_)", "a"},
      {"abnf_digit(_)", "a"},
      {"abnf_hexdig(_)", "g"},
      {"abnf_lwsp", "\r\n"},
      {"abnf_octet(_)", "Ā"},
      {"abnf_vchar(_)", " "},
      {"abnf_wsp", "\n"}
    ]

    for {nt, t} <- yes, do: assert(ok?(c, p(nt, t)), "#{nt} #{inspect(t)}")
    for {nt, t} <- no, do: refute(ok?(c, p(nt, t)), "#{nt} #{inspect(t)}")
  end

  test "Werte: Ziffern bleiben Zeichen, das Oktett ist das Zeichen", c do
    assert {_, {:answers, [a]}} =
             TableCase.run(
               c.reader,
               c.db,
               p("(abnf_alpha(X), abnf_digit(D), abnf_hexdig(H), abnf_octet(O))", "x7Fé")
             )

    assert a =~ "D = '7'"
    assert a =~ "H = 'F'"
    assert a =~ "O = é"
    assert a =~ "X = x"
  end
end
