/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Predicates for parsing HTML and XML documents.
   Written 2020-2022 by Markus Triska (triska@metalevel.at)
   Part of Scryer Prolog.

   Angepasst für PrologEx: '$load_html'/3 und '$load_xml'/3 (bei Scryer in
   Rust: html5ever bzw. roxmltree) sind '$sgml_load'/4 in Elixir
   (PrologEx.Sgml), das Streams und Dateien selbst liest. Zusätzlich:
   file(Name) auch mit einem Atom; die Optionen cdata/1,
   attribute_value/1 und space/1 wie bei SWI-Prolog; xml_write/2,3 und
   html_write/2,3 wie SWIs library(sgml_write).
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

/** Predicates for parsing HTML and XML documents.

Currently, two predicates are provided:

  -  `load_html(+Source, -Es, +Options)`
  -  `load_xml(+Source, -Es, +Options)`

These predicates parse HTML and XML documents, respectively.

Source must be one of:

  - a list of characters with the document contents
  - `stream(S)`, specifying a stream S from which to read the content
  - `file(Name)`, where Name is a list of characters specifying a file name.

Es is unified with the abstract syntax tree of the parsed document,
represented as a list of elements where each is of the form:

  * a list of characters, representing text

  * `element(Name, Attrs, Children)`

    - `Name`, an atom, is the name of the tag

    - `Attrs` is a list of `Key=Value` pairs:
      `Key` is an atom, and `Value` is a list of characters

    - `Children` is a list of elements as specified here.

  * `doctype(Name)`

  * `comment(Comment)`

  * `processing_instruction(Target, Data)`

  * `fragment(Children)`

Options (PrologEx, wie SWI-Prolog):

  - `cdata(Type)`: Text als `chars` (Vorgabe), `atom`, `codes` oder
    `string` (hier nach dem Flag double_quotes)
  - `attribute_value(Type)`: ebenso für Attributwerte
  - `space(Mode)`: `preserve` (Vorgabe), `sgml`, `default` oder `remove`

`xml_write(+Stream, +DOM, +Options)` und `html_write(+Stream, +DOM,
+Options)` schreiben ein DOM wie SWI-Prolog (Optionen `header/1`,
`layout/1`, `indent/1`, `doctype/1`, `public/1`, `system/1`, `nsmap/1`,
`cleanns/1`, `net/1`); Text darf Atom, Zeichen- oder Codeliste sein.

Example:

```
   ?- load_html("<html><head><title>Hello!</title></head></html>", Es, []).
```

Yielding:

```
      Es = [element(html,[],
             [element(head,[],
               [element(title,[],
                 ["Hello!"])]),
              element(body,[],[])])].
```

`library(xpath)` provides convenient reasoning about parsed documents.
For example, to fetch the title of the document above, we can use:

```
   ?- load_html("<html><head><title>Hello!</title></head></html>", Es, []),
      xpath(Es, //title(text), T).
```

Yielding `T = "Hello!"`.

Use `http_open/3` from `library(http/http_open)` to read answers from
web servers via streams.
*/

:- module(sgml, [load_html/3,
                 load_xml/3,
                 xml_write/2,
                 xml_write/3,
                 html_write/2,
                 html_write/3]).

:- use_module(library(iso_ext)).
:- use_module(library(error)).
:- use_module(library(dcgs)).
:- use_module(library(pio)).
:- use_module(library(charsio)).

load_html(Source, Es, Options) :-
        must_be_source(Source, load_html/3),
        must_be(list, Options),
        load_structure_(Source, Es, Options, html).
load_xml(Source, Es, Options) :-
        must_be_source(Source, load_xml/3),
        must_be(list, Options),
        load_structure_(Source, Es, Options, xml).

must_be_source(Source, Context) :-
        (   var(Source) -> instantiation_error(Context)
        ;   is_sgml_source(Source) -> true
        ;   domain_error(sgml_source, Source, Context)
        ).

is_sgml_source(file(Fs)) :- ( atom(Fs) -> true ; must_be(chars, Fs) ).
is_sgml_source(stream(_)).
is_sgml_source([]).
is_sgml_source([C|Cs]) :- must_be(chars, [C|Cs]).

load_structure_([], [], _, _).
load_structure_([C|Cs], [E|Es], Options, What) :-
        '$sgml_load'(What, text([C|Cs]), [E|Es], Options).
load_structure_(file(Fs), [E|Es], Options, What) :-
        '$sgml_load'(What, file(Fs), [E|Es], Options).
load_structure_(stream(Stream), [E|Es], Options, What) :-
        '$sgml_load'(What, stream(Stream), [E|Es], Options).

%% xml_write(+Stream, +DOM, +Options)
%
% DOM als XML schreiben, wie SWI-Prolog.
xml_write(DOM, Options) :-
        '$sgml_write'(xml, current_output, DOM, Options).
xml_write(Stream, DOM, Options) :-
        '$sgml_write'(xml, Stream, DOM, Options).

%% html_write(+Stream, +DOM, +Options)
%
% DOM als HTML schreiben, wie SWI-Prolog.
html_write(DOM, Options) :-
        '$sgml_write'(html, current_output, DOM, Options).
html_write(Stream, DOM, Options) :-
        '$sgml_write'(html, Stream, DOM, Options).
