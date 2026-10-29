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

Voraussetzung: nur Elixir (ab 1.14, OTP 25). Gelesen und ausgeführt wird
alles in Elixir; keine weiteren Programme, keine Abhängigkeiten.

```sh
mix compile                          # übersetzen
mix prolog                           # interaktiver Toplevel
mix prolog examples/demo.pl          # Datei laden, dann Toplevel
mix prolog examples/demo.pl -g main -q   # laden, main ausführen, Ende
cat prog.pl | mix prolog - -g main   # Programm von stdin
```

`mix rebuild` baut alles neu (wie `make clean && make all`).

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
X = [], Y = [1,2] ;        % ";" + Enter für die nächste Lösung
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

Unterstützt (was weder ISO noch SICStus eingebaut haben, erst nach Import
seiner Heimat-Bibliothek, siehe Module): Klauseln, DCG (`-->`, `phrase/2,3`, `M:Rumpf` wie SWI), Direktiven (`op/3`,
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
gleiche Werte und Fehler), Typprüfungen, `functor/3`, `=../2`, `append/3`, `length/2`, `member/2`, `select/3`, `permutation/2`, `memberchk/2`, `last/2`, `reverse/2`,
`proper_length/2`, `sum_list/2`, `max_list/2`, `min_list/2`, `max_member/2`,
`min_member/2`, `delete/3`, `list_to_set/2`, `nextto/3`, `subtract/3`,
`intersection/3`, `union/3`, `include/3`, `exclude/3`, `partition/4`, `foldl/4..6`,
`same_length/2`, `'$skip_list'(Len, List, Rest)` (wie SWI: überspringt
Len Zellen; Rest ist `[]`, eine Variable, ein anderer Term oder bei einer
zyklischen Liste eine Zelle im Zyklus – Brents Zykluserkennung, terminiert
immer; dieselbe Funktion liegt `length/2` und Co. zugrunde), aus SICStus' `library(lists)`: `same_length/3` (negatives N scheitert), `one_longer/2`,
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
T = f('a b',_A), V = ['X'=_A].
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

## Grammatiken über Dateien: `library(pio)`

Reine Eingabe wie in SWI und Scryer: `phrase_from_file(G, Datei)` wendet
die DCG `G` auf den Inhalt der Datei an, ohne ihn vorher ganz einzulesen.
Die Liste ist faul: ihr ungelesener Rest wartet mit `freeze/2`, und erst
wenn die Grammatik ihn braucht, kommt der nächste Block (4096 Zeichen)
dazu. Backtracking darüber ist normal möglich.

```prolog
:- use_module(library(pio)).
lines([L|Ls]) --> line(L), !, lines(Ls).
lines([]) --> [].
line([]) --> "\n", !.
line([C|Cs]) --> [C], line(Cs).

?- phrase_from_file(lines(Ls), 'a.txt').
Ls = ["hallo welt","zweite zeile"].
```

Was die Bibliothek bietet:
* `phrase_from_file/2,3` schließt die Datei, sobald die Grammatik erschöpft
  ist, abgeschnitten wird oder eine Ausnahme wirft.
* `phrase_from_stream/2,3` arbeitet auf einem offenen Stream.
* `stream_to_lazy_list/2` (dazu `_chars`/`_codes`) liefert die faule Liste
  der restlichen Zeichen.
* `lazy_list_location//1` gibt `file(Datei, Zeile, Spalte, Zeichen)`,
  `lazy_list_character_count//1` die Zeichennummer und `syntax_error//1`
  wirft mit diesem Ort.
* `phrase_to_file/2,3` und `phrase_to_stream/2` schreiben, wie in Scryer.

Mit `as(chars)` oder `as(codes)` wählt man Zeichen oder Codes. Ohne diese
Option richtet sich die Liste nach dem Flag `double_quotes`: Codes, wenn
es `codes` ist, sonst Zeichen. So passen Strings in der Grammatik immer
zur gelesenen Liste. SWI nimmt hier stets Codes. Alle anderen Optionen
gehen an `open/4`.

Gelesene Blöcke merkt sich der Stream, bis er geschlossen wird. Nach
`close/1` kann man daher nicht mehr in die Liste zurücksetzen; versucht
man es doch, kommt `existence_error(stream, S)`.

Tempo: 300 000 Zeichen zählen dauert 2,1 s, über eine fertige Liste 1,5 s.

## Dateien und Verzeichnisse: `library(files)`

Wie in Scryer Prolog: Pfade sind *Zeichenlisten* (`"a/b.txt"`), keine
Atome. So lassen sie sich mit DCGs und `library(lists)` zerlegen und gehen
direkt an `open/3,4`.

