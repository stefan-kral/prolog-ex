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

Voraussetzung: Elixir. Gelesen und ausgeführt wird alles in Elixir. GNU
Prolog (`brew install gnu-prolog`) ist optional: ein Teil der Tests
vergleicht Reader und Writer mit gprolog.

```sh
mix compile                          # übersetzen (mit gplc auch den
                                     # Vergleichs-Reader, siehe unten)
mix prolog                           # interaktiver Toplevel
mix prolog examples/demo.pl          # Datei laden, dann Toplevel
mix prolog examples/demo.pl -g main -q   # laden, main ausführen, Ende
cat prog.pl | mix prolog - -g main   # Programm von stdin
```

Bauen: `mix compile` übersetzt neben dem Elixir-Code auch den gprolog-Reader
(`priv/gprolog/reader.pl`, nur noch Vergleichsorakel für Tests; fehlt
`gplc`, gibt es nur eine Warnung), sobald die Quelle neuer ist als das Programm –
also auch bei `mix test`, `mix run` und `mix prolog`. `mix clean` löscht
beides, `mix rebuild` baut alles neu (wie `make clean && make all`).
`mix prolog.build_reader` übersetzt nur den Reader, immer.

Zeilenbearbeitung und Verlauf (↑/↓, Ctrl-R, …) bekommt man mit
[rlwrap](https://github.com/hanslub42/rlwrap) (`brew install rlwrap`):

```sh
rlwrap mix prolog
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

**Antworten seitenweise:** Passiert beim Berechnen einer Antwort kein
Seiteneffekt (Ausgabe, `assert`, `bb_put`, Flags, `op/3`, Zufall, …), rechnet
der Toplevel die nächste schon voraus und zeigt sie gleich mit – bis eine
Bildschirmseite voll ist. Gefragt wird erst danach (`;` nächste Seite,
Enter Ende); zeigt das Vorausrechnen, dass nichts mehr kommt, endet die
Antwort gleich mit `.`. Vorausgerechnet wird in einem eigenen Prozess mit
Zeitgrenze (0,5 s) und gefangener Ausgabe: passiert dabei doch etwas oder
dauert es zu lange, wird es verworfen und wie gewohnt gefragt. Nach einer
Antwort mit Seiteneffekt wird nie vorausgerechnet. Flag `answer_chunk`:
`auto` (Standard: eine Seite), `N` (höchstens N Antworten), `1` (einzeln wie
früher). Ohne Terminal (Eingabe aus Datei/Pipe) immer einzeln.

**Ctrl-C führt zu iex:** `bin/iprolog` startet iex mit `+Bc` – Ctrl-C
unterbricht dann nur die laufende Anfrage (statt des BREAK-Menüs der BEAM),
und man ist in iex. `repl` startet bzw. setzt den Toplevel fort, mit
derselben Sitzung (Datenbank, Flags, Operatoren, … – Stand nach der letzten
fertigen Anfrage); `halt.` führt auch zurück zu iex, `reset_session` beginnt
neu. Von Hand: `iex --erl "+Bc" -S mix`, dann `PrologEx.Toplevel.repl()`.
Offene Datei-Streams überstehen den Abbruch nicht.

Unterstützt: Klauseln, DCG (`-->`, `phrase/2,3`), Direktiven (`op/3`,
`dynamic/1`, `initialization/1`, `multifile/1`, `discontiguous/1`,
`include/1`, bedingte Übersetzung mit `if/1`, `elif/1`, `else/0`,
`endif/0`, beliebige Ziele), Reconsult (erneutes
Laden ersetzt Prädikate), `,` `;` `->` `*->` (soft cut wie SWI; `if/3` wie SICStus: alle Lösungen der Bedingung, Else nur ohne Lösung) `\\+` `!` `call/N` `time/1` (meldet nach jeder Lösung die Zeit, die das Ziel bisher
tatsächlich gelaufen ist – die Pause bis zum `;` im Toplevel zählt nicht mit),
`=` `\\=` `==` `\\==`, Standardordnung (`@<` `@>` `@=<` `@>=` `compare/3`,
`sort/2` `msort/2` `keysort/2`; wie ISO 7.2 alle Floats vor allen Integern:
`7.0 @< 1`), `term_variables/2`, `subsumes_term/2`, `is` und Vergleiche (Ganzzahlen beliebiger Größe,
Floats; alle ISO-Funktionen dazu die üblichen aus SWI/SICStus: `sin` … `atanh`,
`exp`, `log/1,2`, `log2`, `atan/2`, `atan2`, `copysign`, `div`, `gcd`, `msb`,
`lsb`, `popcount`, `xor`, `float_integer_part`, `random/1`, `random_float`,
`cputime`, `realtime`, `epsilon`, …; Fehler nach ISO wie
`evaluation_error(zero_divisor)`, siehe `PrologEx.Arith`; `is/2` und
Vergleiche im Klauselrumpf übersetzt der Compiler in einen Codebaum, statt
den Ausdruck bei jedem Aufruf als Term zu bauen – 4–13 % schneller,
gleiche Werte und Fehler), Typprüfungen, `functor/3`, `=../2`, `append/3`, `length/2`, `member/2`, `between/3`, `select/3`, `permutation/2`, `memberchk/2`, `last/2`, `reverse/2`,
`proper_length/2`, `sum_list/2`, `max_list/2`, `min_list/2`, `max_member/2`,
`min_member/2`, `delete/3`, `list_to_set/2`, `nextto/3`, `subtract/3`,
`intersection/3`, `union/3`, `include/3`, `exclude/3`, `partition/4`, `foldl/4..6`,
`same_length/2`, `'$skip_list'(Len, List, Rest)` (wie SWI: überspringt
Len Zellen; Rest ist `[]`, eine Variable, ein anderer Term oder bei einer
zyklischen Liste eine Zelle im Zyklus – Brents Zykluserkennung, terminiert
immer; dieselbe Funktion liegt `length/2` und Co. zugrunde), aus SICStus' `library(lists)`: `one_longer/2`,
`shorter_list/2`, `keys_and_values/3`, `transpose/2` (rechteckig, in beide
Richtungen; leere Matrizen – keine Zeile oder keine Spalte – scheitern),
`partition/5` (`call(P, X, R)`, R ∈ {`<`,`=`,`>`}), `chain/2`,
`memberd/2` (Neumerkel: wie `member/2` mit `dif/2` in der Rekursion, also
ohne doppelte Antworten; in Elixir, ohne Choice Point, sobald X mit einem
Element identisch ist – bei gebundenem X etwa 18-mal so schnell wie die
Prolog-Fassung `library(memberd_pl)`, `mix run bench/memberd_bench.exs`), `nth0/3,4`, `nth1/3,4`, `maplist/2..8`, `succ/2`, `call_nth/2`,
`findall/3,4`, `forall/2`, `once/1`, `ignore/1`, `plus/3`, `numbervars/3`,
`atomic_list_concat/2,3` (auch zerlegen: `atomic_list_concat(L, '-', 'a-b')`),
`setup_call_cleanup/3` (wie SWI und der WG17-Vorschlag: Cleanup sofort bei
deterministischem Ziel, sonst bei Fehlschlag, Ausnahme oder sobald ein Cut –
auch `once/1`, `->`, `\\+` – die offenen Choice Points abschneidet; beim
Abbruch einer Anfrage im Toplevel nach der ersten Antwort läuft es noch nicht), `exists_file/1`, `exists_directory/1`, `delete_file/1` (wie SWI), `findnsols/4,5`, `countall/2`, `bagof/3`, `setof/3` (ISO;
`V^G`; Gruppen nach Zeugen sortiert wie SICStus/SWI), `=@=/2`, `\=@=/2`, `arg/3`, `copy_term/2`,
`current_prolog_flag/2`, `set_prolog_flag/2` (u. a. `double_quotes`, `unknown`,
`occurs_check`), `unify_with_occurs_check/2`, `acyclic_term/1`, `clause/2`,
`current_predicate/1`, `assert/1` `asserta/1` `assertz/1` `retract/1`
`retractall/1` `abolish/1` `dynamic/1`, `number_chars/2`, `number_codes/2` (ISO; Leerraum und Kommentare davor erlaubt, `0x`/`0o`/`0b`/`0'c`, Zifferngruppen),
`atom_length/2`, `atom_concat/3`, `sub_atom/5`, `atom_chars/2`, `atom_codes/2`,
`char_code/2` (ISO, streng getypt, zählen Zeichen statt Bytes), `atom_number/2`,
`op/3`, `current_op/3` (ISO; Operatoren sind global und gelten ab dem nächsten
gelesenen Term), `false/0`, `repeat/0,1`, `numlist/2,3`,
`write/1` `nl/0` `listing/0,1` `halt/0,1`.

Datenbank: Prädikate aus `assert` sind dynamisch, geladene statisch (außer
mit `:- dynamic`); Änderungen an statischen ergeben `permission_error`.
Es gilt die *logical update view* (ISO): ein laufender Aufruf sieht den
Stand von seinem Start. `assert` ist O(1); der Index wird beim nächsten
Aufruf erweitert statt neu gebaut, `retract` der ersten Klausel ist O(1).
Abwechselnd `assertz` und Aufruf bleibt quadratisch (Kopie der
Klauselliste, klein: 8000 Runden ≈ 0,4 s).

Zahlen im Quelltext: Zifferngruppen wie in SWI (`1_000_000`, nach `_` darf
Leerraum folgen) und Ganzzahl-Literale beliebiger Größe (auch `0x…`).

Ausnahmen: `catch/3`, `throw/1`; alle Fehler der Builtins sind ISO-Terme
`error(Formal, Kontext)` (`type_error`, `instantiation_error`,
`existence_error`, `permission_error`, `domain_error`, `evaluation_error`, …)
und fangbar. Nicht Gefangenes meldet der Toplevel als `Fehler: …`.

## Ein- und Ausgabe: Streams

ISO 8.11–8.14 – Streams sind `'$stream'(N)`, dazu die Aliase `user_input`,
`user_output`, `user_error` und eigene (`alias(A)`):

  * Streams: `open/3,4` (`type(text|binary)`, `alias/1`, `reposition/1`,
    `eof_action(error|eof_code|reset)`, `encoding(utf8)`), `close/1,2`,
    `current_input/1`, `current_output/1`, `set_input/1`, `set_output/1`,
    `flush_output/0,1`, `stream_property/2`, `at_end_of_stream/0,1`,
    `set_stream_position/2`; `line_count/2`, `line_position/2`,
    `character_count/2`.
  * Zeichen und Bytes: `get_char`, `peek_char`, `put_char`, `get_code`,
    `peek_code`, `put_code`, `get_byte`, `peek_byte`, `put_byte` (je /1 und /2),
    `nl/0,1`. Textstreams sind UTF-8.
  * Terme: `read/1,2`, `read_term/2,3` (`variables/1`, `variable_names/1`,
    `singletons/1`), `write/2`, `writeq/2`, `print/2`, `write_canonical/2`,
    `write_term/3`; `term_to_atom/2`, `read_term_from_atom/3` (SWI).
  * Alle Ausgaben (`write/1`, `nl/0`, `listing`, …) gehen auf den aktuellen
    Ausgabestrom.
  * Fehler wie ISO, z. B. `permission_error(input, binary_stream, S)`,
    `permission_error(input, past_end_of_stream, S)`,
    `existence_error(source_sink, F)`.

```prolog
?- open('t.pl', write, S), writeq(S, f('a b', X)), write(S, '.'), nl(S), close(S).
?- open('t.pl', read, S), read_term(S, T, [variable_names(V)]), close(S).
T = f('a b', _A), V = ['X'=_A].
```

`read/1` liest genau einen Term: das Ende (der einzelne `.` vor Leerraum)
findet ein kleiner Scanner, den Term selbst liest `PrologEx.Parser` (siehe
„Reader“ unten). So lassen sich `read/2` und `get_char/2` auf demselben
Stream mischen. Gelesene Direktiven (`:- op(...)`) werden dabei nicht
ausgeführt.

## Formatierte Ausgabe: `format/1,2,3`

Nach PIP 0110 (Prolog Implementers Forum, "Formatted output"), wie SWI,
SICStus und GNU Prolog im gemeinsamen Kern; alle gut 1 100 Fälle aus Logtalks
Konformitätstests bestehen.

```prolog
?- format("~w und ~q~n", ['A b', 'A b']).
A b und 'A b'
?- format("~t~w~10|~t~d~8+~n", [name, 42]).
      name      42
?- format("~2f ~e ~D ~16r~n", [2.675, 1.0e-3, 1234567, 255]).
2.67 1.000000e-03 1,234,567 ff
```

  * Terme `~w ~p ~q ~k ~W`, Text `~a ~c ~s`, Zahlen `~d ~D ~r ~R ~e ~E ~f
    ~g ~G` (Argumente sind arithmetische Ausdrücke), `~n ~N ~i ~~`,
    Spalten `~t ~| ~+` mit Füllzeichen `` ~`ct ``; Zahl vor der Direktive
    als Ziffern, `*` (nächstes Argument) oder `` `c ``.
  * `~e ~f ~g` wie C `printf`: gerundet wird der exakte Binärwert, bei
    Gleichstand zur geraden Ziffer (`~2f` von 2.675 gibt 2.67, `~0f` von
    2.5 gibt 2) – mit 20 000 Zufallswerten gegen C geprüft.
  * Spalten beginnen dort, wo der Stream gerade steht.
  * Die Ausgabe entsteht ganz im Speicher: ein Fehler unterwegs schreibt
    nichts. Formatfehler sind `domain_error(format, Grund)`.
  * `~p` und `print/1,2` fragen ein benutzerdefiniertes `portray/1` für
    jeden Teilterm.

## Schnell speichern: `fast_write/2`, `fast_read/2`

Wie SWI (`fast_write/2`, `fast_read/2`, `fast_term_serialized/2`) und SICStus
(`library(fastrw)`, dazu `fast_write/1`, `fast_read/1`): Terme als
Datensätze im External Term Format der BEAM auf einen Binärstream
(`open(F, write, S, [type(binary)])`); am Ende liest `fast_read` den Term
`end_of_file`. Variablen bleiben geteilt, Attribute fallen weg. Gelesen
wird sicher (`:safe`, nur Prolog-Terme) – kaputte oder fremde Daten geben
`syntax_error(fast_term)`, eine andere Formatversion
`syntax_error(fast_term_version)`. 100 000 Terme: `fast_write` 0,7 s statt
`writeq` 3,1 s, `fast_read` 1,6 s statt `read` 17 s.

## Ausgabe: Terme mit Operatoren

`write/1`, `print/1`, `writeq/1`, `write_canonical/1`, `write_term/2` und die
Antworten im Toplevel schreiben mit Operatoren, nach ISO und im Stil von
gprolog; jede `writeq`-Ausgabe liest sich wieder als
derselbe Term:

```
?- X = (a :- b, c ; d), Y = 1 - -1, Z = -(1), W = - a, V = f((a,b), -).
V = f((a, b), -), W = -a, X = (a:-b, c;d), Y = 1- -1, Z = - (1).
?- writeq(f('A b', 1+2*3, (1+2)*3, a mod b, \+ (x,y), [x|T], "ab")).
f('A b',1+2*3,(1+2)*3,a mod b,\+ (x,y),[x|T],"ab")
```

  * Klammern nur, wo die Priorität es verlangt; Operator-Atome als Operanden
    in Klammern (`a-(mod)`, `X = (-)`), `- (1)` für das Präfix-Minus vor
    einer Zahl, Leerzeichen, wo Zeichen sonst zu einem Token verschmölzen
    (`1- -1`, `a- -b`, `N+\\ \\X^G`).
  * `writeq`/`print` quoten Atome (`'1'`, `'hello world'`, `'.'`), `write`
    nicht; `write_canonical` schreibt ohne Operatoren (`+(1,2)`), auch Listen
    und `{}` funktional wie ISO 8.14.2.4 verlangt: `'.'(1,'.'(2,[]))`, `{}(a)`.
  * `'$VAR'(N)` erscheint als `A`, `B`, …, `Z`, `A1`, … (außer bei
    `write_canonical`).
  * Zeichenlisten bei `double_quotes=chars` wie Scryer als `"..."`
    (`number_chars(123, X)` → `X = "123"`).
  * Frische Variablen in Antworten (nicht aus der Anfrage) heißen wie bei
    SICStus `_A`, `_B`, …, `_Z`, `_AA`, … – je Antwort neu, in Reihenfolge
    des Auftretens, auch in Restzielen; Namen aus der Anfrage werden nicht
    vergeben (`length(As, N)` → `As = [_A, _B], N = 2`).
  * Antworten und `listing` setzen Leerzeichen nach Kommas (`f(a, b)`,
    `[a, b|T]`) wie SWI; `writeq` schreibt kompakt (`f(a,b)`) wie ISO.
  * `write_term/2`: `quoted/1`, `ignore_ops/1`, `numbervars/1`,
    `variable_names/1` (ISO), `max_depth/1`, `spacing/1`, `priority/1` (SWI).
  * Die Operatortabelle für die Ausgabe spiegelt die des Readers: `op/3`,
    Operatoren aus Bibliotheken und aus `module/2`-Exportlisten.
  * `listing/1` wie `portray_clause`, mit eingerücktem Wenn-dann-sonst.
  * Auch sehr tiefe Terme ohne wachsenden Stack: Der Writer steigt in einer
    Schleife ab und legt für jede Struktur einen Rahmen auf einen Stapel im
    Heap (was noch fehlt: weitere Argumente, der rechte Operand, `)` …).
    `f(1,f(2,…))`, `a,(b,(…))`, `((1+2)+3)+…`, `- - - a`, `[[[…]]]` und
    Verschachtelung in mittleren Argumenten kosten so nur Heap; bei einer
    Million Ebenen etwa 1–2 s (vorher 2–4 s, rekursiv).

Abweichung von gprolog: Nach einem alphanumerischen Präfix-Operator steht
immer ein Leerzeichen (`dynamic -a`, gprolog: `dynamic-a`), damit auch andere
Systeme es als Präfix lesen.

## Reifizierte Gleichheit: `library(reif)` und `library(reif_pl)`

Nach Neumerkel und Kral, „Indexing dif/2“ (2016): `if_/3`, `(=)/3`,
`dif/3`, `(',')/3`, `(;)/3`, `cond_t/3`, `memberd_t/3`, `tfilter/3`,
`tpartition/4`, `tmember/2`, `tmember_t/3` – rein und ohne überflüssige
Choice Points:

```
?- tfilter(dif(a), [a,b,X,a,c], Fs).
Fs = "bc", X = a ;
Fs = [b, X, c], dif(X, a).
```

Zwei Fassungen mit denselben Antworten (Vergleichstest auch auf
Zufallstermen): `library(reif_pl)` in reinem Prolog wie reif.pl,
`library(reif)` mit Schnellwegen in Elixir – bei `X = Y`/`dif(X, Y)` als
Bedingung und `=(Y)`/`dif(Y)` als Closure entscheidet die Prüfung von
`dif/2` vorab, Zweige gibt es nur bei offenen Elementen. Gemessen
(`mix run bench/reif_bench.exs`, 100 000 Elemente): `tfilter(dif(5), L, Fs)`
28 ms gegen 1494 ms, `memberd_t/3` 13 ms gegen 991 ms; mit eigener
Closure (`tfilter(gross, L, Fs)`) etwa gleich schnell.

## Ganzzahlen erzeugen: `library(between)`

Wie SICStus: `gen_nat/1` (0, 1, 2, … ohne Ende), `gen_int/1` (0, 1, -1, 2,
-2, …), `numlist/5` (`numlist(L, 2, U, N, [1,X,Y,Z])` gibt `L = 1, U = 7,
N = 4, X = 3, Y = 5, Z = 7`; Länge aus Length, der Liste oder Lower/Step/
Upper), dazu `between/3`, `repeat/1` und `numlist/2,3`.

## Zufall: `library(random)`

Wie SICStus: `random/1` (Float in [0,1)), `random/3` (Ganzzahlen: L =< X < U,
sonst Float), `random_member/2`, `random_select/3` (auch Einfügen),
`random_subseq/3`, `random_permutation/2`, `randseq/3` (K verschiedene
Zahlen aus 1..N in zufälliger Reihenfolge – `randseq(N, N, L)` ist ein
gemischtes `numlist(1, N, L)`), `randset/3` (dasselbe sortiert),
`getrand/1`/`setrand/1`; dazu aus SWI `random_between/3` (inklusive H) und
`set_random(seed(N))`. Generator: Erlangs `exsss`, Zustand je Sitzung,
anfangs zufällig; `set_random(seed(N))` macht Läufe reproduzierbar.
`randseq(1000000, 1000000, L)` dauert etwa 1 s.

## Globale Werte: `library(blackboard)`, `library(mutables)`

Wie SICStus (dort eingebaut, hier nach `use_module`):

  * `bb_put(:Key, +T)`, `bb_get(:Key, ?T)`, `bb_delete(:Key, ?T)`,
    `bb_update(:Key, ?Old, ?New)` – Werte je Modul (Key ein Atom oder eine
    Ganzzahl, auch `M:Key`), als Kopie gespeichert, nicht backtrackbar.
  * `create_mutable(+W, -M)`, `get_mutable(?W, +M)`, `update_mutable(+W, +M)`,
    `mutable(@M)` – backtrackbare Zuweisung: Backtracking stellt den alten
    Wert her. Der Wert ist das versteckte Attribut einer Variablen, eine
    Änderung also ein Eintrag in der Substitution. Der Toplevel zeigt ein
    Mutable als `'$mutable'(Wert)`.

## Lambdas: `library(lambda)` und `library(lambda_pl)`

Nach Ulrich Neumerkel, in zwei Varianten mit gleichem Verhalten:
`library(lambda)` in Elixir, `library(lambda_pl)` in reinem Prolog wie sein
`lambda.pl` (Quelltext: `priv/library/lambda_pl.pl`).

```prolog
?- use_module(library(apply)), use_module(library(lambda)).
?- maplist(\X^Y^(Y is X*2), [1,2,3], L).
L = [2, 4, 6].
?- N = 10, maplist(N+\X^Y^(Y is X+N), [1,2], L).
L = [11, 12], N = 10.
```

`\X1^..^Xn^G` wird bei jedem Aufruf kopiert (lokale Variablen frisch),
`Free+\Lambda` lässt die Variablen von `Free` aus (mehrere als Liste:
`[A,B]+\...`), `X^G` ohne `\` kopiert nicht. Zu wenige Argumente:
`existence_error(lambda_parameter, ...)`. Der Operator `+\` (201, xfx) gilt
ab `use_module`.

Die Elixir-Variante bindet die Parameter und ruft den Rumpf in einem
Schritt auf, statt über `call/N` → `^/N` → `call/N-1` je Parameter; sie
ist etwa 2–3-mal so schnell (`mix run bench/lambda_bench.exs`), ein
eigenes Hilfsprädikat bleibt noch einmal gut 2-mal schneller.

Bibliotheken in Prolog-Quelltext: `priv/library/NAME.pl` mit
`:- module(NAME, ...)` lädt `use_module(library(NAME))` wie eine Datei.

## Sichere Tests: `library(si)`

„sufficiently instantiated“ (Neumerkel, Scryer), in Elixir: Statt bei zu
wenig gebundenen Argumenten zu scheitern, werfen die Prädikate
`instantiation_error`; sie gelingen nur, wenn die Aussage für jede weitere
Bindung gilt, und scheitern nur, wenn sie für keine gilt.

  * `atom_si/1`, `integer_si/1`, `atomic_si/1`, `list_si/1`, `character_si/1`,
    `chars_si/1` – `atom_si(X)` wirft, `list_si([a|_])` wirft,
    `list_si([a|b])` scheitert.
  * `dif_si/2` – gelingt, wenn nie unifizierbar (`dif_si(f(_,a), f(_,b))`).
  * `compare_si/3` – Standardordnung, nur wenn entschieden:
    `compare_si(O, f(a,X), f(b,Y))` gibt `<`, `compare_si(O, f(X,a), f(Y,b))` wirft.
  * `sort_si/2`, `msort_si/2`, `keysort_si/2` – nur, wenn das Ergebnis für
    jede weitere Bindung dasselbe wäre: `sort_si([X,X], L)` gibt `[X]`,
    `sort_si([X,a], L)` wirft.
  * `term_si/1` – ground: ja, sonst wirft es; `not_si/1` – wie `\+`, aber
    nur für ground Ziele (sonst wirft es), dann ist das Ergebnis logisch.
  * `when_si/2` – wie `when/2`, aber ohne zu warten: ist die Bedingung
    schon wahr, läuft das Ziel, sonst `instantiation_error`. Das Konzept
    hinter allen `_si`-Tests: `atom_si(X) :- when_si(nonvar(X), atom(X))`,
    `dif_si(X, Y) :- when_si(?=(X, Y), X \== Y)`.

## Messen: `statistics/2`, `statistics/0`

`statistics(K, V)`:

| Schlüssel | Wert |
|---|---|
| `runtime` (auch `total_runtime`, `process_cputime`) | `[T, D]` CPU-Zeit der VM in ms |
| `walltime` | `[T, D]` ms seit Start der VM |
| `real_time` | `[S, D]` Sekunden seit 1970 |
| `inferences` | Prädikataufrufe der Sitzung (wie SWI; auch `=/2`, `is/2`; nicht `,` `;` `->` `!` `call/N`) |
| `reductions` | `[R, D]` Reduktionen des Sitzungsprozesses (Arbeitsmaß der BEAM) |
| `memory` | `[Bytes, 0]` Speicher des Sitzungsprozesses (wie SICStus) |
| `process_memory`, `vm_memory` | Bytes: Sitzungsprozess, ganze VM |
| `garbage_collection` | `[Anzahl, Bytes freigegeben, 0]` der VM (die GC-Zeit misst die BEAM nicht) |
| `schedulers`, `process_count` | aktive Scheduler, Erlang-Prozesse |

`D` ist der Abstand zum letzten Aufruf mit demselben Schlüssel. Inferenzen
pro Sekunde:

```prolog
?- numlist(1, 400, L), statistics(inferences, I0), statistics(runtime, [T0, _]),
   nrev(L, _), statistics(runtime, [T1, _]), statistics(inferences, I1),
   LIPS is (I1 - I0) / (T1 - T0) * 1000.
```

`statistics/0` gibt eine Übersicht aus. Das Zählen der Inferenzen kostet
etwa 25 ns je Aufruf (rund 1–2 %).

## Ressourcen begrenzen: `call_with_inference_limit/3`, `call_with_depth_limit/3`

Wie SWI und Scryer: `call_with_inference_limit(G, L, R)` ruft `G` mit
höchstens `L` Inferenzen (Prädikataufrufen) *je Lösung* – beim Backtracking
in `G` gibt es ein frisches Kontingent. `R` ist `!` (G deterministisch
gelungen), `true` (Choice Points offen) oder `inference_limit_exceeded`
(`G` wurde abgebrochen, keine weiteren Lösungen).

```prolog
?- call_with_inference_limit(member(X, [a, b]), 10, R).
R = true, X = a ;
R = !, X = b.
?- assertz((loop :- loop)), call_with_inference_limit(loop, 1000, R).
R = inference_limit_exceeded.
```

  * Verschachtelt gelten alle Grenzen, die strengere gewinnt: eine innere
    Grenze kann eine äußere nicht verlängern.
  * Abgebrochen wird mit der Ausnahme `inference_limit_exceeded`; fängt `G`
    sie selbst (`catch(_, _, ...)`), wird sie beim nächsten Schritt erneut
    geworfen – die Grenze lässt sich nicht verschlucken.
  * Unteranfragen (`findall/3`, `\+`, `forall/2`, ...) zählen mit.
  * Kosten ohne Grenze: ein Vergleich je Schritt, im nrev-Benchmark nicht
    messbar; mit aktiver Grenze ebenso.
  * Was in einem eingebauten Prädikat (Elixir) geschieht, zählt als eine
    Inferenz und wird nicht unterbrochen.

`call_with_depth_limit(G, L, R)` wie SWI: Aufrufe tiefer als `L` Ebenen
scheitern (für Iterative Deepening, zum Abfangen endloser Rekursion).
Gelingt `G`, ist `R` die größte erreichte Ebene (mindestens 1); scheitert
`G` und wurde dabei die Grenze überschritten, gelingt der Aufruf einmal mit
`R = depth_limit_exceeded`, sonst scheitert er.

```prolog
?- call_with_depth_limit(nat(X), 3, R).     % nat(0). nat(s(X)) :- nat(X).
R = 1, X = 0 ;
R = 2, X = s(0) ;
R = 3, X = s(s(0)) ;
R = depth_limit_exceeded.
```

Was eine Ebene ist, legen wir unabhängig von der Implementierung fest:

  * Nur Prädikate mit Klauseln aus Benutzermodulen bilden Ebenen; `G`
    selbst ist Ebene 1, der Rumpf einer Klausel liegt eine Ebene tiefer
    als ihr Aufruf.
  * Eingebaute Prädikate (`is/2`, `=/2`, ...) und die Interna der
    Bibliotheken – auch der in Prolog geschriebenen – kosten keine Ebene.
    Ein Ziel, das eine Bibliothek zurückruft (`maplist/3`, `findall/3`,
    ...), liegt auf der Ebene ihres Aufrufs. In SWI zählen dagegen auch
    Builtins und Bibliotheksprädikate; dort ist `R` daher oft größer.
  * Steuerkonstrukte (`,` `;` `->` `\+` `call/N` `catch/3`) sind
    durchsichtig: `(A,B,C)` liegt ganz auf einer Ebene.
  * Endrekursion braucht auch mit Grenze konstanten Speicher: Die Tiefe
    zählt hoch (ein endloser endrekursiver Loop wird erkannt), aber die
    Fortsetzung wächst nicht.
  * Kosten: ohne aktive Grenze keine; mit aktiver Grenze etwa 25–30 % im
    nrev-Benchmark.
  * Verschachtelt (auch mit `call_with_inference_limit/3`) gilt die
    strengere Grenze.

## Coroutining

`freeze/2`, `frozen/2`, `dif/2`, `when/2` (Bedingungen `nonvar/1`,
`ground/1`, `?=/2`, `,`, `;`), dazu `?=/2` und `ground/1`. Verzögerte Ziele
laufen, sobald eine ihrer Variablen gebunden wird – vor dem nächsten Ziel,
auch nach Bindungen im Klauselkopf oder in Builtins. Offene Bedingungen
zeigt der Toplevel als Restziele:

```
?- dif(f(X, Y), f(1, 2)), X = 1.
X = 1, dif(Y, 2).
```

`dif/2` merkt sich nur die *Front*: die Paare des Unifikators, die noch
offen sind. Wird eine ihrer Variablen gebunden, wird die Front gemeinsam
neu unifiziert (erfüllt, gescheitert oder kleinere Front); das Restziel
schrumpft entsprechend (`dif(f(X,Y,Z), f(1,2,3)), X = 1` →
`dif(f(Y, Z), f(2, 3))`).

Ist die Front ein einziges Paar *Variable = ground Wert*, kommt der Wert in
die **Ausschlussmenge** der Variablen statt in eine eigene Bedingung:
`dif(X, a), dif(X, b), …` ist eine Menge „X ∉ {a, b, …}“. Bindet man X an
einen ground Wert, kostet das ein Nachschlagen statt k Prüfungen; bei
X = Y geht die Menge an Y über, bei einem Term mit Variablen (X = f(Z))
wird jeder Wert wieder ein `dif` (dabei oft eine kleinere Menge, etwa an
Z). Als Restziele erscheint die Menge wie gewohnt als `dif(X, a), dif(X, b)`
(jeder Wert einmal). Ausschlussmengen werden beim Wecken vor den übrigen
Weckzielen geprüft; alle anderen in der Reihenfolge des Anhängens.

Übrige geweckte `dif`-Bedingungen prüft die Maschine selbst in Elixir
(statt eines Prolog-Weckziels mit vier Inferenzen), mit frühem Abbruch
beim ersten Scheitern; neue werden in O(1) angehängt. Auch für geweckte
`freeze`/`when` prüft die Maschine selbst, ob die Bedingung erledigt ist,
und legt nur noch das Ziel auf den Stapel (eine Inferenz statt vier).
`mix run bench/dif_bench.exs`, `mix run bench/memberd_bench.exs`: `memberd(X, L)`
mit 1000 Elementen, alle Antworten, 2200 ms → 3 ms.

`frozen/2`, `copy_term/3` (Body als Konjunktion) und `term_attvars/2` wie
SICStus. `copy_term/2` und `findall/3` kopieren Attribute nicht mit.

### Attributierte Variablen: `library(atts)` wie SICStus

```prolog
:- module(domain, [domain/2]).
:- use_module(library(atts)).
:- attribute dom/1.

verify_attributes(Var, Wert, Goals) :- ...   % vor der Bindung
attribute_goal(Var, domain(Var, Dom)) :- get_atts(Var, dom(Dom)).
```

`put_atts/2` (`+A`, `-A`, Listen), `get_atts/2` (auch mit ungebundener
Angabe: alle Attribute), jeweils im Kontextmodul. Beim Binden
attributierter Variablen läuft es wie in SICStus: Bindungen zurücknehmen →
`M:verify_attributes(Var, Wert, Goals)` für jede Variable und jedes Modul
mit `:- attribute` (alle sehen alle beteiligten Variablen ungebunden) →
Bindungen wiederherstellen → alle Goals (im Modul M) → Weckziele von
freeze/dif/when. Scheitern, Alternativen und Ausnahmen der Hooks wirken
normal. `attribute_goal/2` liefert Restziele für Toplevel, `frozen/2`
und `copy_term/3`. Ohne Attributmodule kostet das alles nichts.

## Module

Flache Module (ein Baum der Tiefe 1 unter `system`), Sichtbarkeit wie SICStus:

```prolog
:- module(geo, [flaeche/2, op(700, xfx, ===>)]).
:- use_module(library(lists)).
:- meta_predicate zweimal(0).
```

  * `module/2`, `use_module/1,2` (Dateien und `library(lists)`,
    `library(apply)`, `library(random)`, `library(atts)`, `library(between)`, `library(reif)`, `library(reif_pl)`,
    `library(blackboard)`, `library(mutables)`, `library(lambda)`,
    `library(lambda_pl)`, `library(si)`), `ensure_loaded/1`, `consult/1`, `M:Ziel`,
    `M:Kopf :- Rumpf`, `assert(M:Klausel)`, `meta_predicate/1`,
    `current_module/1`, `strip_module/3`, `predicate_property/2` (wie
    SICStus: `built_in`, `static`, `dynamic`, `defined`, `compiled`,
    `interpreted`, `exported`, `imported_from/1`, `meta_predicate/1`,
    `multifile`, `discontiguous`, `number_of_clauses/1`; ohne Kopf
    `instantiation_error`, `M:H` zählt auf; unbekannte Eigenschaft:
    `domain_error(predicate_property, P)`); `clause/2`, `retract/1`,
    `dynamic/1`, `listing/1`, `current_predicate/1` mit `M:`.
  * Auflösung eines Aufrufs in Modul `m` wie SICStus: in `m` definiert →
    nach `m` importiert → `system`. Kein Rückgriff auf `user` (sonst
    `user:foo` schreiben) und kein Autoload:
    Bibliotheksprädikate wie `append/3`, `member/2`, `maplist/2..8` gibt es
    nur nach `:- use_module(library(lists)).` bzw. `library(apply)` – auch
    im Toplevel. Eigene Definitionen gehen Importen vor.
  * `library(lists)` gibt wie bei SICStus auch `maplist/2..8`, `include/3`,
    `exclude/3` und `partition/4` aus `library(apply)` weiter (Re-Export:
    importiert wird aus `apply`, beide zusammen ergeben keinen Konflikt).
    `foldl/4..6` gibt es nur in `library(apply)`.
  * Rümpfe laufen im Modul, in dem das Prädikat definiert ist;
    Meta-Argumente (`0..9`, `^`, `//`, `:`) werden beim Aufruf mit dem
    Kontextmodul qualifiziert. Prädikate von `system` sind geschützt.
  * Dateien werden schrittweise gelesen: Operatoren aus der Exportliste
    eines mit `use_module` geladenen Moduls gelten schon für den Rest der
    ladenden Datei. Operatoren sind global (nicht modul-lokal).
  * Relative Pfade in einer Datei gelten ab deren Ordner.
  * `:- multifile(P)`: Klauseln von P aus mehreren Dateien werden
    aneinandergehängt (sonst ersetzt die zuletzt geladene Datei die
    Definition). `multifile`/`discontiguous` deklarieren das Prädikat:
    ohne Klauseln scheitert ein Aufruf statt `existence_error`.
  * Warnungen beim Laden (wie SWI), mit Zeile und bei `include` mit Datei:
    Singleton-Variablen einer Klausel oder DCG-Regel (nicht in
    Direktiven; `_X` gilt als Absicht, mehrfach verwendet gibt es eine
    eigene Warnung) und nicht zusammenhängende Klauseln ohne
    `discontiguous/1` (einmal je Prädikat; Klauseln, die `term_expansion`
    aus einem Term macht, dürfen sich abwechseln). Abschalten mit
    `style_check(-singleton)`, `style_check(-(discontiguous))` – die
    Klammern braucht ISO, weil `discontiguous` ein Präfixoperator ist;
    `style_check(?(X))` fragt ab. Fehler in Direktiven nennen ebenfalls die
    Zeile.
  * `:- include(F)`: die Terme von F stehen an dieser Stelle (relativ zur
    einschließenden Datei, `.pl` darf fehlen).
  * `:- if(C)` … `:- elif(C)` … `:- else` … `:- endif` (verschachtelbar,
    wie SWI/SICStus/GNU): C läuft als Anfrage und sieht das bisher
    Geladene, ein Fehler gilt als falsch. In inaktiven Zweigen wird alles
    übersprungen, auch Direktiven und Syntaxfehler.

## Expansion: `term_expansion/2`, `goal_expansion/2`

Wie SWI/SICStus: Hooks im Quellmodul oder in `user`, ab der Klausel nach
ihrer Definition wirksam.

```prolog
term_expansion(erzeuge(N), [p(N), q(N)]).   % ein Term wird zu zweien
goal_expansion(alt(X), neu(X)).             % Teilziele im Rumpf ersetzen
goal_expansion(setze(X), true) :- X = 42.   % Bindungen gelten in der ganzen Klausel
```

  * `term_expansion`: jeder gelesene Term (auch Direktiven, vor der
    DCG-Übersetzung) und zum Schluss `end_of_file`; Ergebnis ein Term oder
    eine Liste (`[]`: entfällt).
  * `goal_expansion`: jedes Teilziel jedes Klauselrumpfs und jeder
    Direktive, wiederholt bis kein Hook mehr greift (höchstens 50-mal);
    auch in `,` `;` `->` `\+` `M:G` und in Meta-Argumenten (`findall/3`,
    `forall/2`, `bagof/3` mit `^`, eigene `meta_predicate`).
  * `expand_term/2`, `expand_goal/2`, `dcg_translate_rule/2`.
  * Fehler in einem Hook werden gemeldet, der Term bleibt dann, wie er ist.
  * Anfragen im Toplevel werden ebenso expandiert (Hook in `user`; wie SWI,
    SICStus expandiert Meta-Aufrufe zur Laufzeit). Bindungen des Hooks
    erscheinen in der Antwort.
  * Ohne Hooks kostet das Laden nichts zusätzlich.

## Eigene Builtins in Elixir

Ein Modul mit `use PrologEx.Builtin` anlegen und in `PrologEx.Builtins`
(`@modules`) eintragen:

```elixir
defmodule PrologEx.Builtins.MyBuiltins do
  use PrologEx.Builtin

  # deterministisch: :ok | :fail | {:unify, [{a, b}, ...]} | {:call, ziel}
  defbuiltin "my_atom_length", [x, len] do
    case deref(x) do
      {:atom, name} -> {:unify, [{len, String.length(name)}]}
      {:var, _} -> raise "instantiation_error"
    end
  end

  # nichtdeterministisch: Liste/Stream solcher Ergebnisse, lazy
  defbuiltin "between", [lo, hi, x], nondet: true do
    for i <- deref(lo)..deref(hi)//1, do: {:unify, [{x, i}]}
  end
end
```

Details in der Moduldoku von `PrologEx.Builtin`. Builtins sind gegen
Neudefinition geschützt, außer mit `protected: false` (so bei `append/3`
und `length/2`). Bibliotheksprädikate in Prolog liefert ein Modul über
`library/0` (siehe `PrologEx.Builtins.Lists`). Ruft ein Elixir-Builtin
Hilfsprädikate über `{:call, ...}` auf, gibt es sie mit
`helpers: [{"$name", n}]` an; `listing` zeigt sie dann mit an (bei
Prolog-Bibliotheksprädikaten werden sie aus dem Quelltext ermittelt).

`append/3` ist hybrid: mit fertigem erstem Argument rechnet es direkt in
Elixir (deterministisch, bei ground Listen über `++`), sonst läuft die
klassische Definition. `nrev` über 300 Elemente wird dadurch etwa 17-mal
schneller als mit einem selbst definierten `app/3`.

## ISO-Konformität: Logtalks Testsammlung

`conformance/run.exs` führt die Konformitätstests von Logtalk
(`tests/prolog`: ISO-Norm samt Korrigenda, Szabó/Szeredi, SICStus, SWI;
gut 3 600 Tests) direkt in PrologEx aus – ohne Logtalk, mit einem Nachbau
des nötigen Teils von lgtunit (`conformance/lgtunit.pl`):

```
git clone --depth 1 https://github.com/LogtalkDotOrg/logtalk3 /pfad/logtalk3
mix run conformance/run.exs /pfad/logtalk3 [predicates/atom_length_2] [--failures datei]
```

Stand: Alle Tests aus der ISO-Norm und aus dem Konformitätsrahmen von
Szabó/Szeredi bestehen. Bewusst anders als SICStus: `sub_atom/5` mit
negativen Zahlen scheitert (ISO sieht keinen Fehler vor). Gesamt:
4 072 bestanden, 134 fehlgeschlagen, 206 übersprungen. Die übrigen
Fehlschläge betreffen Logtalk-, ECLiPSe- und „commons“-Erweiterungen
(Klauselreferenzen, `evaluable_property/2`, `atomic_concat/3`, die
logical-update-Tests über `lgt:`), Unicode-Optionen von `open/4`,
Escapes außerhalb von ISO (`0'\e`, `0'\d`, `0'\s`, `0''` – bewusst
Syntaxfehler) und `functor/3` mit Stelligkeit 10^45 (`resource_error`).

## Reader

`PrologEx.Parser` liest Prolog-Text: Tokenizer nach ISO 6.4,
Operator-Präzedenz-Parser nach 6.3. Gelesen wird im Sitzungsprozess mit
dessen Operatortabelle (`op/3`, `current_op/3`) und Flag `double_quotes`;
Änderungen gelten ab dem nächsten Term – beim Laden einer Datei also ab
dem Term nach der Direktive, im Toplevel ab der nächsten Anfrage
(`?- :- G.` führt G wie eine Direktive aus). `PrologEx.Reader` ist die
Schnittstelle dazu (Texte, Dateien in Abschnitten bis zur nächsten
Direktive). Der frühere gprolog-Reader (`PrologEx.GprologReader`) dient
nur noch als Vergleich.

  * Auf den `.pl`- und `.lgt`-Dateien von Logtalk (gut 5 100 Dateien,
    190 000 Terme) liefert er dieselben Terme wie gprolog, außer wo
    gprolog an eigene Grenzen stößt (Ganzzahlen über 2^60 in Hex,
    Unicode-Escapes über 255, Byte-Order-Mark, sehr tief verschachtelte
    Terme) – rund doppelt so schnell.
  * Ein Operator allein ist ein ganzer Term (`- .` liest `-`, wie gprolog).
  * In Quotes sind Steuerzeichen (Tab, Zeilenumbruch, …) nur als
    Escape-Sequenz erlaubt (ISO 6.4.2.1).
  * Zeichenumsetzung (ISO 8.14.5/6): `char_conversion/2`,
    `current_char_conversion/2` (nur Paare In ≠ Out; Fehler
    `type_error(character, X)` wie gprolog und SICStus). Mit dem Flag
    `char_conversion` auf `on` setzt der Reader jedes Zeichen außerhalb von
    Quotes, `0'c` und Kommentaren um, bevor er zerlegt – auch zu `.`, `%`
    oder Quotes. gprolog setzt zusätzlich in Strings und `0'c` um; hier
    gilt der Wortlaut „unquoted“ (wie SWI und SICStus). Die Tabelle gehört
    der Sitzung; beim Laden gilt eine Direktive ab dem nächsten Term.
  * ISO-Regeln: `- 1` und `'-'1` sind die Zahl -1, `-(1)` nicht; ein
    Operator als Atom hat Priorität 1201 (erlaubt als Argument, in
    Klammern und in `{}`), also Fehler bei `- = a` oder `'<<'/2`; nach
    dem Endepunkt muss Leerraum oder `%` folgen; Gleitkommazahlen brauchen
    Nachkommastellen (`1e10` ist ein Fehler); `(a|b)` ist `'|'(a, b)`.
  * Bewusst anders als gprolog: Backquotes werden mit Escapes gelesen
    (ISO 6.4.7), `\0\` ist im Atom erlaubt, `1.0e400` ist ein
    Syntaxfehler statt `inf`.
  * Nach einem Syntaxfehler geht es hinter dem nächsten Endepunkt weiter
    (wie gprolog, aber Kommentare zählen als Ganzes).

Vergleich mit gprolog: `mix run conformance/reader_diff.exs datei...`
oder `--cases conformance/reader_cases.txt` (gut 200 Grenzfälle).

## Entwicklung

```sh
mix test                  # Tests (Vergleiche mit gprolog nur,
                          # wenn dessen Reader übersetzt ist)
mix run bench/bench.exs   # Speicher- und Laufzeitmessung
```
