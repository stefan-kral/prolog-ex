defmodule PrologEx.SgmlTest do
  # library(sgml) und library(xpath): load_html/3 und load_xml/3 wie
  # Scryer Prolog (die Erwartungen sind Scryers Bäume, hier mit
  # cdata(atom) geschrieben), Optionen und xml_write/3, html_write/3 wie
  # SWI-Prolog (Erwartungen: SWIs Ausgaben)
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    prog = """
    :- use_module(library(sgml)).
    :- use_module(library(xpath)).
    :- use_module(library(lists)).
    :- use_module(library(swi)).
    load(K, Codes, E) :- atom_codes(A, Codes), atom_chars(A, Cs),
        O = [cdata(atom), attribute_value(atom)],
        ( K == html -> load_html(Cs, E, O) ; load_xml(Cs, E, O) ).
    w(D, O) :- with_output_to(chars(Cs), xml_write(current_output, D, O)), atom_chars(A, Cs), write(A).
    h(D, O) :- with_output_to(chars(Cs), html_write(current_output, D, O)), atom_chars(A, Cs), write(A).
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

  defp codes(s), do: inspect(String.to_charlist(s), charlists: :as_lists)

  @cases [
    {:html, "<html><head><title>Hello!</title></head></html>",
     "[element(html,[],[element(head,[],[element(title,[],['Hello!'])]),element(body,[],[])])]"},
    {:html, "hi", "[element(html,[],[element(head,[],[]),element(body,[],[hi])])]"},
    {:html, "<!DOCTYPE html><p>a<p>b",
     "[doctype(html),element(html,[],[element(head,[],[]),element(body,[],[element(p,[],[a]),element(p,[],[b])])])]"},
    {:html, "<ul><li>1<li>2</ul>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(ul,[],[element(li,[],['1']),element(li,[],['2'])])])])]"},
    {:html, "<br><img src=x alt='y'><input disabled>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(br,[],[]),element(img,[alt=y,src=x],[]),element(input,[disabled=''],[])])])]"},
    {:html, "<!-- c --><div>x &amp; &nbsp; &lt; &copy; &unknown; &#65; &#x80; &#0;</div>",
     "[comment(' c '),element(html,[],[element(head,[],[]),element(body,[],[element(div,[],['x &   < © &unknown; A € �'])])])]"},
    {:html, "<p>&notin &notit; &amp</p>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(p,[],['¬in ¬it; &'])])])]"},
    {:html, "<a title='&ampx &amp=1 &copy'>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(a,[title='&ampx &amp=1 ©'],[])])])]"},
    {:html, "<title>a<b>c</b></title><script>if (a<b) x='</p>';</script>",
     "[element(html,[],[element(head,[],[element(title,[],['a<b>c</b>']),element(script,[],['if (a<b) x=\\'</p>\\';'])]),element(body,[],[])])]"},
    {:html, "<table><tr><td>1<td>2</table>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(table,[],[element(tbody,[],[element(tr,[],[element(td,[],['1']),element(td,[],['2'])])])])])])]"},
    {:html, "<table>t<tr><td>1</tr>u</table>",
     "[element(html,[],[element(head,[],[]),element(body,[],[tu,element(table,[],[element(tbody,[],[element(tr,[],[element(td,[],['1'])])])])])])]"},
    {:html, "<p><table><tr><td>a</table>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(p,[],[element(table,[],[element(tbody,[],[element(tr,[],[element(td,[],[a])])])])])])])]"},
    {:html, "<!DOCTYPE html><p><table><tr><td>a</table>",
     "[doctype(html),element(html,[],[element(head,[],[]),element(body,[],[element(p,[],[]),element(table,[],[element(tbody,[],[element(tr,[],[element(td,[],[a])])])])])])]"},
    {:html, "<DIV CLASS=Foo>X</div>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(div,[class='Foo'],['X'])])])]"},
    {:html, "<p>a<div>b</div>c</p>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(p,[],[a]),element(div,[],[b]),c,element(p,[],[])])])]"},
    {:html, "<b><i>x</b>y</i>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(b,[],[element(i,[],[x])]),element(i,[],[y])])])]"},
    {:html, "<b>1<p>2</b>3</p>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(b,[],['1']),element(p,[],[element(b,[],['2']),'3'])])])]"},
    {:html, "<p><b>x<p>y</b>z",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(p,[],[element(b,[],[x])]),element(p,[],[element(b,[],[y]),z])])])]"},
    {:html, "<a href=1>x<a href=2>y</a>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(a,[href='1'],[x]),element(a,[href='2'],[y])])])]"},
    {:html, "<html><body>x</body></html> after",
     "[element(html,[],[element(head,[],[]),element(body,[],['x after'])])]"},
    {:html, "<title>t</title>  <meta x=1> x",
     "[element(html,[],[element(head,[],[element(title,[],[t]),'  ',element(meta,[x='1'],[]),' ']),element(body,[],[x])])]"},
    {:html, "<p>a</p><!--c--><p>b</p></body><!--d--></html><!--e-->",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(p,[],[a]),comment(c),element(p,[],[b])]),comment(d)]),comment(e)]"},
    {:html, "<?php x ?><p>",
     "[comment('?php x ?'),element(html,[],[element(head,[],[]),element(body,[],[element(p,[],[])])])]"},
    {:html, "<select><b>x</b><option>a<option>b</select>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(select,[],[x,element(option,[],[a]),element(option,[],[b])])])])]"},
    {:html, "<pre>\nx</pre><textarea>\ny</textarea>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(pre,[],[x]),element(textarea,[],[y])])])]"},
    {:html, "<svg viewBox='0 0 1 1'><path d='M0'/><g><rect/></g></svg><p>x",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(svg,[viewBox='0 0 1 1'],[element(path,[d='M0'],[]),element(g,[],[element(rect,[],[])])]),element(p,[],[x])])])]"},
    {:html, "<p z=1 a=2 m=3 b=4 a=9>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(p,[a='2',b='4',m='3',z='1'],[])])])]"},
    {:html, "<form><div></form><ul>x</ul>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(form,[],[element(div,[],[element(ul,[],[x])])])])])]"},
    {:html, "<dl><dt>a<dd>b<dt>c</dl>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(dl,[],[element(dt,[],[a]),element(dd,[],[b]),element(dt,[],[c])])])])]"},
    {:html, "<h1>a<h2>b</h2>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(h1,[],[a]),element(h2,[],[b])])])]"},
    {:html, "<table></dl><h2></h2><pre></table><span/>",
     "[element(html,[],[element(head,[],[]),element(body,[],[element(h2,[],[]),element(pre,[],[]),element(table,[],[]),element(span,[],[])])])]"},
    {:html, "<noscript><p>x</p></noscript>",
     "[element(html,[],[element(head,[],[element(noscript,[],['<p>x</p>'])]),element(body,[],[])])]"},
    {:html, "<frameset><frame></frameset>",
     "[element(html,[],[element(head,[],[]),element(frameset,[],[element(frame,[],[])])])]"},
    {:xml, "<a>x</a>", "[element(a,[],[x])]"},
    {:xml,
     "<?xml version=\"1.0\"?>\n<!-- c --><a  b='1' c=\"&lt;&amp;&#65;&#x42;\">t<b/>u<!--com-->v<?pi data?>w<![CDATA[<x>]]>y</a>\n<!-- after -->",
     "[element(a,[b='1',c='<&AB'],[t,element(b,[],[]),u,element('',[],[]),v,element('',[],[]),'w<x>y'])]"},
    {:xml, "<n:a xmlns:n=\"urn:x\" xmlns=\"urn:d\" n:at=\"1\" at2=\"2\"><b>1</b></n:a>",
     "[element(a,[at='1',at2='2'],[element(b,[],['1'])])]"},
    {:xml, "<a>\n  <b> x </b>\n</a>", "[element(a,[],['\\n  ',element(b,[],[' x ']),'\\n'])]"},
    {:xml, "<a b='x\ny\tz'/>", "[element(a,[b='x y z'],[])]"},
    {:xml, "<a>x\r\ny</a>", "[element(a,[],['x\\ny'])]"},
    {:xml, "<a><![CDATA[]]></a>", "[element(a,[],[''])]"},
    {:xml, "<a>&nbsp;</a>", "fail"},
    {:xml, "<!DOCTYPE a [<!ENTITY e \"EE\">]><a>&e;</a>", "fail"},
    {:xml, "<a><b></a>", "fail"},
    {:xml, "<a></a><b/>", "fail"},
    {:xml, "<a>&#0;</a>", "fail"},
    {:xml, "<a x='1' x='2'/>", "fail"},
    {:xml, "<a>]]></a>", "fail"},
    {:xml, "<p:a/>", "fail"},
    {:xml, "<a/>", "[element(a,[],[])]"}
  ]

  for {kind, text, expect} <- @cases do
    test "load_#{kind}(#{inspect(text)})", c do
      q = "load(#{unquote(kind)}, #{codes(unquote(text))}, E)"

      if unquote(expect) == "fail" do
        check(c, q, :fails)
      else
        check(c, q <> ", E == " <> unquote(expect), :succeeds)
      end
    end
  end

  test "Vorgabe wie Scryer: Text und Attributwerte als Zeichenlisten", c do
    check(
      c,
      "atom_chars('<a href=x>hi</a>', Cs), load_html(Cs, [element(html, _, [_, element(body, _, [E])])], []), " <>
        "E == element(a, [href=[x]], [[h,i]])",
      :succeeds
    )

    check(
      c,
      "atom_chars('<a>x<b/></a>', Cs), load_xml(Cs, E, []), E == [element(a, [], [[x], element(b, [], [])])]",
      :succeeds
    )

    check(c, "load_html([], E, [])", ["E = []"])
    check(c, "atom_chars('<a/>', Cs), load_xml(Cs, E, [cdata(codes)])", :succeeds)
  end

  test "Quellen: stream(S), file(F); Fehler wie Scryer", c do
    path =
      Path.join(System.tmp_dir!(), "prolog_ex_sgml_#{System.unique_integer([:positive])}.xml")

    File.write!(path, "<r><x>é</x></r>")

    try do
      check(c, "load_xml(file('#{path}'), E, [cdata(atom)])", [
        "E = [element(r,[],[element(x,[],[é])])]"
      ])

      check(c, "atom_chars('#{path}', F), load_xml(file(F), E, [cdata(atom)])", :succeeds)

      check(
        c,
        "open('#{path}', read, S), load_xml(stream(S), E, [cdata(atom)]), close(S), E = [element(r, _, _)]",
        :succeeds
      )
    after
      File.rm(path)
    end

    check(
      c,
      "catch(load_xml(file('/nonexistent/x.xml'), _, []), error(E, _), true)",
      {:any, [["E = existence_error(source_sink,'/nonexistent/x.xml')"]]}
    )

    check(c, "catch(load_html(_, _, []), error(E, _), true)", ["E = instantiation_error"])

    check(c, "catch(load_html(foo, _, []), error(E, _), true)", [
      "E = domain_error(sgml_source,foo)"
    ])

    check(c, "catch(load_html([a|b], _, []), error(E, _), true)", :succeeds)
  end

  test "space/1 wie SWI", c do
    t = "<a>\\n  <b>  x   y \\n z </b>\\n  <c/>  t  <d>\\n</d></a>"

    for {mode, expect} <- [
          {"preserve",
           "[element(a,[],['\\n  ',element(b,[],['  x   y \\n z ']),'\\n  ',element(c,[],[]),'  t  ',element(d,[],['\\n'])])]"},
          {"sgml",
           "[element(a,[],[element(b,[],['  x   y \\n z ']),element(c,[],[]),'  t  ',element(d,[],[])])]"},
          {"default",
           "[element(a,[],[element(b,[],[' x y z ']),element(c,[],[]),' t ',element(d,[],[])])]"},
          {"remove",
           "[element(a,[],[element(b,[],['x y z']),element(c,[],[]),t,element(d,[],[])])]"}
        ] do
      check(
        c,
        "atom_chars('#{t}', Cs), load_xml(Cs, E, [space(#{mode}), cdata(atom)]), E == #{expect}",
        :succeeds
      )
    end

    check(
      c,
      "atom_chars('<b>\\n\\nx\\n\\n</b>', Cs), load_xml(Cs, E, [space(default), cdata(atom)])",
      ["Cs = [<,b,>,'\\n','\\n',x,'\\n','\\n',<,/,b,>], E = [element(b,[],[' x '])]"]
    )

    check(c, "catch(load_xml([a], _, [space(foo)]), error(E, _), true)", [
      "E = domain_error(space,foo)"
    ])
  end

  test "xpath/3 (Scryers library(xpath))", c do
    doc =
      "<html><head><title>Hello!</title></head><body><ul><li class='a'>one</li><li class='b'>two <b>2</b></li>" <>
        "<li>  three  3 </li></ul><a href='x.pl'>X</a><p>42</p><p>3.5</p></body></html>"

    pre = "atom_codes(A, #{codes(doc)}), atom_chars(A, Cs), load_html(Cs, D, []), "
    check(c, pre <> "findall(T, xpath(D, '//'(title(text(atom))), T), L)", {:any, [:succeeds]})

    check(
      c,
      pre <>
        "findall(T, xpath(D, '//'(li(normalize_space)), T), L), L == [[o,n,e],[t,w,o,' ','2'],[t,h,r,e,e,' ','3']]",
      :succeeds
    )

    check(c, pre <> "findall(T, xpath(D, '//'(li('@'(class))), T), L), L == [[a],[b]]", :succeeds)
    check(c, pre <> "findall(T, xpath(D, '//'(p(number)), T), L), L == [42, 3.5]", :succeeds)

    check(
      c,
      pre <>
        "findall(T, xpath(D, '//'(li(last, text)), T), L), L == [[' ',' ',t,h,r,e,e,' ',' ','3',' ']]",
      :succeeds
    )

    check(c, pre <> "xpath_chk(D, '//'(title(text(atom))), T), T == 'Hello!'", :succeeds)
  end

  @writes [
    {"w(element(a, [], []), [])", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\n<a/>"},
    {"w(element(a, [], [x]), [header(false)])", "<a>x</a>"},
    {~S|w(element(a, [b=1, c='x"<&>\n\ty'], ['t<&>\r"\'']), [header(false)])|,
     ~S|<a b="1" c="x&quot;&lt;&amp;>&#xA;&#x9;y">t&lt;&amp;&gt;&#xD;"'</a>|},
    {~S|w(element(a, [], [element(b, [], [x]), element(c, [], []), '  \n ', element(d, [], [element(e, [], [y])])]), [header(false)])|,
     "<a>\n  <b>x</b>\n  <c/>\n  <d>\n    <e>y</e>\n  </d>\n</a>"},
    {"w(element(a, [], [text1, element(b, [], [x]), more]), [header(false)])",
     "<a>text1<b>x</b>more</a>"},
    {"w([element(a, [], []), element(b, [], [])], [header(false)])", "<a/><b/>"},
    {"w(element(a, [aaaaaaaaaaaaaaa=bbbbbbbbbbbbbbbbbbbbbb, cccccccccccccccc=dddddddddddddddddddd, e=f], [element(x,[],[])]), [header(false)])",
     "<a\n    aaaaaaaaaaaaaaa=\"bbbbbbbbbbbbbbbbbbbbbb\"\n    cccccccccccccccc=\"dddddddddddddddddddd\"\n    e=\"f\">\n  <x/>\n</a>"},
    {"w(element(a, [], [element(b, [], [element(c, [], [deep])])]), [header(false), indent(4)])",
     "    <a>\n      <b>\n\t<c>deep</c>\n      </b>\n    </a>"},
    {"w(element(a, [], [element(b, [], [])]), [header(false), layout(false)])", "<a><b/></a>"},
    {"w(element(a, [], [pi('php x'), y]), [header(false)])", "<a><?php x?>y</a>"},
    {"w(element(a, [k=[v1,v2,v3]], []), [header(false)])", "<a k=\"v1 v2 v3\"/>"},
    {"w(element(a, [], [42]), [header(false)])", "<a>42</a>"},
    {"w(element(a, [], []), [header(false), doctype(a)])", "<!DOCTYPE a []>\n\n<a/>"},
    {"w(element(a, [], []), [header(false), public('-//X//Y'), system('a.dtd')])",
     "<!DOCTYPE a PUBLIC \"-//X//Y\" \"a.dtd\">\n\n<a/>"},
    # Text als Zeichenliste (Scryers Darstellung)
    {"w(element(a, [href=[x,'<']], [[h,i,'&'], element(b, [], [])]), [header(false)])",
     "<a href=\"x&lt;\">hi&amp;<b/></a>"},
    {"h(element(html, [], [element(head, [], [element(title, [], ['T'])]), element(body, [], [element(p, [], [x]), element(br, [], []), element(script, [], ['a<b && c']), element(div, [], [])])]), [])",
     "<html>\n  <head>\n    <title>T</title>\n  </head>\n  <body>\n    <p>x</p>\n    <br>\n    <script>a<b && c</script>\n    <div></div>\n  </body>\n</html>"},
    {"h(element(p, [class=x], ['a&b<c>']), [])", "<p class=\"x\">a&amp;b&lt;c&gt;</p>"},
    {"h(element(html, [version='4.0'], []), [])",
     "<!DOCTYPE HTML PUBLIC \"4.0\">\n\n<html version=\"4.0\"></html>"}
  ]

  for {q, out} <- @writes do
    test "Schreiben: #{q}", c do
      check(c, unquote(q), {:out, unquote(out)})
    end
  end

  test "Fehler beim Schreiben", c do
    check(
      c,
      "catch(xml_write(current_output, element(a, [], [foo(x)]), [header(false)]), error(E, _), true)",
      {:out, "<a>", ["E = type_error(sgml_content,foo(x))"]}
    )

    check(c, "catch(w(element(a, [], []), [bogus(1)]), error(E, _), true)", [
      "E = domain_error(xml_write_option,bogus(1))"
    ])

    check(
      c,
      "catch(xml_write(current_output, _, []), error(E, _), true)",
      {:any,
       [{:out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\n", ["E = instantiation_error"]}]}
    )
  end

  test "Rundreise: laden, schreiben, wieder laden", c do
    check(
      c,
      "atom_chars('<r a=\"1\"><x>t&amp;u</x><y/></r>', Cs), load_xml(Cs, D, []), " <>
        "with_output_to(chars(Out), xml_write(current_output, D, [header(false), layout(false)])), " <>
        "load_xml(Out, D2, []), D == D2, atom_chars(A, Out)",
      :succeeds
    )
  end
end