| Prädikat | Bedeutung |
|---|---|
| `directory_files(D, Fs)` | Einträge (Dateien und Verzeichnisse), sortiert |
| `file_exists(F)`, `directory_exists(D)` | gewöhnliche Datei / Verzeichnis (Verweise werden verfolgt) |
| `file_size(F, N)` | Größe in Bytes |
| `make_directory(D)`, `make_directory_path(D)` | anlegen; `_path` wie `mkdir -p` |
| `delete_file(F)`, `delete_directory(D)` | löschen (Verzeichnis muss leer sein) |
| `rename_file(F, G)`, `file_copy(F, G)` | umbenennen, kopieren |
| `working_directory(D0, D)` | D0 ist das aktuelle Verzeichnis, danach D (`working_directory(D, D)` fragt nur ab) |
| `path_canonical(P, C)` | absoluter Pfad, `.`/`..` und Verweise aufgelöst; scheitert, wenn es P nicht gibt |
| `path_segments(P, Ss)` | `"/a/b"` ⇔ `[[], "a", "b"]` |
| `file_modification_time(F, T)`, `file_access_time(F, T)`, `file_creation_time(F, T)` | Zeitstempel |

**Typprüfungen und Fehler** folgen Scryers `must_be/2` und `can_be/2`:
* Ein Pfad als Variable oder Teilliste gibt `instantiation_error`.
* Ein Pfad, der keine Liste ist, gibt `type_error(list, P)`.
* Ein Element, das kein Zeichen ist, gibt `type_error(character, E)`. Typfehler
  gehen dabei Instanziierungsfehlern vor.
* Ein Ergebnisargument, das keine Liste bzw. keine ganze Zahl sein kann,
  gibt `type_error(list, _)` bzw. `type_error(integer, _)`.
* Wo eine Datei oder ein Verzeichnis vorhanden sein muss, kommt sonst
  `existence_error(file, F)` bzw. `existence_error(directory, D)`.
* Was das Betriebssystem ablehnt (gibt es schon, nicht leer, keine
  Rechte), scheitert.

**Zeitstempel** wie in Scryer, in Ortszeit:
`['Y'="2026", m="10", d="28", 'H'="11", ..., finis]` mit den Feldern
`Y m d H M S y b B a A w u U W j D x v`. Früher heißt `@<`. Die
Erstellungszeit kennt Erlang unter Unix nicht, dort scheitert
`file_creation_time/2` (wie in Scryer auf Systemen ohne sie).

Das eingebaute `delete_file/1` (wie SWI, auch mit Atom) bleibt
verfügbar. Nach `use_module(library(files))` gilt das aus `files`, das
nur Zeichenlisten nimmt.

## Netzwerk: `library(sockets)`

TCP und Unix-Domain-Sockets wie in SICStus 4, dazu `current_hostname/1`
aus Scryer:

```prolog
?- use_module(library(sockets)).
?- socket_server_open(Port, S),                 % freier Port
   socket_client_open(localhost:Port, C, []),
   socket_server_accept(S, Client, SS, []),     % Client = '127.0.0.1'
   write(C, 'hallo.'), nl(C), flush_output(C), read(SS, T),
   close(C), close(SS), socket_server_close(S).
?- socket_server_open(P, S), socket_client_open(localhost:P, C, []),
   socket_select([s-S], SR, [], _, [], _, off),          % SR = [s-S]
   socket_server_accept(S, _, SS, []),
   socket_select([], _, [k-SS], R0, [], _, 0.1),         % R0 = [] nach 0,1 s
   write(C, 'x.'), nl(C), flush_output(C),
   socket_select([], _, [k-SS], R1, [], _, off),         % R1 = [k-SS]
   close(C), close(SS), socket_server_close(S).
```

* `socket_client_open(Addr, S, Opts)`, `socket_server_open(Addr, Srv[,
  Opts])`, `socket_server_accept(Srv, Client, S, Opts)`,
  `socket_server_close(Srv)`, `socket_select/7`, `current_host/1`,
  `current_hostname/1`.
* Adressen sind `Host:Port`, `inet(Host, Port)` oder `unix(Pfad)`, beim
  Server auch `Port` allein. `''` heißt dieser Rechner bzw. alle Schnittstellen. Der
  Port ist eine Zahl, ein Ziffernatom oder ein Dienstname wie `http`;
  ist er beim Server offen, wird ein freier gewählt und gebunden.
* `unix(Pfad)`: ein Unix-Domain-Socket an dieser Stelle im Dateisystem
  (relativ ab dem aktuellen Verzeichnis). `reuseaddr(true)` löscht beim
  Server eine vorhandene Datei vorher, `socket_server_close/1` löscht sie
  wieder. `Client` beim Annehmen ist dann `''`.
