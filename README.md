# prolog-ex
Elixir does Prolog!

Ein Prolog-Kern in Elixir:

- Unifikation über persistente Substitutions-Maps, eine zentrale `bind/3`
- Listen als native BEAM-Cons-Zellen (`'.'(H,T)` = `[H|T]`)
- Klauseln werden beim Laden in eine WAM-artige IR kompiliert
  (`lib/prolog_ex/compiler.ex`): Variablenklassifikation, Read-/Write-Modus
  im Kopf, Rumpf wird erst nach passendem Kopf gebaut
- explizite Ziel- und Choice-Point-Stacks mit Last-Call-Optimierung,
  vorberechneter Index nach dem ersten Argument
- Kompaktierung der Bindungen: konstanter Speicher bei endrekursiven Schleifen

## Loslegen

Voraussetzung: Elixir und GNU Prolog (`brew install gnu-prolog`). gprolog
dient nur als Term-Reader (Operator-Syntax → kanonische Terme); ausgeführt
wird alles in PrologEx.

```sh
mix prolog.build_reader              # Reader mit gplc übersetzen (einmalig;
                                     # GPLC=/pfad/zu/gplc falls nicht im PATH)
mix prolog                           # interaktiver Toplevel
mix prolog examples/demo.pl          # Datei laden, dann Toplevel
mix prolog examples/demo.pl -g main -q   # laden, main ausführen, Ende
cat prog.pl | mix prolog - -g main   # Programm von stdin
```

Im Toplevel:

```
?- [user].                 % Klauseln eintippen, Ende mit end_of_file. / Ctrl-D
|: app([], L, L).
|: app([H|T], L, [H|R]) :- app(T, L, R).
|: end_of_file.
true.

?- app(X, Y, [1,2]).
X = [], Y = [1, 2] ;       % ";" + Enter für die nächste Lösung
...
?- [examples/demo].        % Datei laden
?- listing(app/3).
?- halt.
```

Unterstützt: Klauseln, DCG (`-->`, `phrase/2,3`), Direktiven (`op/3`,
`dynamic/1`, `initialization/1`, beliebige Ziele), Reconsult (erneutes
Laden ersetzt Prädikate), `,` `;` `->` `\+` `!` `call/N`, `=` `\=` `==`
`\==`, `is` und Vergleiche (Ganzzahlen beliebiger Größe, Floats),
Typprüfungen, `write/1` `nl/0` `listing/0,1` `halt/0,1`.

Noch nicht: `assert`/`retract`, `catch`/`throw`, Ausgabe in
Operator-Schreibweise (`write` gibt derzeit kanonisch aus), große
Integer-Literale im Quelltext (Grenze von gprolog).

## Entwicklung

```sh
mix test                  # Tests (Integrationstests mit gprolog nur,
                          # wenn der Reader übersetzt ist)
mix run bench/bench.exs   # Speicher- und Laufzeitmessung
```