* `socket_select(+Server, -SBereit, +Lesen, -LBereit, +Schreiben,
  -SchBereit, +Timeout)` wartet, bis ein Server eine Verbindung zum
  Annehmen hat oder ein Stream ohne Blockieren lesen bzw. schreiben kann
  (auch am Ende, wo die Operation einen Fehler gäbe).
  * Einträge sind Server bzw. Streams oder `Term-Eintrag`; der Term
    bleibt am bereiten Eintrag, die Reihenfolge bleibt erhalten.
  * Timeout: `off` wartet beliebig, eine Zahl ≥ 0 in Sekunden, `S:U`
    Sekunden und Mikrosekunden. Ist er abgelaufen, sind alle Listen `[]`.
  * Gemeldet wird, was bei der Rückkehr bereit ist: alle lesbaren Streams;
    von Servern, deren Verbindungen gleichzeitig ankommen, sicher
    mindestens einer, die übrigen spätestens beim nächsten Aufruf.
  * Schreib-Streams sind immer bereit (Senden blockiert praktisch nie),
    ebenso Datei- und Speicher-Streams zum Lesen. Standardeingabe und
    Pipes wartet `socket_select/7` nicht ab.
  * Gewartet wird ohne Abfrageschleife: Socket-Streams melden sich einmal
    aktiv, für Server nimmt ein kleiner Prozess die Verbindung an, die
    `socket_server_accept/4` dann übernimmt.
* Server-Optionen: `reuseaddr/1`, `loopback/1`, `numeric_nodename/1`,
  `numeric_servname/1`. Stream-Optionen wie bei `open/4`: `type/1`,
  `alias/1`, `eof_action/1`, `encoding(utf8)`.
* Ein Socket-Stream ist **ein** Stream für beide Richtungen, hat also
  `input` und `output` und `mode(read_write)`, und ist nicht
  positionierbar. Die Voreinstellung ist Text (UTF-8); SICStus nimmt
  binär. `Client` ist wie bei SICStus nur die IP-Adresse, ohne Port.
* Fehler:
  * Eine abgelehnte Verbindung, ein unbekannter oder unerreichbarer
    Rechner gibt `existence_error(source_sink, Addr)`.
  * Ein belegter Port gibt `permission_error(open, source_sink, Addr)`.
  * Keine Adresse gibt `type_error(socket_address, _)`, ein Port außerhalb
    0..65535 `domain_error(socket_address, _)`.
  * Bei einem Server-Socket gibt es `type_error/existence_error(server_socket, _)`.
  * Senden, wenn die Gegenseite weg ist, gibt `socket_error(Grund)`.
  * `socket_select/7`: ein offener Timeout gibt `instantiation_error`, ein
    ungültiger `domain_error(timeout, T)`; die Listen werden wie Listen
    geprüft, die Streams wie bei `get_char/2` bzw. `put_char/2`.
* Socket-Operationen gelten als äußere Wirkungen: Der Toplevel rechnet sie
  nicht voraus.

## Bibliotheken aus Scryer Prolog

Als Prolog-Quelltext übernommen (`priv/library/`). Geändert sind nur die
Stellen, an denen Scryer eigene Hilfsprädikate seiner Maschine benutzt; das
ist jeweils am Dateianfang vermerkt.

* `library(error)` (Markus Triska, gemeinfrei) enthält
  `must_be(Typ, T)` und `can_be(Typ, T)`. Die Typen sind `integer`, `atom`,
  `character`, `in_character`, `chars`, `octet_character`, `octet_chars`,
  `list`, `boolean`, `pair`, `term`, `var`, `not_less_than_zero` und `type`.
  Dazu kommen `instantiation_error/0,1`, `domain_error/2,3`,
  `type_error/2,3`, `representation_error/1`, `resource_error/1` und
  `call_with_error_context/2`. Fehlerterme und Kontexte sind wie bei Scryer:
  ohne Kontext steht `[]`, sonst `must_be/2` bzw. `can_be/2`.
* `library(charsio)` (BSD-Lizenz, siehe `priv/library/SCRYER-LICENSE`):
  * `char_type/2` mit Scryers Klassen. Die ISO-Klassen des Lesers
    (`graphic`, `solo`, `layout`, `meta`, ...) sind genau, die
    Unicode-Klassen folgen den allgemeinen Kategorien (`alphabetic` = L
    und Nl, `lower` = Ll, `upper` = Lu, `numeric` = N). `upper(U)` und
    `lower(L)` geben eine Zeichenliste (ß → `"SS"`).
  * `read_from_chars/2` und `read_term_from_chars/3`: Der Term braucht
    den Schlusspunkt, leerer Text gibt `end_of_file`.
  * `write_term_to_chars/3`: Freie Variablen heißen `A`, `B`, ... wie in
    Scryer.
  * `chars_utf8bytes/2`, `chars_base64/3`, `get_line_to_chars/3`,
    `get_n_chars/3` und `get_single_char/1`. Letzteres ist bei uns
    zeilengepuffert.
* `library(dcgs)` bietet `seq//1`, `seqq//1` und `...//0`. `phrase/2,3`
  und die DCG-Übersetzung bleiben die eingebauten.
* `append/2` (Liste von Listen) steht jetzt in `library(lists)`, wie in
  SWI und Scryer.
* `library(format)` (Markus Triska, gemeinfrei) ist rein deklarativ:
  `phrase(format_(Fs, Args), Cs)` beschreibt die Zeichenliste. Die
  Direktiven sind `~w ~q ~a ~s ~d ~Nd ~D ~U ~NL ~f ~Nf ~r ~Nr ~R`,
  dazu `~n ~i ~~`, Spalten mit `~t ~| ~+` und `` ~`ct ``, sowie `~*`
  statt einer Zahl. Fehler sind wie in Scryer, z. B.
  `domain_error(format_string, "~e")`.

  Nach `use_module(library(format))` gelten Scryers `format/2,3`
  (= `phrase_to_stream(format_(Fs, Args), S)`) und `listing/1` statt der
  eingebauten. Ohne den Import bleibt das eingebaute `format/2,3` nach
  PIP 0110 mit `~e ~g ~p ~c`.

  Dazu kommt `portray_clause/1,2` mit Scryers Einrückung. `listing/1`
  sucht dabei im Modul des Aufrufers; bei Scryer ist das Modulsystem
  lockerer.
* `library(time)` (BSD-Lizenz) enthält:
  * `current_time/1`. Der Zeitstempel hat dieselbe Form wie bei
    `library(files)`.
  * `format_time//2` mit `%Y %m %d %H %M %S %y %b %B %a %A %w %u %U %W %j
    %D %x %v %%`, z. B. `phrase(format_time("%d.%m.%Y", T), Cs)`.
  * `sleep/1`, `max_sleep_time/1`.
  * `time/1`, das wie Scryer `% CPU time: 0.000s, 1 inference` je Lösung
    und beim Scheitern ausgibt. Gemessen wird direkt um das Ziel herum,
    also zählt nur das Ziel (`time(true)` meldet 1 Inferenz).

  Nach `use_module(library(time))` gilt dieses `time/1`, nach
  `use_module(library(swi))` das SWI-artige. `statistics/2` bleibt das eingebaute, eine Obermenge von
  Scryers vorläufigem.
* `library(os)` (Markus Triska, gemeinfrei):
  * `getenv/2`, `setenv/2`, `unsetenv/1` mit Namen und Werten als
    Zeichenlisten, Namen wie bei Scryer nur aus `alnum` und
    `ascii_punctuation`.
  * `shell/1,2` über `$SHELL -c`, sonst `/bin/sh`; die Ein- und Ausgabe
    wird geerbt.
  * `pid/1`.
  * `argv/1`: die Argumente nach `--` beim Start (`mix prolog datei.pl --
    a b`); `raw_argv/1` alle.
* `library(process)` (BSD-Lizenz) enthält
  `process_create(Exe, Args, Optionen)` mit `stdin/stdout/stderr(std | null
  | file(P) | pipe(S))`, `env/1`, `environment/1`, `cwd/1` und
  `process(P)`, dazu `process_wait/2,3` (`timeout(0 | infinite)`,
  `release/1`), `process_kill/1`, `process_id/2` und `process_release/1`.
  Optionen und Fehler sind wie bei Scryer.

  Ein Prozess läuft über einen Port der BEAM; Pipes sind benannte Pipes
  (`mkfifo`). Die BEAM meldet ein Programm, das ein Signal beendet hat,
  wie `exit(128 + Signal)`. `killed(9)` gibt es daher nur nach
  `process_kill/1`, Scryer kennt das Signal immer.
* Der Toplevel rechnet beim Vorausrechnen keine Antwort voraus, die einen
  Prozess startet, `shell/1,2` aufruft oder die Umgebung ändert. Solche
  Wirkungen ließen sich nicht zurücknehmen, sie passieren erst nach `;`.
  Außerhalb des Vorausrechnens werden sie im Memo des Toplevels vermerkt
  wie Ausgaben und Änderungen am Interpreter. Nach einer Antwort mit
  solcher Wirkung wird also gar nicht erst vorausgerechnet.
* Dafür neu in der Maschine:
  * DCG-Pushback (`H, PB --> B`) nach dem Entwurf des DCG-Standards,
  * die Schreiboption `double_quotes(true)` (Zeichenlisten als `"..."`,
    wie Scryer).

## Schnell speichern: `fast_write/2`, `fast_read/2`

Wie SWI (`fast_write/2`, `fast_read/2`, `fast_term_serialized/2`) und SICStus
(`library(fastrw)`, dazu `fast_write/1`, `fast_read/1`), nach
`:- use_module(library(fastrw)).` (`fast_term_serialized/2`: `library(swi)`): Terme als
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
V = f((a,b),-), W = -a, X = (a:-b,c;d), Y = 1- -1, Z = - (1).
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
    vergeben (`length(As, N)` → `As = [_A,_B], N = 2`).
  * Antworten, `listing` und Fehlermeldungen schreiben Terme kompakt wie
    Scryer und `writeq` – ohne Leerzeichen nach Kommas (`f(a,b)`,
    `[1,2,3]`, `(x,y)`); nur die Bindungen einer Antwort trennt `, `
    (`X = f(a,b), Y = [1,2]`). Leerzeichen nach Kommas gibt es mit
    `write_term/2` und `spacing(next_argument)` (wie SWI: `f(a, b)`,
    `[1, 2]`).
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
Fs = [b,X,c], dif(X,a).
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
Upper), dazu `between/3`, `repeat/1` und `numlist/2,3` – `between/3` und
`repeat/1` gibt es nur hier (siehe Module: Heimat-Bibliotheken).

## Zufall: `library(random)`

Wie SICStus: `maybe/0` (gelingt mit Wahrscheinlichkeit 1/2, wie auch in
SWI und Scryer), `random/1` (Float in [0,1)), `random/3` (Ganzzahlen: L =< X < U,
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

## Eindeutige Atome: `library(gensym)`

Wie Scryer und SWI: `gensym(+Base, -Unique)` gibt `Base1`, `Base2`, … (ein
Zähler je Basis), `reset_gensym(+Base)` setzt einen Zähler zurück,
`reset_gensym/0` (SWI) alle. Die Zähler überstehen Backtracking wie
`assert` und kosten nichts, solange niemand `gensym/2` aufruft. Erzeugte
Atome belasten die Atomtabelle der BEAM nicht. Fehler: Base Variable →
`instantiation_error`, kein Atom → `type_error(atom, Base)` (Scryer
scheitert hier nur), Unique gebunden → `uninstantiation_error(Unique)`.

**Erweiterung** (weder in Scryer noch in SWI – Code, der sie benutzt,
läuft nur hier): `current_gensym_base(?Base)` zählt die Basen mit
laufendem Zähler in Standardordnung auf, nach `reset_gensym/1` ist eine
Basis weg; Base weder Variable noch Atom → `type_error(atom, Base)`. Die
Liste wird beim Aufruf festgehalten. Gedacht zum Nachsehen und Debuggen;
den Zählerstand selbst gibt es bewusst nicht.

## Lambdas: `library(lambda)` und `library(lambda_pl)`

Nach Ulrich Neumerkel, in zwei Varianten mit gleichem Verhalten:
`library(lambda)` in Elixir, `library(lambda_pl)` in reinem Prolog wie sein
`lambda.pl` (Quelltext: `priv/library/lambda_pl.pl`).

```prolog
?- use_module(library(apply)), use_module(library(lambda)).
?- maplist(\X^Y^(Y is X*2), [1,2,3], L).
L = [2,4,6].
?- N = 10, maplist(N+\X^Y^(Y is X+N), [1,2], L).
L = [11,12], N = 10.
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
| `occurs_checks` | tatsächliche Occurs-Checks der Sitzung (siehe unten) |
| `occurs_check_steps` | ihre Arbeit: besuchte Teilterme aller Occurs-Checks |
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

`statistics/0` (`library(swi)`) gibt eine Übersicht aus. Das Zählen der
Inferenzen kostet etwa 25 ns je Aufruf (rund 1–2 %).

Occurs-Checks laufen mit dem Flag `occurs_check` (`true` oder `error`)
und bei `unify_with_occurs_check/2`. Gezählt wird nur ein *tatsächlicher*
Check – was schon oben entschieden ist, zählt nicht: eine Bindung an
einen atomaren Wert, an eine Variable oder an einen als ground bekannten
Term. `occurs_check_steps` zählt die besuchten Teilterme, bei einer
Liste mit n Elementen `f(Y)` also 3n + 1; ein Fund bricht ab. Beide
Zähler laufen weiter, Backtracking setzt sie nicht zurück:

```prolog
?- unify_with_occurs_check(X, 2).        % zählt nicht
?- length(L, 100), maplist(=(f(_)), L),
   statistics(occurs_check_steps, S0), unify_with_occurs_check(_, L),
   statistics(occurs_check_steps, S1), D is S1 - S0.
D = 301.
```

Gezählt wird beim Prüfen in einem Argument und je Check einmal gebucht;
der Check selbst wurde dabei sogar schneller (eigene Rekursion über die
Argumente statt `Enum.any?`, rund 10 % bei langen Listen). Ohne
Occurs-Check kostet das Zählen nichts.

## Ressourcen begrenzen: `call_with_inference_limit/3`, `call_with_depth_limit/3`

Wie SWI und Scryer (`library(iso_ext)`; `call_with_depth_limit/3`:
`library(swi)`): `call_with_inference_limit(G, L, R)` ruft `G` mit
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
X = 1, dif(Y,2).
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
Z). Als Restziele erscheint die Menge wie gewohnt als `dif(X,a), dif(X,b)`
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

`call_residue_vars(G, Vs)` wie SICStus und SWI: `Vs` sind die
attributierten Variablen, die während `G` entstanden sind und nach der
Lösung noch offen sind (ungebunden, mit einem nicht erledigten `freeze`,
`when`, `dif` oder einem Attribut eines Moduls). Das gilt in der Reihenfolge
des Entstehens und auch für Variablen, die sonst nirgends mehr vorkommen.
Dafür behält die Kompaktierung der Substitution, solange der Aufruf läuft,
auch unerreichbare attributierte Variablen, die jünger sind als die Marke.

```prolog
?- call_residue_vars((dif(X, f(Y)), X = f(Z)), Vars).
Vars = [Z,Y], X = f(Z), dif(Z,Y).
```

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
    `library(lambda_pl)`, `library(si)`, `library(gensym)`), `ensure_loaded/1`, `consult/1`, `M:Ziel`,
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
  * Eingebaut ohne Import ist nur, was ISO vorschreibt oder SICStus
    eingebaut hat. Alles andere hat eine *Heimat-Bibliothek* (nach Inhalt,
    nicht nach Herkunft) und ist erst nach deren Import sichtbar – auch
    die Steuerkonstrukte der Maschine wie `*->/2` oder `not/1`; ohne
    Import gibt es `existence_error(procedure, PI)`:

    | Bibliothek | Prädikate |
    |---|---|
    | `library(iso_ext)` (wie Scryer) | `forall/2`, `succ/2`, `setup_call_cleanup/3`, `call_nth/2`, `countall/2`, `call_with_inference_limit/3`, `copy_term_nat/2`; weitergegeben: `call_cleanup/2`, `call_residue_vars/2`, `copy_term/3`, `bb_get/2`, `bb_put/2` |
    | `library(between)` | `between/3`, `repeat/1` (dazu `numlist/2,3` usw.) |
    | `library(fastrw)` | `fast_read/1,2`, `fast_write/1,2` |
    | `library(swi)` | vorläufig der Rest aus SWI: `ignore/1`, `not/1`, `*->/2`, `plus/3`, `atomic_list_concat/2,3`, `atom_number/2`, `term_to_atom/2`, `read_term_from_atom/3`, `=@=/2`, `\=@=/2`, `term_attvars/2`, `findnsols/4,5`, `call_with_depth_limit/3`, `exists_file/1`, `exists_directory/1`, `delete_file/1`, `fast_term_serialized/2`, `time/1`, `statistics/0`, `style_check/1`, `expand_goal/2`, `dcg_translate_rule/2`, `strip_module/3` – und gibt alle obigen weiter |

    `library(swi)` ist ein Kompromiss auf Zeit: ihre Prädikate wandern nach
    und nach in Bibliotheken, zu denen sie inhaltlich passen. Eigene
    Definitionen gleichen Namens sind erlaubt und gelten; eine Bibliothek
    mit eigener Fassung (Scryers `time/1` in `library(time)`,
    `delete_file/1` in `library(files)`) behält sie. Bibliotheken des
    Systems sehen alle Prädikate ohne Import.
  * Flag `swi_compat` (Voreinstellung `false`): mit
    `set_prolog_flag(swi_compat, true)` ist alles aus der Tabelle wie bei
    SWI ohne Import sichtbar (die Logtalk-Testsammlung läuft so).
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
Direktive).

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

Neumerkels Konformitätstabelle zur ISO-Syntax (in der Fassung von Scryer
Prolog, 266 Fälle zum Lesen und Schreiben): 259 bestehen.
`mix run conformance/neumerkel/run.exs /pfad/scryer-prolog` (Checkout
von github.com/mthom/scryer-prolog). Die übrigen sieben sind Absicht oder
von ISO offen gelassen: Backquotes lesen sich als Atom (#113; ISO: kein
Term), `|` ist wie bei gprolog und SWI vordefiniert (#285), dazu Abstände
und Variablennamen in der Ausgabe (#142, #151, #226, #227, #260).

Die Tests vergleichen Reader und Writer mit gprolog über aufgezeichnete
Ergebnisse (`test/fixtures/reader/gprolog_reads.txt`,
`test/fixtures/writer/gprolog_writeq.txt`) – gprolog braucht man dafür
nicht. Zum Aufzeichnen und für Vergleiche ganzer Dateien liegt das
frühere gprolog-Orakel in `tools/gprolog/` (nicht im Build; braucht
`gplc`, übersetzt sich bei Bedarf selbst):

```sh
mix run tools/gprolog/reader_diff.exs datei...      # Terme wie gprolog?
mix run tools/gprolog/reader_diff.exs --cases conformance/reader_cases.txt
mix run tools/gprolog/record_reads.exs              # Lesarten neu aufzeichnen
GPROLOG_RECORD=1 mix test test/writer_ops_test.exs  # fehlende writeq-Werte
```

## Laufzeit

`mix run bench/suite.exs` misst kleine klassische Programme (beste von N
Läufen; `--save`/`--compare` für vorher/nachher). Stand (OTP 25, eine
Maschine im Rechenzentrum, ±5 % Rauschen):

| Programm | Zeit | MLIPS |
|---|---|---|
| nrev (30 Elemente, 400-mal) | 271 ms | 0,74 |
| loop (deterministisch, `is`) | 469 ms | 1,28 |
| between (Backtracking) | 117 ms | 2,58 |
| member (300 000 Lösungen) | 199 ms | 1,51 |
| facts (Klausel-Backtracking) | 176 ms | 1,87 |
| queens (8, alle) | 77 ms | 0,98 |
| tak (18, 12, 6) | 193 ms | 1,16 |
| deriv | 171 ms | 0,65 |

Wohin die Zeit geht (Profil von nrev): knapp die Hälfte in Kopfabgleich
und Rumpfaufbau der übersetzten Klauseln, gut ein Zehntel in `walk` und
Map-Zugriffen der Substitution, ein Zehntel in Buchhaltung (Inferenz-
zähler, Datenbank-Zugriff), der Rest in der Maschinenschleife.
Gemessen: Closures statt der interpretierten Klausel-IR bringen nichts
(360 statt 331 ns für Kopf und Rumpf von `app/3`), handgeschriebener
Elixir-Code wäre 4,4-mal schneller (75 ns) – den Gewinn gäbe es nur mit
echter Codeerzeugung (BEAM-Module je Prädikat).

Term-Traversierungen (Kopieren für `findall/3` & Co., Auflösen der
Antworten, Markieren, Attribute suchen, Occurs-Check) laufen mit eigener
Rekursion über die Argumente statt mit `Enum.map`/`Enum.reduce` und
Closure: `findall/3` über strukturierte Terme wurde dadurch rund 30 %
schneller (im Programm wie als Antwort), der Occurs-Check rund 25 %.

`plus/3`, `functor/3`, `arg/3`, `=../2`, `once/1`, `ignore/1` und
`current_prolog_flag/2` (mit gebundenem Namen) führt die Maschine selbst aus, statt
den allgemeinen Aufrufweg eines Builtins zu gehen (`plus/3` wie `not/1`
mit den Sichtbarkeitsregeln seiner Heimat; `functor/3` und `arg/3` sind
geschützt, ohne Prüfung): `plus/3` rund 17 % schneller, nahe an `is/2`,
`functor/3` und `arg/3` rund 20 %. `functor/3` bindet beim Zerlegen
Name und Stelligkeit direkt (atomar, kein Occurs-Check nötig); `arg/3`
ist deterministisch (ISO: ungebundenes N gibt `instantiation_error`,
kein Aufzählen wie in SWI) und sucht in einem Durchgang.

`clause/2` wählt die Klauseln wie ein Aufruf über den Index aufs erste
Argument: Nur Klauseln mit passendem Schlüssel oder einer Variable an
erster Stelle werden kopiert und unifiziert, in ihrer Reihenfolge; passt
genau eine, ist die Lösung deterministisch (kein Choice Point). Ein
Vanilla-Meta-Interpreter (`solve/1` über `clause/2`) läuft dadurch etwa
doppelt so schnell, der Zugriff auf eine Faktentabelle mit 1000 Fakten
rund 25-mal; `=../2` wurde 25–30 % schneller.

`once/1` und `ignore/1` waren Klauseln (`once(G) :- call(G), !.`), also
ein voller Prädikataufruf vor dem `call/1`; jetzt `call(G)` mit einem
Schnitt auf die jetzige Höhe bzw. `(call(G) -> true ; true)`: rund 45 %
bzw. 50 % schneller, dieselben Inferenzen. Nebenbei entfällt die
Modulqualifikation des Meta-Arguments, an der `call/1` bisher vorbeisah:
`once((a, 1))` gibt jetzt wie ISO `type_error(callable, (a,1))` (vorher
`existence_error` für `a/0`), und ein beim Aufruf ungebundenes Ziel im
Rumpf wird `call(G)` mit lokalem Cut.

`current_prolog_flag/2` mit gebundenem Namen liest das Flag direkt und
deterministisch (Aufzählen und Fehler wie bisher über das Builtin):
30–60 % schneller. Die Standardwerte der Flags liegen als fertige
Prolog-Terme vor (vorher bei jedem Lesen neu gebaut): `Flags.get/1`, das
intern oft läuft (`swi_compat` bei jeder Heimat-Prüfung, `unknown`,
`double_quotes`), wurde dadurch rund 28 % schneller.

Allgemein werden Ziele aus Daten jetzt wie bei `call/1` zum Rumpf (ISO
7.6.2) – auch `M:Rumpf` (`call/1` stieg bisher nicht hinein) und bei
`\+`, `findall/3`, `findnsols/4,5`, `countall/2`, `catch/3`, `forall/2`,
`call_nth/2`, den Grenzen und `time/1` (sie führten das Ziel bisher roh
aus): beim Aufruf ungebundene Variablen innen werden `call(V)` (Cut darin
lokal, `findall(x, ((G = !, G, fail) ; true), L)` gibt `L = [x]` wie
SWI), gebundene werden eingesetzt, nicht Aufrufbares gibt
`type_error(callable, _)` vor jeder Ausführung. Ohne eigenen
`call`-Schritt umgewandelt: keine messbaren Kosten.

Dasselbe Vorfiltern nutzen `retract/1` und `retractall/1`: Geprüft
(kopiert und unifiziert) werden nur Klauseln, die zum ersten Argument
passen können. `retractall/1` ohne Treffer lässt das Prädikat samt Index
unverändert (vorher wurde der Index danach neu gebaut). Gezieltes
Ersetzen in 1000 Fakten (`retract(fakt(500, _)), assertz(fakt(500, w))`)
wurde dadurch rund 6-mal schneller, `retractall/1` ohne Treffer mit
anschließendem Aufruf rund 50-mal.

Nach `assertz/1` erweitert der nächste Aufruf den Index, statt ihn neu
zu bauen; die neue Klausel hinten an die Listen aller Klauseln
anzuhängen, kostete dabei aber O(n) – im Wechsel von `assertz` und
Aufruf (Memo-Tabellen) quadratisch. Jetzt wird das Anhängen aufgeschoben
(`{:cat, liste, hinten_umgekehrt}`); flach gemacht wird erst, wer die
ganze Liste braucht – ein Aufruf mit offenem erstem Argument (einmal,
mit Zurückschreiben) oder `clause/2`, `retract/1`, `listing/1`. Ein
Aufruf mit gebundenem erstem Argument braucht nur den Index nach
Schlüssel: `assertz(m(I, I)), m(I, _)` für 20 000 Werte 4,4 s → 0,14 s.

Bekannte Grenze: Liest nach *jeder* Änderung ein Aufruf eine Klauselliste
in Reihenfolge, in die hinten etwas dazugekommen ist, kostet das je
Aufruf O(n) – also quadratisch insgesamt. Das betrifft `assertz` im
Wechsel mit Aufrufen mit offenem erstem Argument und `assertz` vieler
Klauseln mit *demselben* ersten Argument im Wechsel mit Aufrufen darauf
(dort wächst die Liste dieses Schlüssels im Index). Linear sind
dagegen: `asserta`/`assertz` in beliebiger Mischung ohne Aufrufe
dazwischen und im Wechsel mit Aufrufen mit gebundenem, verschiedenem
erstem Argument. Der Ausweg, falls ein Programm das braucht: Klausel-
listen veränderter dynamischer Prädikate als Stücke nach der
logarithmischen Methode (Puffer hinten, gleich große Stücke
zusammenlegen) – `assertz` amortisiert O(log n), Durchlaufen nahe an der
Liste (etwa 2–4 statt 1,5 ns je Klausel; Map oder `gb_trees` mit
Positionen: rund 19 ns), statische Prädikate unverändert (in
`try_clauses` liegt der Fall hinter dem Listenfall, der Normalfall bleibt
ein einziger Test).

## Entwicklung

```sh
mix test                  # Tests
mix run bench/bench.exs   # Speicher- und Laufzeitmessung
```
