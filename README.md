# prolog-ex
Elixir does Prolog!

Ein Prolog-Kern in Elixir:

- Unifikation über persistente Substitutions-Maps, eine zentrale `bind/3`.
  Alle Zugriffe auf die Substitution (Verfolgen und Binden von Variablen,
  Attribute, Weck-Vermerk, Ebene von `call_with_depth_limit/3`,
  backtrackbares Blackboard, Festhalten für Choice Points) laufen über
  `PrologEx.Store`; Maschine, Builtins und Kompaktierung kennen die
  Darstellung nicht. Ein veränderlicher Speicher mit Trail (Marke je
  Choice Point, Zurückspulen statt Kopieren) wäre damit ein Austausch
  dieses einen Moduls. Kosten der Schnittstelle: keine messbaren
  (Reduktionen ±1 %, Laufzeit im Rauschen).
  Ausprobiert und verworfen (Branch `trail-store`): genau dieser
  Austausch – Prozesswörterbuch mit Trail, Marken statt Schnappschüsse,
  Zurückspulen statt Kopieren, Aufräumen statt Neuaufbau. Alle Prüfungen
  bestehen, aber er ist langsamer: nrev 314 → 530 ms, loop 555 → 946 ms,
  tak 209 → 349 ms, n_queens(60) in clpz +25 %, die clpz-Beispiele +3 bis
  +20 % (einzig queens(8, alle) 87 → 71 ms). Eine Bindung kostet dort drei
  Wörterbuchzugriffe statt eines Map-Eintrags, das Aufräumen ist
  O(Schreibvorgänge) statt O(lebende Daten), und weil die Kompaktierung die
  lebenden Substitutionen klein hält, ist die persistente Map ohnehin im
  Vorteil; der Mikrobenchmark (Binden in einen 100 000-Einträge-Speicher
  zehnmal billiger) hat die Maschine nicht abgebildet. Was der Versuch
  nebenbei gezeigt hat: wo die Maschine Substitutionen probeweise ändert
  und verwirft (gescheiterte oder Probe-Unifikation, Unter-Maschinen,
  clpz-Fallbacks), ist nun dokumentiert – `PrologEx.unifiable?/3`,
  `unifiable_all?/2` fassen die Proben zusammen.
- Listen als native BEAM-Cons-Zellen (`'.'(H,T)` = `[H|T]`)
- Klauseln werden beim Laden in eine WAM-artige IR kompiliert
  (`lib/prolog_ex/compiler.ex`): Variablenklassifikation, Read-/Write-Modus
  im Kopf, Rumpf wird erst nach passendem Kopf gebaut. Ziele `X = V`
  zweier Variablen, deren V nur noch in den folgenden Zielen derselben
  Konjunktion vorkommt, fallen dabei weg (V wird zu X) – etwa die Ketten
  `S0 = S1` aus DCG-Übersetzungen; `clause/2` und `listing/1` zeigen die
  Quelle. Ein DCG-Zahlenparser −10 % Reduktionen, die clpz-Beispiele
  −1 bis −4 %. Ebenso wandert eine Unifikation `V = T` am Anfang des
  Rumpfs in den Kopf, wenn V eine Kopfvariable ist und in T nicht vorkommt
  (sie geschähe ohnehin gleich nach dem Kopf): jede DCG-Regel, die mit
  einem Terminal beginnt, spart so einen Schritt (`S0 = [X|S1]` wird
  Kopfmuster), und `p(X) :- X = a, …` bekommt einen Index. Eine DCG über
  eine Liste von 200 000 Elementen −31 bis −42 %
- JIT für deterministische Prädikate über Zahlen und Listen (Flag `jit`,
  Vorgabe `true`; beim Laden aus: nichts übersetzt, beim Aufruf aus: der
  Interpreter rechnet – so lässt sich in einer Sitzung vergleichen):
  in BEAM-Code übersetzt, die Werte in Erlang-Variablen
  statt in Bindungen. fib(23) 390 → 1–2 ms, eine Zählschleife über 10⁶
  1,1 s → 9 ms, eine nicht endrekursive Summe über 200 000 1,6 s → 5 ms,
  eine Float-Rekursion 1,3 s → 28 ms, nrev über 500 Elemente
  190 → 3 ms (≈ 40 Mio. LIPS), app/len/sum/rev über 300 000 Elemente
  2,6 s → 50 ms.
  - Was übersetzt wird – jede Klausel: im Kopf Zahlen, Variablen, `[]`
    und `[E1, …, En | T]` (E Zahlen oder Variablen); im Rumpf `is`,
    arithmetische Vergleiche, `X = Y` (Terme wie im Kopf), `!`, `true`,
    `fail`, `( C -> T ; E )`, `( C -> T )`, `\+ G`, Typtests (`var`,
    `nonvar`, `atom`, `number`, `integer`, `float`, `atomic`, `compound`,
    `callable`, `is_list`), `==`, `\==` und Aufrufe von sich selbst oder
    anderen übersetzten Prädikaten desselben Moduls; alle
    auswertbaren Funktoren außer `random`/`random_float` (dazu `pi`, `e`,
    `epsilon`). Je zwei Klauseln müssen sich nachweislich ausschließen
    (Schnitt in der früheren, verschiedene Muster – Konstanten, `[]`
    gegen `[_|_]`, auch `X = 0` am Anfang des Rumpfs –, ein Vergleich am
    Anfang, der für die Konstante der anderen falsch ist, einander
    ausschließende Vergleiche wie `X > 0` / `X =< 0`, oder Typtests und
    Muster ohne Gemeinsames wie `integer(X)` / `float(X)` / `[]`; davor
    darf in der späteren Klausel nichts werfen können). Eine Variable, die nur ein
    Zweig eines If-then-else bestimmt, darf danach nicht mehr vorkommen.
  - Modi und Typen: steht eine Kopfvariable zuerst in einem Vergleich
    oder rechts in `is`, ist sie Eingabe, links in `is` Ausgabe, als
    Argument eines Aufrufs wie dort; die übrigen Positionen werden
    durchprobiert (mehr Ausgaben zuerst, Ausgaben eher rechts: app/3 wird
    app(+, +, -)). Ein Wert ist eine Zahl, eine Liste, eine Liste von
    Zahlen oder beliebig – dann wird er nur durchgereicht, auch als
    ungebundene Variable (app([1], X, L) gibt L = [1|X]). Was ein Wert
    sein muss, folgt aus dem Gebrauch (gerechnet, zerlegt, verglichen);
    Ausgabetypen dürfen von Eingaben abhängen (app/3 gibt eine Liste,
    wenn das zweite Argument eine ist).
  - Typtests: auf einer Zahl meist schon beim Übersetzen entschieden,
    sonst zur Laufzeit wie im Interpreter; nach `integer(X)` (im Code mit
    Floats auch `float/number`) ist X eine Zahl, mit der gerechnet werden
    darf – eine Eingabe, die nur getestet wird, wird beim Aufruf nicht
    geprüft. Ein Typtest als erstes Ziel auf dem ersten Kopfargument zählt
    wie im Interpreter nur bei ungebundenem Argument (dort übernimmt ihn
    der Index). Weil der übersetzte Code Ausgaben erst am Ende bindet,
    gibt er auf, wenn ein Typtest oder `==` auf eine Ausgabevariable des
    Aufrufs stößt (`p(X, Y) :- Y = 1, var(X)` mit `p(A, A)`): der
    Interpreter hätte sie schon gebunden. 200 000 gemischte Elemente nach
    Typ zählen: 1,5 s → 50 ms.
  - Listen werden erst beim Zerlegen gelesen – so weit wie der
    Interpreter auch (`first([X|_], X)` liest eine Zelle, nicht die ganze
    Liste). Stößt der Code auf etwas, das er nicht kann (ein offener Rest,
    ein Element, das keine Zahl ist), gibt er auf: er hat nichts gebunden,
    die Inferenzen werden zurückgesetzt, und der Interpreter fängt den
    Aufruf neu an (und meldet etwa denselben Fehler).
  - Rechnet alles, was sich gegenseitig ruft, nur mit Ganzzahlen und
    ganzzahligen Operationen (+ - * // mod rem div min max >> << /\ \/
    xor gcd abs sign msb \), rechnet der Code + - * direkt und nimmt
    ganzzahlige Eingaben; sonst alles über dieselben Funktionen wie der
    Interpreter (Floats, auch rationale Zwischenwerte).
  - Die Prädikate eines Ladeschritts werden zusammen analysiert;
    wechselseitig rekursive teilen sich ein Modul. Gerufen werden dürfen
    auch schon übersetzte statische Prädikate früherer Schritte, direkt.
    Wird ein Gerufener neu geladen (oder dynamic/1), verlieren seine Rufer
    ihren Code und rufen die neue Fassung über den Interpreter;
    dynamische Prädikate ruft übersetzter Code nie.
  - Beim Laden wird nur analysiert (clpz: im Rauschen); der
    BEAM-Compiler läuft beim ersten Aufruf. Die Module heißen nach einem
    Hash der Zwischenform mit kanonisch benannten Variablen: dasselbe
    Programm neu geladen nimmt das vorhandene Modul. Lässt sich eines nicht
    übersetzen (Grenzen der BEAM), rechnet der Interpreter.
  - Benutzt wird der Code nur, wenn der Aufruf passt (Eingaben vom
    richtigen Typ, Ausgaben verschiedene frische Variablen ohne Attribute,
    keine Tiefengrenze) und das Prädikat wenigstens ein Ziel hat – bei
    einem Fakt kostet der Wechsel mehr, als er spart (übersetzt wird er
    trotzdem, für übersetzte Rufer). Die Ausgaben werden unifiziert (sie
    dürfen in Eingaben vorkommen, samt Occurs-Check wie sonst). Kosten,
    wo es nicht passt: eine rekursive DCG-Regel über `phrase/2` (der Rest
    ist dort `[]`, gebunden) prüft je Aufruf vergeblich, +2 % Reduktionen.
  - `jit_listing/0,1` zeigt je Prädikat eines Moduls, ob es übersetzt ist
    (Modi und Typen, etwa `app(+list, +any, -)`) oder warum nicht
    („Klausel 2: Ziel is_list/1“, „Klauseln 1 und 2 schließen sich nicht
    nachweislich aus“, „ruft r/2, das nicht übersetzt wird“).
  - Gleich wie im Interpreter: Antworten, Fehler, Inferenzen und Grenzen
    (Inferenz-, Zeit-, Speichergrenzen an denselben Prüfpunkten,
    spätestens alle 65 536 Inferenzen). Zwei Unterschiede, beide zum
    Besseren: das übersetzte Prädikat hinterlässt keine Choice Points
    (`call_with_inference_limit/3` gibt `!` statt `true`), und beim
    Zurücksetzen zählt es keine Versuche von Klauseln, die ohnehin nichts
    finden.
  - Tiefe Rekursion: jede Garbage Collection durchsucht den ganzen Stack.
    Darum legt Scheitern im übersetzten Code nichts auf den Heap (die
    Summe über 200 000 100 → 10 ms), und ist der Stack an einem Prüfpunkt
    tief, bekommt der Heap Luft im Verhältnis (`min_heap_size`, nach dem
    Aufruf wieder wie vorher): eine Summe von Quadraten mit einem
    Hilfsprädikat 110 → 12 ms
- Deterministische eingebaute Ziele am Anfang eines Rumpfs (`is`,
  arithmetische Vergleiche, `=`, `==`, `\==`, Typtests, ein Neck-Cut)
  laufen gleich beim Eintritt in die Klausel, direkt aus den Vorlagen –
  ohne Term, Zielstapel und Schritt-Schleife; Inferenzen, Grenzen,
  Weckziele und Fehler wie sonst. Zählschleifen −8 %, eine DCG −14 %
  (BEAM-Reduktionen; die Zeit schwankt mehr)
- Wächter im Index: beginnt ein Rumpf mit einem Typtest auf die Variable
  des ersten Kopfarguments (`integer/1`, `float/1`, `number/1`, `atom/1`,
  `atomic/1`, `compound/1`, `callable/1`, `var/1`), lässt der Index die
  Klausel für Argumente anderen Typs weg – auch für Werte, die in keinem
  Kopf stehen (je Typklasse eine Restliste, beim Laden berechnet). Typ-
  Verzweigungen werden so deterministisch, auch ohne Schnitt; eine
  Verzweigung über drei Typen −54 % (ohne Schnitt) bzw. −26 % (mit).
  Prädikate ohne Wächter: unverändert. `clause/2` und `retract/1` wählen
  nach dem Kopf der Quelle
- Fassungen je Kandidatenliste (beim Laden): in einer Liste, deren
  Typklasse ein Wächter sicher erfüllt, fällt der Typtest weg; und ist eine
  Klausel der letzte Kandidat ihrer Liste und stehen vor einem Schnitt nur
  Typtests, fällt der Schnitt weg – er schnitte nichts ab (auch
  `f([]) :- !, … . f([H|T]) :- !, …`). Aufrufe mit ungebundenem erstem
  Argument nehmen die vollständigen Klauseln. Eine Typ-Verzweigung mit
  Wächter und Schnitt −17 bis −20 %, so schnell wie eine ohne beides.
  Ein assert auf ein solches Prädikat baut den Index einmal schlicht neu
  (ohne Wächter und Fassungen), danach wird er wie sonst erweitert
- explizite Ziel- und Choice-Point-Stacks mit Last-Call-Optimierung,
  vorberechneter Index nach dem ersten Argument. Der Zustand der Maschine
  ist ein Struct mit ~25 Feldern; je Inferenz wird er genau einmal
  aktualisiert (Choice Point, Variablenzähler, Ziele und Substitution in
  einem Update statt in dreien, jedes eine Kopie) – nrev, loop, between
  −3 bis −6 %, facts −10 %
- Kompaktierung der Bindungen: konstanter Speicher bei endrekursiven Schleifen.
  Sie läuft früh (ab 256 Bindungen, danach beim Doppelten der lebenden
  Nicht-ground-Knoten) und kostet ohne `call_nth/2`/`time/1` nichts je
  Choice Point: nicht mehr erreichbare Zwischenstände (etwa die Bäume
  `A0, A1, …` einer `foldl`-Schleife mit `put_assoc/4`) halten so die
  Speicherbereinigung nicht auf – dort rund 40 % schneller, endrekursive
  Rechenschleifen 6–18 %.
- Geteilte Teilterme (DAGs wie `T1 = f(T0,T0), T2 = f(T1,T1), …` oder die
  Knoten eines BDDs) bearbeitet jede Operation, die Terme abläuft, nur
  einmal: Kompaktieren, Auflösen, Kopieren (`copy_term/2,3`, `findall`,
  `bagof`/`setof`, `throw/catch`), Variablen sammeln (`term_variables`,
  `numbervars`, Attribute), `ground`, `acyclic_term`, Vergleichen (`==`,
  `compare/3`, `sort`/`msort`), Unifizieren (auch mit Occurs-Check),
  `subsumes_term` und `dif`. Kopien bleiben geteilt. Erkannt wird ein
  geteilter Teilterm an der physischen Identität (`:erts_debug.same/2`,
  Modul `PrologEx.Share`): ein Memo je Durchlauf, das erst nach den ersten
  32 Strukturen wirkt (kleine Terme zahlen nur einen Zähler) und nur
  Strukturen mit einem zusammengesetzten Argument aufnimmt. Ein Treffer
  verlangt Identität, das Ergebnis ist also immer dasselbe wie ohne Memo;
  fehlt die Funktion, wird ohne Memo gerechnet. Vorher wuchs der Aufwand
  mit der Zahl der Pfade (bei 24 Stufen lief der Speicher über; 8 Damen
  mit `library(clpb)` brach deshalb ab), jetzt mit der Zahl der Knoten:
  Ketten mit 2^40 Pfaden in Millisekunden (`test/share_test.exs`), wie in
  Scryer. Ausgenommen ist `assert` (die Klausel wird ausgerollt
  gespeichert; in Scryer ebenso). Das Memo ist eine Heuristik (je
  Schlüssel nur die letzten Einträge); in Messungen kostet es auf
  gewöhnlichen Termen nichts Messbares (Fakten, `findall`, `sort`/`msort`
  im Rahmen des Rauschens oder schneller). Bei `==` auf Listen kommt nur
  die erste Zelle ins Memo; die Folgezellen mit flachem Kopf (Zahl, Atom,
  Struktur mit atomaren Argumenten) laufen ohne, denn sie verzweigen nicht
  (eine Struktur wie `f(L, L)` mit `L` als Variable ist selbst nicht im
  Memo – dort schützt die erste Zelle von `L`). Lange Listen, etwa
  clpz-Domänen mit vielen Intervallen, zahlten vorher einen Memo-Eintrag
  und eine Closure je Zelle: sieve(5000) 1,09 → 0,37 s, Reduktionen
  sieve(2000) −34 %.

## Loslegen

Voraussetzung: nur Elixir (ab 1.18.4) auf Erlang/OTP 28 oder neuer (`mix`
bricht sonst mit einer Meldung ab). Gelesen und ausgeführt wird
alles in Elixir; keine weiteren Programme, keine Abhängigkeiten.

```sh
mix compile                          # übersetzen
mix prolog                           # interaktiver Toplevel
mix prolog examples/demo.pl          # Datei laden, dann Toplevel
mix prolog examples/demo.pl -g main -q   # laden, main ausführen, Ende
                                     # (-q: still, auch beim Laden)
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

**Zyklische Terme (rationale Bäume):** Ohne Occurs-Check (Flag
`occurs_check` = `false`, Standard) macht `X = f(X)` einen zyklischen Term.
Der Toplevel zeigt ihn wie SWI, statt endlos aufzulösen:

```
?- X = f(Y), Y = g(X).
X = f(g(X)), Y = g(X).
?- X = [a|_T], _T = [b|_T].
X = [a|_T], _T=[b|_T].           % Zyklus über eine nicht gezeigte Variable
```

Was mit zyklischen Termen geht (wie SWI):

* **Unifizieren** (`A = f(A), B = f(f(B)), A = B` gelingt), **Vergleichen**
  (`==`, `compare/3`, `sort`/`msort`/`keysort`, Standardordnung koinduktiv:
  ein Paar, das gerade schon verglichen wird, gilt als gleich), `dif/2`,
  `subsumes_term/2`, `ground/1`, `term_variables/2`, `numbervars/3`.
* **Kopieren mit Zyklus:** `copy_term/2`, `findall/3,4`, `findnsols`,
  `bagof`/`setof`, `throw/1`–`catch/3` (auch aus `findall` heraus).
* **Ausgabe** (`write`, `print`, `writeq`, `format`, `write_term`, ...) wie
  SWI als `@(Vorlage, Gleichungen)`: `A = f(A), write(g(A))` schreibt
  `@(g(_S1),[_S1=f(_S1)])`.
* `cyclic_term/1` (library(swi)), `acyclic_term/1`; `length/2` einer
  zyklischen Liste: `type_error(list, L)`.
* **Fehler statt Endlosschleife,** wo das Ergebnis keinen Zyklus darstellen
  kann: `assertz` u. a. `representation_error(cyclic_term)`, Arithmetik
  (`X = X + 1, Y is X`) `type_error(acyclic_term, _)`. Die Kompaktierung
  der Bindungen behält lebende Zyklen.

Erkannt wird ein Zyklus ohne Vorab-Prüfung: Ein Durchlauf zählt auf dem
aktuellen Pfad, wie oft er über eine Bindung ging. In einem endlichen Term
liegt jede Bindung höchstens einmal auf einem Pfad (zwei Terme
nebeneinander: zweimal); mehr, als die Substitution Einträge hat, heißt
Zyklus. Dann rechnet eine zyklenfeste Fassung von vorn (Modul
`PrologEx.Cyclic`), die nur zyklische Terme bezahlen. Endliche Terme zahlen
je Bindung auf dem Pfad einen Vergleich: gemessen (A/B gegen den Stand
davor) unter 1 % bei üblichen Programmen; reines Unifizieren bzw. Kopieren
langer, über Bindungen gebauter Listen +4 bis +7 %. Ein vorgeschaltetes
`acyclic_term/1` hätte so viel gekostet wie `copy_term/2`. Restziele
(`freeze`, `dif`, clpz) zeigt der Toplevel bei einer zyklischen Antwort
nicht; `library(concurrent)` nimmt keine Zyklen
(`representation_error(cyclic_term)`).

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
`evaluation_error(zero_divisor)`, `0 ^ -1` ist nach Cor.2
`evaluation_error(undefined)`, siehe `PrologEx.Arith`; `is/2` und
Vergleiche im Klauselrumpf übersetzt der Compiler in einen Codebaum, statt
den Ausdruck bei jedem Aufruf als Term zu bauen – 4–13 % schneller,
gleiche Werte und Fehler), Typprüfungen, `functor/3`, `=../2`, `append/3`, `length/2`, `member/2`, `select/3`, `permutation/2`, `memberchk/2`, `last/2`, `reverse/2`,
`proper_length/2`, `sum_list/2`, `max_list/2`, `min_list/2`, `max_member/2`,
`min_member/2`, `delete/3`, `list_to_set/2`, `nextto/3`, `subtract/3`,
`intersection/3`, `union/3`, `include/3`, `exclude/3`, `partition/4`, `foldl/4..6`,
`same_length/2`, `'$skip_list'(Len, List, Rest)` (wie SWI: überspringt
Len Zellen; Rest ist `[]`, eine Variable, ein anderer Term oder bei einer
zyklischen Liste eine Zelle im Zyklus – Brents Zykluserkennung, terminiert
immer; dieselbe Funktion liegt `length/2` und Co. zugrunde), eigene:
`list_frequencies(+L, ?F)` (`list_frequencies([a,a,b,c,c,b,a,b], [a-3,b-3,c-2])`,
Reihenfolge des ersten Vorkommens) und `list_runs(+L, ?R)`
(`list_runs([a,a,b,c,c,b,a,b], [2-a,1-b,2-c,1-b,1-a,1-b])`) – gleich heißt
`==/2`, deterministisch; `list_runs/2` in einem Durchgang (O(n)),
`list_frequencies/2` über eine stabile Sortierung (O(n log n)); aus SICStus' `library(lists)`: `same_length/3` (negatives N scheitert), `one_longer/2`,
`shorter_list/2`, `keys_and_values/3`, `transpose/2` (rechteckig, in beide
Richtungen; leere Matrizen – keine Zeile oder keine Spalte – scheitern),
`partition/5` (`call(P, X, R)`, R ∈ {`<`,`=`,`>`}),
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
`occurs_check`, `clpz_residuals`, `stack_limit`), `unify_with_occurs_check/2`, `acyclic_term/1`, `clause/2`,
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

Zahlen im Quelltext: Zifferntrenner wie von WG17 2025 angenommen
(`1_000_000`; nach `_` darf Layout-Text folgen, also Leerraum, Zeilenumbruch
oder ein Kommentar: `1_ /* … */ 000`; auch in `0b…`, `0o…`, `0x…` und
in den Nachkommastellen, `1_000.000_1`; kein doppeltes `__`) und Ganzzahl-Literale beliebiger Größe.

### Rationale Zahlen

Brüche wie in SWI: `1r3`, `-7r2` (gelesen auch mit Zifferntrennern im
Nenner, `1_000r3`; `1r0` ist ein Syntaxfehler), immer gekürzt – `2r6` ist
`1r3`, `4r2` die Ganzzahl `2`. Sie sind atomar: `number/1`, `atomic/1`
und `rational/1` gelingen, `integer/1`, `float/1` und `compound/1` nicht;
`rational(X, N, D)` zerlegt (auch Ganzzahlen: `D = 1`).

  * **Rechnen:** Ganzzahlen und Brüche bleiben exakt (`+ - * /`, `rdiv`,
    `min`, `max`, `abs`, `sign`, `^` und `**` mit ganzzahligem Exponenten:
    `X is 2r3 ** -2` gibt `9r4`); ein Float macht alles zum Float
    (`1r3 + 0.5`). `floor`, `ceiling`, `truncate`, `round` (wie für Floats
    `floor(X + 1/2)`) und `integer` (Hälften weg von 0) geben Ganzzahlen,
    `float/1` den nächsten Float (korrekt gerundet, auch bei riesigen
    Zählern und Nennern). Neu: `rdiv/2` (Operator 400 `yfx` wie in SWI),
    `rational/1` (exakter Wert eines Floats: `rational(0.1)` ist
    `3602879701896397r36028797018963968`), `rationalize/1` (einfachster
    Bruch, der denselben Float ergibt: `1r10`), `numerator/1`,
    `denominator/1`. Ganzzahl-Operationen (`//`, `mod`, Bitoperationen, …)
    geben `type_error(integer, 1r3)`.
  * **Flag `prefer_rationals`** (Vorgabe `false` wie SWI): mit `true` gibt
    `/` auf Ganzzahlen einen Bruch statt eines Floats (`1/3` → `1r3`), ebenso
    `2 ** -1` und `2 ^ -1` (sonst `0.5` bzw. `type_error`). Der Compiler
    rechnet solche Ausdrücke darum erst zur Laufzeit aus.
  * **Vergleiche:** exakt, außer wenn ein Float beteiligt ist (dann über
    Floats, wie bei Ganzzahl und Float). **Standardordnung:** alle Floats
    vor allen Ganzzahlen und Brüchen (wie bisher Floats vor Ganzzahlen),
    Ganzzahlen und Brüche untereinander nach Wert: `[0.9, -1r2, 1r3, 1, 2]`.
    Die Sortierschlüssel von `sort/2` & Co. bilden den Wert über den
    Kettenbruch exakt ab.
  * **Text:** `write/1`, `writeq/1`, `format/2` (`~w`; `~Nf` exakt:
    `format("~2f", [10^30 rdiv 3])` schreibt alle Stellen),
    `number_codes/2`, `atom_number/2`, `term_to_atom/2` – `1r3` hin und
    zurück; `fast_write/2` und `fast_term_serialized/2` ebenso.
  * Brüche gehen überall durch: Unifikation, `assert`, `findall`,
    Ausnahmen, `term_hash/2`, `concurrent_maplist/3`, `dif/2`. clpz nimmt
    keine (`domain_error`).
  * Programme ohne Brüche zahlen nichts: Ganzzahl- und Float-Arithmetik
    laufen über dieselben Klauseln wie vorher, Brüche haben eigene dahinter.

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
    `nl/0,1`. Textstreams sind UTF-8; ein ungültiges Byte ist kein
    Zeichen: `get_char`, `peek_char`, `get_code`, `peek_code` und
    `read_term` geben `representation_error(character)` (Neumerkel stc
    #76; `get_*` verbraucht das Byte, danach geht es weiter). Beim Laden
    einer Datei ist es ein Syntaxfehler – Latin-1-Quelltexte vorher nach
    UTF-8 umwandeln.
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
    jeden Teilterm. `user:portray/1` ist wie in SWI vordeklariert
    (`dynamic`, `multifile`): ohne Klauseln scheitert ein Aufruf nur.

## Grammatiken über Dateien: `library(pio)`

Reine Eingabe wie in SWI und Scryer: `phrase_from_file(G, Datei)` wendet
die DCG `G` auf den Inhalt der Datei an, ohne ihn vorher ganz einzulesen.
Die Liste ist faul: ihr ungelesener Rest wartet mit `freeze/2`, und erst
wenn die Grammatik ihn braucht, kommt der nächste Block (256 Zeichen)
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
  Bei `phrase_to_file/2,3` nimmt Backtracking das Geschriebene zurück:
  jede Lösung schreibt ab der Stelle, an der die vorige begonnen hat (die
  Datei wird dort abgeschnitten). `phrase_to_file(({between(1,3,X),
  number_chars(X,Cs)}, seq(Cs)), F)` mit `;` bis X = 3 hinterlässt `3`,
  nicht `123` (Scryer, SWI). Endet die Grammatik deterministisch, wird
  dort geschlossen und die letzte Lösung bleibt; bleibt ein Choice Point
  und werden alle Lösungen erschöpft, ist die Datei am Ende leer. Die
  gemerkte Position steht backtrackbar in der Substitution (wie
  `b_setval/2`), es entsteht kein zusätzlicher Choice Point.
* `phrase_to_stream/3` macht dasselbe auf einem offenen Stream:
  zurückgenommen wird bis zur Stelle, an der der Aufruf begonnen hat
  (davor und nach dem endgültigen Erfolg Geschriebenes bleibt; nach dem
  Erschöpfen aller Lösungen steht der Stream wieder dort). Option
  `undo(B)`, auch für `phrase_to_file/3`: `true` – zurücknehmen
  (`permission_error(reposition, stream, S)`, wenn der Stream es nicht
  kann), `false` – stehen lassen wie Scryer; ohne die Option: zurücknehmen,
  wo es geht. Das geht bei Dateien, die sich positionieren lassen
  (Vorgabe bei `open/4` mit `write` oder `append`), nicht bei Terminal,
  Pipes oder Speicher-Streams. `phrase_to_stream/2` (und damit `format/3`)
  bleibt wie Scryer.

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

## Byte-Folgen: `library(bytes)`

Ein eigener atomarer Typ für Bytes, ein BEAM-Binary: ein Byte je Byte (eine
Code-Liste braucht 16), Länge und Zugriff in O(1), ein Teilstück ist ein
Verweis ohne Kopie, und ab 64 Bytes teilen Prozesse die Daten, statt sie zu
kopieren – Kinder von `library(concurrent)` bekommen eine große Folge
umsonst.

```prolog
?- read_file_to_bytes('log.txt', B), bytes_length(B, N),
   bytes_utf8(P, "ERROR"), aggregate_all(count, bytes_search(P, B, _), K).
```

  * Typ: `bytes/1`. Wie eine Zahl atomar (`atomic/1` ja, `atom/1`,
    `callable/1` nein); Unifikation und `==` vergleichen den Inhalt; in der
    Standardordnung nach den Atomen und vor dem Zusammengesetzten,
    untereinander Byte für Byte (ein Präfix zuerst)
  * Umwandeln (in beide Richtungen): `bytes_list/2` (0..255),
    `bytes_utf8/2`, `bytes_latin1/2` (Text als Zeichen, umgekehrt auch Codes
    oder ein Atom), `bytes_hex/2`, `bytes_base64/2`
  * `bytes_length/2`, `bytes_at/3` (Position ab 0; frei: alle),
    `sub_bytes/5` (wie `sub_atom/5`), `bytes_concat/3` (die Verbindung
    gegeben: alle Teilungen), `bytes_concat_list/2`, `bytes_search/3` (jedes
    Vorkommen, auch überlappend)
  * Bits (Bit 0 ist das höchste Bit des ersten Bytes, wie Erlangs
    Bit-Syntax): `bytes_and/3`, `bytes_or/3`, `bytes_xor/3` (gleich lang,
    sonst `domain_error(same_length, B)`), `bytes_not/2`,
    `bytes_popcount/2`, `bytes_bit(I, B, Bit)` (I frei: alle),
    `bytes_set_bit(I, B0, Bit, B)` (eine neue Folge, O(n)), dazu
    `bytes_fill(N, Byte, B)` für eine Folge aus N gleichen Bytes. Und, oder,
    xor und nicht laufen in C (als große Ganzzahlen, in Stücken zu 64 KB):
    20 Mbit in 7–24 ms, popcount in 2 ms
  * Dateien und Binär-Streams: `read_file_to_bytes/2`, `write_bytes/2`,
    `get_bytes/3` (höchstens N Bytes; am Ende die leere Folge); diese drei
    sind Ein-/Ausgabe für `call_with_no_side_effects/1`

Kein Literal (noch offen, wie es sich mit der ISO-Syntax verträgt):
`write/1` und `writeq/1` geben `'$bytes'(Länge)` aus, das nicht wieder als
Byte-Folge einlesbar ist (wie `'$stream'(N)`). Was zum Wiedereinlesen
geschrieben wird – `listing/0,1` (auch das aus `library(format)`) und
`portray_clause/1,2` – verweigert darum Byte-Folgen mit
`representation_error(bytes)`, bevor es etwas ausgibt, statt still eine
Struktur zu schreiben. Speichern geht mit `fast_write/2` und
`fast_term_serialized/2`. Fehler: keine Folge
`type_error(bytes, X)`, ein Byte außerhalb 0..255 `type_error(byte, X)`,
ungültiges UTF-8 und Zeichen über 255 bei Latin-1
`representation_error(character)`, ungültiges Hex oder Base64
`domain_error(hex_encoding | base64_encoding, Text)`.

Gemessen (20 MB, rund 206 000 Treffer zählen): seriell 819 ms, verteilt auf
acht Kinder über `sub_bytes/5` 238 ms – als Code-Liste wären es 320 MB, die
jedes Kind kopieren müsste.

### DCGs über Byte-Folgen: `library(dcg/bytes)`

Eine gewöhnliche Grammatik liest eine Byte-Folge als faule Liste, wie
`phrase_from_file/2` eine Datei: der noch nicht ausgepackte Rest wartet mit
`freeze/2`, erst beim Lesen kommt der nächste Block (256 Bytes) dazu.
Terminale (`[X]`, `"..."`), `seq//1`, `...//0` und `library(dcg/high_order)`
laufen unverändert; vorausliegende Bytes werden nie ausgepackt, und nach
dem Rücksetzen wird ein Block einfach neu erzeugt (die Byte-Folge ist
unveränderlich).

```prolog
gif(W, H) --> "GIF89a", u16le(W), u16le(H).

?- read_file_to_bytes('bild.gif', B), phrase_bytes(gif(W, H), B, Rest).
```

  * `phrase_bytes(G, B)`, `phrase_bytes(G, B, Rest)` (Rest wieder als
    Byte-Folge, ohne Kopie), `phrase_bytes(G, B, Rest, Optionen)`,
    `bytes_to_lazy_list(B, Sicht, L)`
  * Sichten `as(codes)` (Zahlen 0..255), `as(latin1)` (ein Zeichen je
    Byte: 71 ist `'G'`), `as(utf8)` (dekodierte Zeichen; ungültig:
    `representation_error(character)`). Ohne Angabe wie `library(pio)` nach
    `double_quotes`: `codes` bei `codes`, sonst `latin1` – so passt
    `"GIF89a"` in der Grammatik zur Liste. Für Binärformate, die Zahlen und
    Text mischen, ist `double_quotes = codes` am bequemsten (`[137]` passt
    in der Sicht `latin1` nicht, `u8(137)` in beiden)
  * Für Binärformate: `u8//1`, `s8//1`, `u16le//1`, `u16be//1`, `s16le//1`,
    `s16be//1`, `u32le//1`, `u32be//1`, `s32le//1`, `s32be//1`,
    `take(N, B)//` (die nächsten N Bytes als Byte-Folge), `eos//0`

Zum Zerlegen, nicht zum Erzeugen (`phrase_bytes/2` mit freier Byte-Folge
geht nicht). Wie bei `library(pio)` liegt der gelesene Teil vorübergehend
als Liste vor; was kein Choice Point mehr braucht, räumt die Kompaktierung
weg, die Byte-Folge selbst bleibt kompakt. Beispiele (GIF, PNG in Chunks,
ein Sieb auf einer Bitmenge): `examples/bytes.pl`.

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

## HTTP: `library(http/http_open)`, `library(http/http_server)`

Wie in Scryer Prolog, mit derselben Schnittstelle; Programme für Scryers
HTTP-Bibliotheken laufen unverändert. Die Prolog-Teile sind Scryers
Quelltext (`priv/library/http/`), die Teile, die bei Scryer in Rust
stecken (reqwest, Warp), sind hier in Elixir: der Client über `:httpc`
aus OTP, der Server als kleiner HTTP/1.1-Server
(`PrologEx.HttpServer`). `ssl` und `inets` starten erst beim ersten
HTTP-Aufruf, ohne HTTP kostet das nichts.

```prolog
:- use_module(library(http/http_server)).
:- use_module(library(lists)).

hallo(_Request, Response) :-
    http_body(Response, text("Hallo von PrologEx!\n")).
gruss(Name, _Request, Response) :-
    append("Servus, ", Name, T), http_body(Response, text(T)).
zaehler(_, Response, N0, N) :-          % Zustand über Anfragen hinweg
    N is N0 + 1, number_chars(N, Cs), http_body(Response, text(Cs)).

run :- http_listen(8765, [get(hallo, hallo), get(gruss/Name, gruss(Name)),
                          get(zaehler, zaehler)], [initial_state(0)]).
```

```prolog
?- use_module(library(http/http_open)), use_module(library(charsio)),
   http_open("http://localhost:8765/gruss/Stefan", S, [status_code(C)]),
   get_n_chars(S, _, Cs).
C = 200, Cs = "Servus, Stefan", S = '$stream'(5).
```

**`http_open/3`**: HTTP und HTTPS, die Methoden `get`, `head`, `post`,
`put`, `delete` und `patch`, die Optionen `method/1`, `data/1`,
`request_headers/1`, `headers/1`, `status_code/1` und `size/1`.
Weiterleitungen werden verfolgt (wie reqwest). HTTPS prüft Zertifikat und
Rechnernamen gegen die Zertifikate des Systems oder `SSL_CERT_FILE`;
`HTTPS_PROXY`, `HTTP_PROXY` und `NO_PROXY` gelten wie bei reqwest. Der
Stream liest den Rumpf als Text (UTF-8), ist er kein gültiges UTF-8, als
Bytes. Kommt keine Antwort, scheitert `http_open/3` (wie Scryer).

**`http_listen/2,3`**: Handler `Methode(Pfadmuster, Ziel)`, Zustand mit
`initial_state/1` (Handler mit einem oder zwei zusätzlichen Argumenten),
`content_length_limit/1` (sonst 413), `catch_errors/1`, TLS mit
`tls_key/1` und `tls_cert/1`; dazu `http_headers/2`,
`http_status_code/2`, `http_body/2` (`text`, `bytes`, `form`, `file`),
`http_redirect/2`, `http_query/3` und `http_basic_auth/4`. Der Server
spricht HTTP/1.0 und 1.1 mit Keep-Alive, Rümpfen mit `Content-Length`
oder in Stücken (`chunked`), `Expect: 100-continue` und `HEAD`. Jede
Verbindung ist ein eigener BEAM-Prozess: Ein langsamer Client hält die
anderen nicht auf. Die Handler laufen der Reihe nach, wie bei Scryer.
Beenden mit Ctrl-C.

Unterschiede zu Scryer (alle am Anfang der Dateien vermerkt):

  * `size(S)` gibt die Länge als Zahl und geht auch ohne `headers/1`.
    Bei Scryer lief `member/2` auf der noch ungebundenen Header-Liste.
  * `text(T)` eines Anfragerumpfs ist nach UTF-8 dekodiert; Scryer gibt
    die Bytes als Zeichen. `form(F)` geht auch mit
    `; charset=...` im Content-Type.
  * Eine Query ohne `=` (`?debug`) gibt `debug-""`; bei Scryer scheitert
    die ganze Anfrage.
  * Antworten mit Text, auch 404 und 500, gehen über einen Textstream.
    Scryer schreibt mit `format/3` in einen Binärstream, ISO verbietet
    das.
  * Fehlt bei `file(F)` die Datei, kommt der Fehler vor der Antwort (500
    wie jeder Fehler im Handler).
  * TLS-Schlüssel und -Zertifikat gehen als PEM-Text (wie Scryer) oder als
    Dateiname. OTPs TLS lehnt ein selbst signiertes Server-Zertifikat ab;
    zum Ausprobieren braucht es eine kleine eigene CA (siehe
    `test/http_test.exs`).
  * Ohne `library(clpz)` und `library(crypto)`, die es hier nicht gibt.

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
* `library(pairs)` (wie SWI): `pairs_keys_values/3`, `pairs_keys/2`,
  `pairs_values/2` (relational, in jede Richtung), `group_pairs_by_key/2`
  (benachbarte Paare mit `==`-gleichem Schlüssel), `map_list_to_pairs/3`
  (Prädikat im Modul des Aufrufers) und, aus SWI ergänzt,
  `transpose_pairs/2` (Paare getauscht, stabil nach dem neuen Schlüssel
  sortiert). `library(aggregate)` nutzt sie.
* `library(dcgs)` bietet `seq//1`, `seqq//1`, `...//0` und wie Scryer
  `phrase//2,3` (`phrase/4,5`: `phrase(G, A)` als Nichtterminal ist G mit
  dem zusätzlichen Argument A, etwa `phrase(seq, Xs)`). `phrase/2,3` und
  die DCG-Übersetzung bleiben die eingebauten. Dazu `call_dcg/3` wie SWI
  (hier dasselbe wie `phrase/3`, das `S0` und `S` auch nicht als Listen
  prüft).
* `library(dcg/pcre)`: reguläre Ausdrücke als Nichtterminale, `re//1,2,3`
  (siehe Reguläre Ausdrücke).
* `library(dcg/high_order)` wie SWI: `sequence//2,3,5`, `optional//2`,
  `foreach//2,3` – sie geben die Elemente nur weiter, Zeichen oder Codes
  ist ihnen gleich. Wie SWI liest `sequence//3` einen Trenner am Ende mit
  (`"1,2,"`) und erzeugt deshalb auch `"1,2,"`.
* `library(dcg/chars)`: die Nichtterminale von SWIs `library(dcg/basics)`
  (`blank//0`, `blanks//0`, `white//0`, `whites//0`, `blanks_to_nl//0`,
  `nonblank//1`, `nonblanks//1`, `digit//1`, `digits//1`, `integer//1`,
  `float//1`, `number//1`, `xdigit//1`, `xdigits//1`, `xinteger//1`,
  `string//1`, `string_without//2`, `remainder//1`, `eos//0`, `eol//0`,
  `alpha_to_lower//1`, `csym//1`, `csyms//1`, `prolog_symbol//1`,
  `atom//1`), aber auf **Zeichen** statt Codes – passend zu
  `double_quotes=chars`, `phrase_from_file/2` und `library(dcgs)`. Der
  eigene Name ist Absicht: SWI-Code, der Codes erwartet
  (`digits(Ds), {number_codes(N, Ds)}`), lädt nicht stillschweigend und
  scheitert dann, sondern muss angepasst werden. Was eine Zahl liefert
  (`integer//1`, `number//1`, `xdigit//1`, …), verhält sich wie bei SWI;
  `integer`, `float`, `number`, `xinteger`, `csym` und `atom` erzeugen
  auch. Die Zeichenklassen sind die von `code_type/2`.

  ```prolog
  ?- phrase(sequence(kv, (blanks, ",", blanks), L), "a=1 , b=-2").
  L = [a-1,b- -2].                 % kv(K-V) --> csym(K), "=", integer(V).
  ```
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
  * `sleep/1` (Sekunden), `sleep_ms/1` (Millisekunden), `max_sleep_time/1`.
    Geschlafen wird in ganzen Millisekunden, aufgerundet: `sleep_ms(X)`
    schläft `ceiling(X)` ms (`sleep_ms(0.0001)` so lange wie
    `sleep_ms(1)`), `sleep(S)` `ceiling(S * 1000)` ms. Floats gelten dabei
    als die Dezimalzahl, die sie zeigen: `sleep(1.1)` sind 1100 ms (binär
    ist 1.1 etwas größer).
  * Zeitgrenzen, Ausnahme `time_limit_exceeded` (wie SWI; Scryers
    `library(clpz)` fängt sie):
    * `call_with_timeout(G, S)`, `call_with_timeout(G, S, Optionen)`: G mit
      einer Frist von S Sekunden. `mode(cumulative)` (Vorgabe): S für alle
      Lösungen zusammen, die Zeit außerhalb von G (zwischen den Lösungen)
      zählt nicht; `mode(per_answer)`: je Lösung neu. `on_timeout(throw)`
      (Vorgabe), `on_timeout(fail)` oder `on_timeout(H)`: H statt G (im
      Modul des Aufrufers). Mehrfach angegeben gilt die letzte Option.
    * `call_with_time_limit(S, G)` wie SWI: `once(G)` mit Frist.
    * `set_timer(S)`: nach S Sekunden kommt `time_limit_exceeded` in die
      laufende Anfrage, einmal. Ein Timer je Anfrage (ein neuer ersetzt
      ihn), bis zum Ende der Anfrage oder `cancel_timer/0`; Backtracking
      nimmt ihn nicht zurück, die Zeit zwischen den Antworten zählt mit.
      Auch in `findall/3`, `\+` und Co. gesetzt gilt er für die ganze
      Anfrage.
    * G kann die Ausnahme nicht verschlucken: Fängt G sie selbst
      (catch-all), kommt sie beim nächsten Schritt wieder, bis ihr Rahmen
      sie fängt; eine Lösung nach Ablauf der Frist zählt nicht.
      Verschachtelt fängt die Grenze, die zuerst abläuft. `sleep/1` und
      `sleep_ms/1` schlafen höchstens bis zur nächsten Frist. Cleanups
      (`setup_call_cleanup/3`) laufen beim Abbruch und werden selbst nicht
      unterbrochen.
    * Mechanik: Die Maschine hat schon den Vergleich für
      `call_with_inference_limit/3` in jedem Schritt (ohne Grenze ein
      Vergleich mit `nil`). Eine Zeitgrenze trägt dort einen Prüfpunkt ein,
      alle 1000 Inferenzen ein Blick auf die Uhr. Ohne Zeitgrenze kostet
      das also nichts (gemessen: Unterschiede im Rauschen), mit einer rund
      100 ns je 1000 Inferenzen; die Frist hält auf wenige ms genau. Ein
      einzelnes lang laufendes eingebautes Prädikat (etwa `msort/2` auf
      einer Million Elementen) wird erst nach seiner Rückkehr unterbrochen.
  * `time/1`, das wie Scryer `% CPU time: 0.000s, 1 inference` je Lösung
    und beim Scheitern ausgibt. Gemessen wird direkt um das Ziel herum,
    also zählt nur das Ziel (`time(true)` meldet 1 Inferenz).

  Nach `use_module(library(time))` gilt dieses `time/1`, nach
  `use_module(library(swi))` das SWI-artige. `statistics/2` bleibt das eingebaute, eine Obermenge von
  Scryers vorläufigem.
* `library(arithmetic)` (BSD-Lizenz, wie Scryer): `expmod/4`, `lcm/3`,
  `lsb/2`, `msb/2`, `popcount/2` mit Scryers Fehlern; dazu für Brüche
  (neu geschrieben, über die eingebauten):
  - `number_to_rational(+Eps, +Real, -F)`: der einfachste Bruch (kleinster
    Nenner) mit `|F - Real| =< Eps`, exakt gerechnet und über Kettenbrüche
    (auch winzige Eps sind sofort fertig). Scryer sucht nur im
    Nachkommateil und trifft dessen Ränder nie: dort gibt `2.0000001` mit
    Eps `1.0e-6` 2 + 1/909091 statt 2 und eine negative Ganzzahl `-2.0`
    den Wert -3.
  - `number_to_rational(+Real, -F)`: Ganzzahlen unverändert, sonst Eps
    `1.0e-6` wie Scryer (`3.14159265` → `355r113`).
  - `rational_numerator_denominator(+R, -N, -D)`: wie `rational/3` (für
    eine Ganzzahl `D = 1`; Scryer scheitert dort).
* `library(stats)` (eigene): beschreibende Statistik über Zahlenlisten,
  Umfang wie SICStus' `library(statistics)` plus Quantile und
  Rangkorrelation wie Logtalk (der Name `statistics` ist durch
  `statistics/0,2` belegt).
  - Lage: `mean/2`, `weighted_mean/3`, `geometric_mean/2`,
    `harmonic_mean/2`, `trimmed_mean/3`, `median/2` (gerade Anzahl: Mittel
    der beiden mittleren; SICStus nimmt den kleineren), `modes/2`.
  - Quantile: `fractile/3` (nächster Rang, wie SICStus), `percentile/3`
    (0..100, linear interpoliert wie R/NumPy), `quartiles/4`,
    `interquartile_range/2`.
  - Streuung: `min/2`, `max/2`, `min_max/3`, `range/2`,
    `sample_variance/2` (n−1), `population_variance/2` (n),
    `weighted_variance/3`, `sample_standard_deviation/2`,
    `population_standard_deviation/2`, `standard_error/2`,
    `coefficient_of_variation/2`, `mean_deviation/2`,
    `median_deviation/2`.
  - Form: `central_moment/3`, `skewness/2`, `kurtosis/2` (Exzess).
  - Zusammenhang: `sample_covariance/3`, `population_covariance/3`,
    `correlation/3` (Pearson), `rank_correlation/3` (Spearman, gemittelte
    Ränge bei Gleichstand).
  - Sonst: `z_normalization/2`, `min_max_normalization/2`,
    `frequency_distribution/2`.

  Ohne Floats in der Liste rechnet alles exakt mit Brüchen
  (`mean([1,2,2], M)` gibt `5r3`, `sample_variance([2,4,4,4,5,5,7,9], V)`
  gibt `32r7`); Wurzeln, Logarithmen und was davon abhängt
  (Standardabweichung, Schiefe, Korrelation, geometrisches Mittel,
  z-Normierung) sind Floats. Mit Floats: Summen nach Neumaier, Varianz und
  Momente in zwei Durchgängen um das Mittel – numerisch stabil
  (`sample_variance([1.0e9, 1.0e9+1, 1.0e9+2])` gibt `1.0`). Undefiniertes
  (leere Liste, `sample_*` mit einem Wert, Varianz 0 bei Schiefe oder
  Korrelation) gibt `evaluation_error(undefined)`.
* `library(debug)` (BSD-Lizenz, unverändert): `* G` (Ziel
  wegverallgemeinern), `$ G` und `$- G` (Aufruf und Ausnahmen mit
  `portray_clause/1` zeigen).
* `library(freeze)` gibt wie in Scryer `freeze/2` weiter (eingebaut).
* `library(terms)`: wie in Scryer `numbervars/3`, dazu wie SWI
  - `term_hash(+T, -H)`: ist T ground, ein Hashwert in 0..2²⁷-1 (über
    Sitzungen und Rechner gleich, `:erlang.phash2/1` einer kanonischen
    Form); sonst bleibt H ungebunden. Gleiche Terme (`==`) geben denselben
    Wert, auch zyklische (dann aus den ersten 1000 Knoten der Abwicklung).
  - `term_hash(+T, +Tiefe, +Bereich, -H)`: nur bis Tiefe (1: Funktor bzw.
    atomarer Wert, 2: dazu die Argumente, ...), H in 0..Bereich-1.
  - `term_size(+T, -N)`: Zellen wie SWI – `f(A1, ..., An)` belegt 1 + n
    plus die Argumente (eine Listenzelle 3), Atome, kleine Zahlen und
    Variablen 0; was über dieselbe Variable geteilt ist, zählt einmal.
* `library(varnumbers)` (wie SICStus/SWI; `numbervars/3` selbst ist
  eingebaut): `numbervars/1`, `max_var_number(+T, +Start, -Max)`,
  `varnumbers/2,3` (Umkehrung von `numbervars/3`: jedes `'$VAR'(N)` mit
  ganzzahligem N ≥ Start wird einheitlich eine frische Variable, die
  Variablen von T bleiben) und `varnumbers_names(+T, -Copy, -Bindings)`
  (jedes `'$VAR'(X)`, auch mit Namen wie `'$VAR'('Foo')`; Bindings =
  `[X = V, ...]` nach X sortiert). Zyklische Terme:
  `domain_error(acyclic_term, _)`.
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
wird sicher, auch gegen absichtlich manipulierte Daten: `:safe` (keine
neuen Atome, keine Funktionsverweise), kein komprimiertes ETF (keine
Zip-Bombe), nur Prolog-Terme (Namen gültiges UTF-8, Stelligkeit höchstens
`max_arity`), und als ground markiert wird erst beim Aufbau – kaputte oder
fremde Daten geben `syntax_error(fast_term)`, eine andere Formatversion
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
    nicht. Nicht-ASCII gilt wie beim Lesen: ein Atom aus Buchstaben, das
    mit einem Kleinbuchstaben oder einem Buchstaben ohne Groß-/Kleinschreibung
    beginnt, bleibt ohne Hochkommas (`αβγ`, `äb`, `中文`, `x²`), ein
    Großbuchstabe am Anfang wäre eine Variable (`'Γβα'`, `'Äb'`) – wie SWI
    und Scryer; `write_canonical` schreibt ohne Operatoren (`+(1,2)`), auch Listen
    und `{}` funktional wie ISO 8.14.2.4 verlangt: `'.'(1,'.'(2,[]))`, `{}(a)`.
  * `'$VAR'(N)` erscheint als `A`, `B`, …, `Z`, `A1`, … (außer bei
    `write_canonical`).
  * Zeichenlisten bei `double_quotes=chars` wie Scryer als `"..."`
    (`number_chars(123, X)` → `X = "123"`).
  * Variablen schreiben `write/1`, `writeq/1`, `print/1`,
    `write_canonical/1` und `format` als `_` und Kennung (`_17`), wie SWI,
    Scryer und SICStus: Jede Variable hat eine VM-weit eindeutige Zahl
    (`PrologEx.Vars`), dieselbe Variable heißt also in jeder Ausgabe gleich
    und verschiedene heißen verschieden – auch über getrennte Aufrufe
    hinweg (`write(X), write(Y)` gibt `_17_18`, nie zweimal denselben
    Namen). Der Name aus dem Quelltext erscheint nie (`write_canonical(B+B)`
    gibt `+(_13,_13)`, nicht `+(_B,_B)`); `read/1` liefert Terme mit
    namenlosen Variablen (`T = foo(_A,_B,_A)`), die Namen gibt es über
    `variable_names/1`.
  * Nur die Antworten im Toplevel zeigen Namen: die der Anfrage (auch
    `_X`, die selbst nicht angezeigt werden), und frische Variablen heißen
    wie bei SICStus `_A`, `_B`, …, `_Z`, `_AA`, … – je Antwort neu, in
    Reihenfolge des Auftretens, auch in Restzielen; Namen aus der Anfrage
    werden nicht vergeben (`length(As, N)` → `As = [_A,_B], N = 2`).
    `listing/1` schreibt die Namen des Quelltexts, anonyme `_` wieder als
    `_`.
  * Antworten, `listing` und Fehlermeldungen schreiben Terme kompakt wie
    Scryer und `writeq` – ohne Leerzeichen nach Kommas (`f(a,b)`,
    `[1,2,3]`, `(x,y)`); nur die Bindungen einer Antwort trennt `, `
    (`X = f(a,b), Y = [1,2]`). Leerzeichen nach Kommas gibt es mit
    `write_term/2` und `spacing(next_argument)` (wie SWI: `f(a, b)`,
    `[1, 2]`).
  * `write_term/2`: `quoted/1`, `ignore_ops/1`, `numbervars/1`,
    `variable_names/1` (ISO), `max_depth/1`, `spacing/1`, `priority/1` (SWI).
    Mehrfach angegeben gilt die letzte Option (wie Scryer, ISO Cor.3).
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
`set_random(seed(N))`, aus Scryer `random_integer/3` (L =< X < U; X muss
ungebunden sein). Generator: Erlangs `exsss`, Zustand je Sitzung,
anfangs zufällig; `set_random(seed(N))` macht Läufe reproduzierbar.
`randseq(1000000, 1000000, L)` dauert etwa 1 s.

## Aggregieren: `library(aggregate)`

Zwischen SWI-Prolog und SICStus: die Prädikate beider Systeme,
`aggregate/3,4`, `aggregate_all/3,4` und `foreach/2`, mit den Templates,
die beide kennen.

```prolog
?- use_module(library(aggregate)).
?- aggregate_all(r(count, sum(A), max(A, N)), age(N, A), R).
R = r(5,42,max(11,ann)).
?- aggregate(sum(P), C^city(C, Land, P), S).    % je Land eine Lösung
Land = at, S = 2300 ;
Land = de, S = 5100.
```

  * Templates: `count`, `sum(E)`, `min(E)`, `max(E)`, `min(E, W)`,
    `max(E, W)` (Ergebnis `max(Wert, Zeuge)`), `bag(X)`, `set(X)` und
    zusammengesetzte Terme, deren Argumente selbst Templates sind
    (`r(count, min(X), max(X))`, auch geschachtelt).
  * `aggregate/3,4` gruppieren wie `bagof/3` bzw. `setof/3` nach den
    freien Variablen des Generators (`^` existenziell) und scheitern ohne
    Lösung. `aggregate_all/3,4` geben genau ein Ergebnis; ohne Lösung
    sind `count` und `sum` 0, `bag` und `set` `[]`, `min` und `max`
    scheitern (auch in einem zusammengesetzten Template).
  * Diskriminator: Lösungen, die in Diskriminator und Template gleich
    sind, zählen einmal (`aggregate(count, A, N^age(N, A), C)` zählt die
    verschiedenen Alter).
  * Arithmetik wie `is/2`: `sum` addiert, `min` und `max` vergleichen
    numerisch, ein Wert, der keine Zahl ergibt, wirft wie `is/2`. Beim
    Zeugen gewinnt bei Gleichstand der erste.
  * Fehler wie SWI, geprüft vor dem Generator: freies Template
    `instantiation_error`, unbekanntes `domain_error(aggregate_template,
    T)`, nicht aufrufbares `type_error(aggregate_template, T)`.
  * `foreach(Generator, Goal)`: die Konjunktion der Instanzen von Goal;
    anders als `forall/2` werden Variablen von Goal, die nicht im
    Generator vorkommen, geteilt und gebunden
    (`foreach(member(X, [1,2,3]), dif(Y, X)), Y = 4` gelingt).
  * `aggregate_all/3` faltet in der Maschine, ohne die Lösungen zu
    sammeln: Bei einer Million Lösungen ist `count` 1,9-mal so schnell wie
    `findall/3` mit `length/2`, `sum` und `max` rund 1,3–1,4-mal, und es
    bleibt kein Speicher liegen (statt rund 60 MB für die Liste).

## Geordnete Mengen: `library(ordsets)`

Mengen als geordnete Listen ohne Duplikate (Standardordnung der Terme),
die Vereinigung der Bibliotheken von SWI (= Scryer) und SICStus:

  * wie SWI und Scryer: `is_ordset/1`, `list_to_ord_set/2`,
    `ord_add_element/3`, `ord_del_element/3`, `ord_selectchk/3` (beide
    Richtungen), `ord_intersect/2,3`, `ord_intersection/2,3,4`,
    `ord_disjoint/2`, `ord_subtract/3`, `ord_union/2,3,4`,
    `ord_subset/2`, `ord_empty/1`, `ord_memberchk/2`, `ord_symdiff/3`,
    `ord_seteq/2`
  * dazu aus SICStus: `ord_member/2`, `ord_nonmember/2`,
    `ord_setproduct/3` (Paare `X-Y`), `ord_disjoint_union/3` (scheitert
    bei gemeinsamen Elementen), `ordset_order/3` (`<`, `=`, `>` für
    Teil-, gleiche und Obermenge, sonst scheitert es)

Die Prädikate sind in Elixir: Bei Mengen mit 10 000 Elementen dauern
Vereinigung, Schnitt und Differenz unter einer Millisekunde, SWIs Fassung
in Prolog braucht in unserer Maschine 40–50 ms. Anders als SWI und
SICStus, die bei einer Nicht-Liste still scheitern oder Teillisten
binden, prüfen sie ihre Mengen wie `sort/2`: Teilliste
`instantiation_error`, keine Liste `type_error(list, X)`. Nur der Typtest
`is_ordset/1` scheitert dann. Ob die Listen geordnet sind, prüft (wie
dort) niemand. `library(aggregate)` nutzt sie für `foreach/2`.

## Zuordnungen: `library(assoc)`

Schlüssel-Wert-Zuordnungen als AVL-Bäume in der Darstellung von SWI und
Scryer (`t` leer, sonst `t(K, V, Balance, L, R)` mit Balance `<`, `-`,
`>`); Schlüssel nach der Standardordnung (`==`, nicht Unifikation). Die
API ist die Vereinigung von SWI und SICStus:

  * `empty_assoc/1`, `get_assoc/3`, `get_assoc/5` (Wert ersetzen),
    `put_assoc/4`, `del_assoc/4`, `del_min_assoc/4`, `del_max_assoc/4`,
    `min_assoc/3`, `max_assoc/3`, `gen_assoc/3` (Schlüssel ground:
    nachschlagen, sonst aufsteigend aufzählen), `list_to_assoc/2`,
    `ord_list_to_assoc/2`, `assoc_to_list/2`, `assoc_to_keys/2`,
    `assoc_to_values/2`, `is_assoc/1`, `map_assoc/2,3`
  * dazu aus SICStus: `get_next_assoc/4`, `get_prev_assoc/4` (nächster
    größerer bzw. kleinerer Schlüssel; K muss nicht vorkommen),
    `portray_assoc/1` (`<a-1,b-2>`)

SICStus nimmt unbalancierte Bäume (`t(K,V,L,R)`), die bei aufsteigend
eingefügten Schlüsseln zur Liste entarten; wir nehmen AVL wie SWI und
Scryer, damit jede Operation logarithmisch bleibt. Die Bäume sind Term für
Term dieselben wie bei SWI: Einfügen, Löschen und Rotationen folgen
dessen Algorithmus, und ein Test vergleicht zufällige Folgen von
Operationen mit SWIs Prolog-Fassung (`test/fixtures/assoc_swi.pl`).
In Elixir, mit einem schnellen Pfad für die selbst gebauten Knoten
(direkt erkannt, ohne Umweg über die Bindungen) und für Ganzzahl- und
Atomschlüssel (direkt verglichen). Etwa 4–5-mal langsamer als Erlangs
`gb_trees`: ein Knoten `t/5` ist eine Struktur mit Argumentliste, also
gut dreimal so groß wie ein Tupel.
Fehler wie SWI: freier Baum `instantiation_error`, kein Baum
`type_error(assoc, X)`, doppelte Schlüssel bei `list_to_assoc/2`
`domain_error(unique_key_pairs, L)`, ungeordnete bei
`ord_list_to_assoc/2` `domain_error(key_ordered_pairs, L)`, ein Element
ohne `-` `type_error(pair, X)`. `is_assoc/1` prüft den ganzen Baum
(Ordnung, Balance, ground Schlüssel) und scheitert sonst.

Die Operationen sind in Elixir; gegenüber SWIs Fassung in Prolog in
unserer Maschine: 20 000 `put_assoc/4` (aufsteigend) 420 statt 2 123 ms,
20 000 `get_assoc/3` 575 statt 2 613 ms, `list_to_assoc/2` mit 20 000
Paaren 45 statt 168 ms, `assoc_to_list/2` 357 statt 474 ms.

## Graphen: `library(ugraphs)`, `library(wgraphs)`

Gerichtete Graphen als Listen von Paaren `Knoten-Nachbarn`, Knoten und
Nachbarn nach der Standardordnung, jeder Nachbar selbst ein Knoten (wie
SWI, Scryer und SICStus); Knoten sind beliebige Terme, gleich heißt `==`.
Ein ungerichteter Graph hat zu jeder Kante die Gegenkante.

`library(ugraphs)` (ungewichtet) ist die Vereinigung von SWI/Scryer und
SICStus:

  * beide: `vertices_edges_to_ugraph/3`, `vertices/2`, `edges/2`,
    `add_vertices/3`, `del_vertices/3`, `add_edges/3`, `del_edges/3`,
    `transpose_ugraph/2`, `neighbors/3`, `neighbours/3`, `complement/2`,
    `compose/3`, `transitive_closure/2`, `top_sort/2`, `reachable/3`
  * SWI und Scryer: `top_sort/3` (Differenzliste), `ugraph_union/3`,
    `connect_ugraph/3`
  * SICStus: `symmetric_closure/2`, `transitive_reduction/2`,
    `max_path/5`, `min_path/5`, `min_paths/3`, `path/3` (nichtdeterministisch),
    `reduce/2` (starke Zusammenhangskomponenten), `random_ugraph/3`,
    `min_tree/3` (Prim), `max_cliques/2` (Bron–Kerbosch)

`library(wgraphs)` (gewichtet) wie SICStus: Nachbarn sind Paare
`Nachbar-Gewicht`, eine Kante ist `U-(V-W)`. `wgraph_to_ugraph/2`,
`ugraph_to_wgraph/2,3`, `vertices_edges_to_wgraph/3`, `vertices/2`,
`edges/2`, `add_vertices/3`, `del_vertices/3`, `add_edges/3`,
`del_edges/3`, `transpose_wgraph/2`, `neighbors/3`, `neighbours/3`,
`transitive_closure/2` (kürzeste Wege), `symmetric_closure/2`,
`top_sort/2`, `max_path/5`, `min_path/5` und `min_paths/3` (Dijkstra),
`path/3`, `reduce/2`, `reachable/3`, `random_wgraph/4`, `min_tree/3`
(Kruskal). Doppelte Kanten behalten das kleinste Gewicht. Viele Namen
gibt es in beiden Bibliotheken; wer beide braucht, importiert eine davon
mit leerer Liste und ruft sie mit `wgraphs:` auf.

Die Ergebnisse sind dieselben wie bei den Vorbildern: Ein Test vergleicht
zufällige Graphen mit SWIs Prolog-Fassung (`test/fixtures/ugraphs_swi.pl`),
die SICStus-Prädikate wurden ebenso mit SICStus' Algorithmen verglichen
(bei gleich langen Pfaden und gleichen Gewichten gewinnt derselbe), und
ein Test prüft Pfade, Abschlüsse, Komponenten, Cliquen und Spannbäume
gegen Aufzählen. Wo SWI und SICStus sich widersprechen, erreicht beim
transitiven Abschluss ein Knoten auf einem Zyklus sich selbst (SWI;
SICStus lässt diese Schlingen weg). Bewusst anders in Randfällen:
`path/3` nimmt auch über eine Schlinge keinen Knoten zweimal,
`min_tree/3` eines einzelnen Knotens ist `[V-[]]` (SICStus: `[]`),
gewichtet behalten `min_paths/3` den Startknoten und `max_path/5` eine
Kante mit Gewicht 0, und `del_vertices/3` entfernt alle genannten Knoten
(SWI behält einen, wenn davor ein fehlender genannt ist). Fehler: ein
Graph, eine Knoten- oder Kantenliste als Teilliste `instantiation_error`,
keine Liste `type_error(list, X)`, ein Element ohne `-`
`type_error(pair, X)`, ein Gewicht keine Zahl `type_error(number, W)`;
`random_ugraph/3` verlangt wie SICStus einen Float in [0.0, 1.0].

Die Prädikate sind in Elixir (Knoten intern über Sortierschlüssel, die
die BEAM ohne Rückruf vergleicht). Gegenüber SWIs Fassung in Prolog in
unserer Maschine: `top_sort/2` mit 1 000 Knoten 1 statt 4 524 ms,
`reachable/3` mit 2 000 Knoten 5 statt 4 800 ms, `transitive_closure/2`
mit 200 Knoten 19 statt 384 ms, `transpose_ugraph/2` mit 2 000 Knoten 7
statt 69 ms.

## Prioritätswarteschlangen: `library(heaps)`

Min-Heaps aus Paaren `Schlüssel-Wert`, Schlüssel nach der
Standardordnung; die Vereinigung von SWI und SICStus:

  * beide: `empty_heap/1`, `add_to_heap/4`, `get_from_heap/4`,
    `delete_from_heap/4`, `heap_size/2`, `heap_to_list/2`,
    `list_to_heap/2`, `min_of_heap/3`, `min_of_heap/5`, `is_heap/1`
  * SWI: `merge_heaps/3`, `singleton_heap/3`
  * SICStus: `portray_heap/1` (`heap{a->1, b->2}`)

Anders als dort ist der Heap stabil: Paare mit gleichem Schlüssel kommen
in der Reihenfolge heraus, in der sie hineinkamen (`list_to_heap/2`: die
der Liste; nach `merge_heaps/3` je Ausgangsheap, neue danach). SWI und
SICStus lassen das offen. `delete_from_heap(+Heap0, ?Key, ?Value, -Heap)`
entfernt das erste Paar nach Priorität, das mit `Key-Value` unifiziert;
so geht es in SICStus' Richtung (Schlüssel gegeben) wie in SWIs (Wert
gegeben). Fehler: Heap als Variable `instantiation_error`, kein Heap
`type_error(heap, X)`, ein Listenelement ohne `-` `type_error(pair, X)`;
`is_heap/1` prüft den ganzen Baum und scheitert sonst.

Darstellung: `heap(Größe, Zähler, Baum)` mit einem Leftist-Heap. SWI
nimmt einen Pairing-Heap, SICStus einen Binärbaum mit Freiliste. Der
Leftist-Heap braucht für Einfügen, Entnehmen und Verschmelzen auch im
schlechtesten Fall nur O(log n); beim Pairing-Heap gilt das nur
amortisiert, und das trägt nicht, wenn derselbe Heap (etwa beim
Backtracking einer Suche) mehrmals benutzt wird. In Elixir; in unserer
Maschine gegenüber SWIs Fassung (Pairing-Heap in Prolog) und SICStus'
(Binärbaum in Prolog): 20 000 Paare einfügen und alle entnehmen 0,8 statt
3,7 bzw. 4,1 s, `list_to_heap/2` und `heap_to_list/2` mit 20 000 Paaren
0,1 statt 3,7 bzw. 3,4 s, 200 Mal `get_from_heap/4` auf denselben Heap mit
20 000 Paaren kaum messbar statt 27 s (SWI) bzw. 2 s (SICStus).

Andere Systeme: YAP und ECLiPSe haben O'Keefes ursprüngliche Bibliothek
von 1983 (die Grundlage der SICStus-Fassung, ohne `delete_from_heap/4`,
`is_heap/1` und `portray_heap/1`); Logtalk hat eigene Heap-Objekte
(Binär- und Pairing-Heaps, Min und Max) mit anderer API; Scryer hat
keine (nur `library(queues)` für FIFO-Warteschlangen).

## Warteschlangen: `library(queues)`

FIFO-Warteschlangen als Differenzlisten mit Zähler (`q(N, Vorne,
Hinten)`, N als `0`, `s(0)`, …, wie Scryer): Anhängen und Abnehmen an
beiden Enden kosten O(1) und gehen in beide Richtungen. Die API ist die
Vereinigung von Scryer und SICStus 4:

  * Scryer: `queue/1`, `queue/2`, `queue_head/3`, `queue_head_list/3`,
    `queue_last/3`, `queue_last_list/3`, `list_queue/2`, `queue_length/2`
    (hier auch zum Erzeugen, wie SICStus)
  * SICStus 4: `empty_queue/1`, `singleton_queue/2`, `is_queue/1`,
    `queue_head/2`, `queue_tail/2`, `queue_cons/3`, `queue_last/2`,
    `append_queue/3`, `queue_append/3`, `queue_list/2`, `queue_member/2`,
    `queue_memberchk/2`, `map_queue/2,3`, `map_queue_list/3`,
    `map_list_queue/3`, `some_queue/2,3`, `somechk_queue/2,3`,
    `portray_queue/1` (`Queue[a,b,c]`)

`queue_last/3` hat Scryers Reihenfolge, `queue_last(X, Q0, Q)` (SICStus:
`queue_last(Q0, X, Q)`). Wie dort binden `queue_last/3`,
`queue_last_list/3` und `queue_append/3` das Hinten der alten
Warteschlange; an eine Warteschlange hängt man also nur einmal hinten
an. In Prolog (`priv/library/queues.pl`, Scryers Teil unter deren
Lizenz): die logischen Variablen sind hier die Darstellung, Elixir
brächte nichts. Die alte O'Keefe-API von YAP und ECLiPSe (`make_queue/1`,
`join_queue/3`, `serve_queue/3`, …) gibt es nicht; SWI hat keine
`library(queues)`.

## Rot-Schwarz-Bäume: `library(rbtrees)`

Wie SWI-Prolog (und YAP, beide von Vitor Santos Costa): `rb_new/1`,
`rb_empty/1`, `rb_lookup/3`, `rb_update/4,5`, `rb_apply/4`,
`rb_insert/4`, `rb_insert_new/4`, `rb_delete/3,4`, `rb_visit/2`,
`rb_visit_range/4`, `rb_keys/2`, `rb_map/2,3`, `rb_partial_map/4`,
`rb_fold/4`, `rb_clone/3`, `rb_min/3`, `rb_max/3`, `rb_del_min/4`,
`rb_del_max/4`, `rb_next/4`, `rb_previous/4`, `list_to_rbtree/2`,
`ord_list_to_rbtree/2`, `is_rbtree/1`, `rb_size/2`, `rb_in/3`. Scryer
und SICStus haben keine.

Darstellung wie SWI (`t(Nil, Wurzel)`, `Nil = black('', _, _, '')`,
Knoten `red/4` und `black/4`); Einfügen, Löschen, Aufbau und alle Umbauten
folgen SWIs Code Klausel für Klausel, die Bäume sind Term für Term
dieselben: Ein Test vergleicht zufällige Folgen von Operationen mit
SWIs Fassung (`test/fixtures/rbtrees_swi.pl`, die SSU-Regeln mechanisch
in Klauseln mit Cut umgeschrieben). Die Operationen sind in Elixir
(`'$rb_...'`), nur die Prädikate mit Zielaufruf (`rb_map`, `rb_apply`,
`rb_fold`, `rb_partial_map`) in Prolog – mit SWIs Reihenfolge der
Aufrufe. Anders als SWI prüfen `list_to_rbtree/2` und
`ord_list_to_rbtree/2` ihre Liste wie `library(assoc)`: doppelte
Schlüssel `domain_error(unique_key_pairs, L)` bzw.
`domain_error(key_ordered_pairs, L)`, ungeordnete
`domain_error(key_ordered_pairs, L)`; ein Baum als Variable
`instantiation_error`, kein Baum `type_error(rbtree, X)`. In unserer
Maschine gegenüber SWIs Fassung in Prolog: 20 000 `rb_insert/4` 0,4 statt
3,0 s, 20 000 `rb_lookup/3` 0,3 statt 1,5 s, 20 000 `rb_delete/3` 0,6
statt 3,9 s, `list_to_rbtree/2` und `rb_visit/2` mit 20 000 Paaren 0,06
statt 1,3 s.

## Konjunktionen als Listen: `library(commalist)`

Schnittstelle nach XSB Prolog: `commalist_to_list/2`,
`nonemptylist_to_commalist/2`, `commalist_append/3`, `commalist_length/2`,
`commalist_member/2`, `commalist_memberchk/2`. Die Elemente einer
Commaliste sind die Blätter ihres `,`-Baums von links nach rechts, gleich
wie er geschachtelt ist:

```
?- commalist_to_list((A,(B,C),D), L).      % L = [A,B,C,D]
?- commalist_to_list(((A,B),C), L).        % L = [A,B,C]
?- nonemptylist_to_commalist([a,b,c], C).  % C = (a,b,c)
```

  * Jeder andere Term ist ein Element (`a` ist die Commaliste `[a]`), auch
    eine Variable als Blatt – das ist nicht monoton:
    `commalist_to_list((A,b), L)` gibt `[A,b]`, nach `A = (x,y)` aber
    `[x,y,b]`.
  * Ist die Commaliste selbst eine Variable, gibt es `instantiation_error`;
    Bäume werden nicht aufgezählt. Zum Aufzählen:
    `length(Ls, N), Ls = [_|_], nonemptylist_to_commalist(Ls, C)`.
  * Erzeugte Commalisten (`nonemptylist_to_commalist/2`,
    `commalist_append/3`) sind rechts geschachtelt wie ein gelesenes
    `(a,b,c)`. Eine leere gibt es nicht: `nonemptylist_to_commalist([], C)`
    ist `domain_error(non_empty_list, [])`, eine Teilliste
    `instantiation_error`, eine Nicht-Liste `type_error(list, L)`.
  * `commalist_append/3` braucht beide Eingaben, `commalist_length/2` die
    Commaliste (Länge wie bei `length/2` geprüft).

In Prolog (`priv/library/commalist.pl`), ohne Rekursionstiefe: auch
Bäume mit 100 000 Elementen, links oder rechts geschachtelt.

## Reguläre Ausdrücke: `library(pcre)`

Schnittstelle wie SWI-Prologs `library(pcre)`, gerechnet von Erlangs
`:re` – seit OTP 28 PCRE2 (`re_config(version(V))`): `re_match/2,3`,
`re_matchsub/3,4`, `re_foldl/6`, `re_split/3,4`, `re_replace/4,5`,
`re_compile/3`, `re_flush/0`, `re_config/1`.

```
?- re_matchsub("(?<y_I>\\d+)-(?<m_I>\\d+)-(?<d_I>\\d+)", "am 2026-11-01", S).
S = [0-"2026-11-01",d-1,m-11,y-2026].
?- re_replace("(?<y>\\d+)-(?<m>\\d+)-(?<d>\\d+)"/g, "$d.$m.$y", "2026-11-01", R).
R = "01.11.2026".
?- re_split(":\\s*"/n, "Age: 33", L).
L = ['Age',': ',33].
```

  * Muster als Text oder `Text/Flags` mit den Buchstaben wie bei SWI
    (`i m s x` und `a r t` für den Ergebnistyp; `re_split`: `a s n`;
    `re_replace`: `g a s`), Optionen wie bei SWI (`caseless/1`,
    `multiline/1`, `dotall/1`, `extended/1`, `greedy/1`, `ucp/1`,
    `newline/1`, `bsr/1`, `anchored/1`, `bol/1`, `eol/1`, `empty/1`,
    `start/1`, `capture_type/1`, …); Flags gehen vor, von mehrfach
    angegebenen Optionen gilt die erste (wie SWI). Optionen nur für
    Geschwindigkeit (`optimise/1`, `jit/1`, …) werden angenommen und
    übergangen, unbekannte sind `domain_error(re_option, O)`.
  * Benannte Gruppen mit Typ-Endung wie SWI (`_S _A _I _F _N _T _R`).
  * Statt eines Dicts eine Paarliste: `0`, dann die nicht benannten Gruppen
    nach Nummer, dann die benannten nach Name; nicht gesetzte fehlen. Die
    Nummern der benannten Gruppen liest die Bibliothek aus dem Muster; wo
    das nicht sicher geht (`(?|…)`, Optionen im Muster wie `(?x)`),
    erscheinen benannte Gruppen zusätzlich mit ihrer Nummer.
  * Texte sind Atome, Zeichen- oder Codelisten. Der Ergebnistyp `string`
    (Vorgabe) ist die Textart des Subjekts (bei `[]` die von
    `double_quotes`); dazu `atom`, `chars`, `codes`, `range` (Start-Länge),
    `term`. Positionen zählen in Zeichen, nicht in Bytes.
  * Ersetzungstext: `\N`, `\{N}`, `$Name`, `${Name}`, `$$` und `\\`; eine
    benannte Gruppe nur über ihren Namen, ein unbekannter Name ist
    `existence_error(re_group, Name)`.
  * Fehler: ungültiges Muster `syntax_error(Meldung)` (von PCRE),
    katastrophales Backtracking `resource_error(match_limit)`.

Eine kompilierte Regex ist der lesbare Term `'$regex'(Muster, Optionen)`
(statt SWIs Blob), etwa `'$regex'('a+b',[caseless(true),greedy(false)])`:
das Muster als Atom, die Optionen, die das Kompilat bestimmen, ohne
Vorgabewerte nach Namen sortiert. Das Kompilat steht nie im Term, sondern
in einem Cache je Prozess (höchstens 256 Einträge, `re_flush/0` leert
ihn) mit Muster und Optionen als Schlüssel. Ein selbst gebauter Term ist
darum nie gefährlicher als eine Regex: Er wird geprüft (nicht kanonisch:
`domain_error(regex, T)`) und wie jede andere kompiliert. Die Terme
überstehen `copy_term/2`, `findall/3`, `assert` und `fast_write`.

Für Programme ohne `library(pcre)` ändert sich nichts: keine neue Termart,
nichts in der Maschine; die Prädikate kommen erst mit `use_module`.
`re:run` läuft wie ein langes eingebautes Ziel – Zeitgrenzen
(`call_with_timeout`) greifen erst danach, `resource_error(match_limit)`
schützt vor exponentiellem Backtracking.

### In Grammatiken: `library(dcg/pcre)`

`re(Regex)//`, `re(Regex, Sub)//` und `re(Regex, Sub, Optionen)//` suchen
das Muster **verankert an der aktuellen Stelle** einer Zeichen- oder
Codeliste und verbrauchen den Treffer. `Sub` und die Optionen sind die von
`re_matchsub/4`; die Texte haben die Art der Liste.

```
:- use_module(library(dcg/pcre)).
toks([T|Ts]) --> ws, tok(T), !, toks(Ts).
toks([]) --> ws.
ws --> re("\\s*").
tok(num(N)) --> re("[0-9]+(\\.[0-9]+)?", [0-Cs|_]), { number_chars(N, Cs) }.
tok(id(A))  --> re("[a-z_]\\w*", [0-A], [capture_type(atom)]).
tok(op(A))  --> re("[-+*/=()]", [0-A], [capture_type(atom)]).

?- phrase(toks(Ts), "x1 = 3.14 * (foo + 42)").
Ts = [id(x1),op(=),num(3.14),op(*),op('('),id(foo),op(+),num(42),op(')')].
```

  * Deterministisch wie PCRE: genau der eine Treffer, den PCRE hier findet
    (gierig, erste passende Alternative), kein Zurücksetzen auf kürzere.
    Ein leerer Treffer verbraucht nichts.
  * Subjekt ist der ganze Rest der Liste: `^` und `\A` passen an der
    aktuellen Stelle, `$` und `\z` am Ende der Eingabe, ein Lookbehind
    sieht nichts davor, `capture_type(range)` zählt ab hier.
  * Der Rest muss deshalb bekannt sein. Eine faule Liste
    (`phrase_from_file/2`, allgemein ein Ende, das mit `freeze/2` wartet)
    liest der erste Aufruf zu Ende; ein offenes Ende ohne `freeze` ist
    `instantiation_error`, ein anderes Ende oder eine zyklische Liste
    `type_error(list, …)`.
  * Kosten: Der Rest wird einmal in Text umgewandelt und mit seiner Liste
    gemerkt; ein späterer Aufruf findet seine Stelle über die physische
    Identität der Listenzelle, von der letzten Stelle aus vorwärts. Ein
    Tokenizer über einer Liste aus `atom_chars/2`, einem String oder
    `phrase_from_file/2` bleibt so linear (20 000 Treffer über 200 000
    Zeichen: etwa 0,4 s). Weil gebundene Variablen der Liste nach dem
    Zurücksetzen anders gebunden sein können, prüft jeder Aufruf die
    Variablen im Rest – bei einer Liste, die Zelle für Zelle mit
    Variablen entstand (etwa in einer `get_char/2`-Schleife), kostet ein
    Aufruf deshalb O(Rest); `atom_chars/2` einmal darauf macht sie nativ.
    PCRE prüft im Unicode-Modus bei jedem Lauf den ganzen Rest auf
    gültiges UTF-8 (Erlangs `:re` kann das nicht abschalten); ist der Rest
    ab der Stelle reines ASCII und das Muster auch, läuft die Regex ohne
    Unicode-Modus – gleiches Ergebnis, ohne diese Prüfung. Steht weiter
    hinten noch Nicht-ASCII, bleibt es bei etwa 0,4 ms je MB Rest.

## Boolesche Bedingungen: `library(clpb)`

CLP(B) von Markus Triska (MIT-Lizenz), aus Scryer Prolog (b7066b4):
`sat/1`, `taut/2`, `labeling/1`, `sat_count/2`, `weighted_maximum/3`,
`random_labeling/2`; Formeln mit `~ * + # =:= =\= =< >= < > ^` (Quantor),
`card(Is, Fs)`, `+(Ls)`, `*(Ls)`. Atome stehen für allquantifizierte
Variablen. Die Restziele zeigt der Toplevel wie Scryer:

```prolog
?- sat(X+Y).
sat(X=\=X*Y#Y).
?- sat(X =< Y), sat(Y =< Z), taut(X =< Z, T).
T = 1, sat(X=:=X*Y), sat(Y=:=Y*Z).
?- sat(1#X#a#b).
sat(X=:=a#b).
```

Dafür kamen allgemeine Bausteine dazu, die auch andere Bibliotheken aus
Scryer brauchen: `bb_b_put/2` (backtrackbare globale Werte), `foldl/4..6`
auch in `library(lists)`, `random_integer/3`, die Hooks
`attribute_goals//1` und `project_attributes/2`. Getestet mit den
Beispielen der Dokumentation (Tauben, XOR aus NAND-Gattern, Damen) und
Triskas eigenen Prüfprogrammen aus github.com/triska/clpb
(`test/fixtures/clpb/`, mit eingeschalteten internen Konsistenzprüfungen
`clpb:validation`); `testing.pl` mit Größe 1 läuft als langsamer Test
(gut eine Minute), `test_bdd_merging.pl` (65 536 Kombinationen) einmal von
Hand, bestanden.

Ziel ist, clpb nach und nach ganz in Elixir zu rechnen
(`PrologEx.Builtins.ClpbPrims`); `clpb.pl` geht dafür bewusst vom
Snapshot weg (upstream ändert sich die Datei selten: seit 2020 ein paar
echte Korrekturen, sonst Doku und Anpassungen; Herkunft und Abweichungen
stehen in ihrem Kopf). Referenz für jeden Schritt:

  * `test/clpb_golden_test.exs`: 400 zufällige Anfragen (mehrere `sat/1`
    über Variablen und Atome, Bindungen, `taut/2`, `labeling/1`,
    `sat_count/2`) mit den Antworten der ursprünglichen Fassung, samt
    Restzielen und Fehlern (erzeugt von `test/fixtures/clpb/gen_golden.exs`);
  * Vergleiche einzelner Teile mit Triskas Prolog-Code auf Zufallsformeln.

Bisher in Elixir:

  * die Prüfung nach jedem `sat/1` (`satisfiable_bdd/1`: welche
    Variablen nur noch einen Wert zulassen, welche gleich sein müssen),
    auch mit Atomen (allquantifizierten Variablen);
  * der BDD-Kern: `apply/4` (Verknüpfung zweier BDDs), `make_node/4`
    (eindeutige Knoten über die Tabelle an jeder Variablen),
    `bdd_restriction/4` und `existential/3` (Quantoren).
  * das Übersetzen der Formeln (`parse_sat/2`): Typprüfung mit denselben
    Fehlern, Umschreiben der Synonyme, Atome durch ihre Variablen;
  * der Aufbau des BDDs aus der Formel (`sat_bdd/2`), auch `card/2` (über
    dasselbe Zählnetz wie das Original) und `^`;
  * `sat/1` selbst: Zerlegen in Konjunktionsglieder (samt der Eigenheit
    des Originals bei offenen Listen wie `sat(*(L))`), Verknüpfen mit den
    BDDs der beteiligten Wurzeln, Neuaufbau der Knotentabellen. In
    Prolog bleiben nur die Unifikationen der Propagation, weil jede die
    Hooks der gebundenen Variablen wecken muss, bevor die nächste kommt;
  * `taut/2` (die Prüfung auf Tautologie, ohne bleibende Änderungen) und
    der Hook beim Binden (`verify_attributes/3`, samt Neuaufbau des BDDs
    einer Wurzel);
  * `sat_count/2`: Verknüpfen mit den bisherigen Bedingungen, Herausrechnen
    der übrigen Variablen (Atome mit ∀, sonst ∃), Zählen über die Knoten
    mit Merktabelle. Bei `length(Vs, 30), sat(card([10-15], Vs))` zählt
    es in rund 20–30 ms (Scryer 24–93 ms); die Prolog-Fassung kam hier
    in 300 s nicht zum Ende;
  * die Restziele (`attribute_goals//1`, `project_attributes/2`): ANF der
    Formeln (mit Merktabelle je Knoten), Zusammenfassen und Trennen der
    Variablen, `clpb_residuals(bdd)`. Die Ausgabe ist um ein Vielfaches
    schneller (`card([2], Vs)` über 12 Variablen: 0,8 statt 21 s, Scryer
    9 s), bleibt aber exponentiell, weil die ANF selbst exponentiell
    groß werden kann;
  * der Neuaufbau der Knotentabellen nach jedem `sat/1` baut je Variable
    den AVL-Baum in O(n) aus den sortierten Schlüsseln (statt jeden
    Knoten einzeln einzufügen); die Propagation rechnet auf dem BDD als
    dichte Arrays (Knoten 0…n-1, Besucht-Marken in `:atomics`), und ohne
    `clpb:validation` liest `sat/1` den BDD für Neuaufbau und
    Propagation nur einmal; die Schlüssel der Knotentabellen sind Zahlen
    (Cantor-Paarung der Kinder-Codes) statt Terme `node(LID, HID)`.
    7 Damen aufstellen: 5,6 → 1,6 s; 8 Damen aufstellen 31 → 9,6 s, dazu
    `labeling/1` (früher Speicherüberlauf) 2,3 s. Scryer braucht schon
    für das Aufstellen von 6 Damen 20 s;
  * von `labeling/1` das Prüfen und Sortieren, von `random_labeling/2` die
    zufälligen Bindungen (mit denselben Zufallszahlen), von
    `weighted_maximum/3` der BDD-Teil (`weighted_maximum/3`: 51 → 3 ms
    bei 6 Damen). In Prolog bleibt nur das Binden mit Backtracking
    (`indomains/1`, `max_labeling/2`): Jede Bindung muss die Hooks aller
    Module wecken, bevor die nächste kommt.

Triskas Fassungen dieser Prädikate bleiben als `…_ref` in `clpb.pl` und
dienen den Vergleichstests (je 1500–3000 Zufallsformeln, -terme bzw.
Folgen von Bedingungen, für `parse_sat/2` auch fehlerhafte). Die kleinen Formeln aus
`bench/compare.pl` brauchen damit rund 80 statt 1640 ms – gut dreimal
schneller als Scryer (265 ms). Mit `clpb:ref_mode` (dynamisch, für die
Tests) rechnen `sat/1`, `taut/2`, `sat_count/2` und der Hook wieder mit
Triskas Code, ebenso die Restziele und die drei Prädikate zum Belegen.

Eine Eigenheit des Originals bleibt erhalten (Scryer verhält sich
genauso): Bindet eine einzige Unifikation mehrere Variablen aus
verschiedenen Bedingungen, scheitert sie, etwa
`sat(X =\= Y), sat(A =\= B), f(X, Y) = f(A, B)` – der Hook der zweiten
Variablen findet die Formel ihrer Wurzel nicht mehr, weil der erste sie
zum Neuaufbau schon abgeräumt hat.

## Bedingungen über ganzen Zahlen: `library(clpz)`

CLP(ℤ) von Markus Triska (BSD-Lizenz), aus Scryer Prolog (b7066b4),
unverändert: arithmetische Bedingungen (`#=`, `#\=`, `#<`, ... über `+ - *
^ // div mod rem abs min max` und Bitoperationen), Domänen (`in/2`,
`ins/2`, `fd_dom/2`, `fd_inf/2`, ...), Reifikation (`#<==>`, `#==>`,
`#\/`, `#\`, `zcompare/3`), globale Bedingungen (`all_different/1`,
`all_distinct/1`, `sum/3`, `element/3`, `tuples_in/2`,
`global_cardinality/2,3`, `lex_chain/1`, `circuit/1`, `cumulative/1,2`,
...) und `label/1`, `labeling/2`. Die Restziele zeigt der Toplevel wie
Scryer:

```prolog
?- X #= Y*Y, Y in -2..2.
X in 0..4, Y^2#=X, Y in -2..2.
?- X in 0..5, X #\= 3, fd_dom(X, D).
D = 0..2\/4..5, X in 0..2\/4..5.
```

Drei Formen schreibt PrologEx lesbarer (Flag `clpz_residuals`,
Voreinstellung `compact`): eine halboffene Domäne als Vergleich mit einer
Zahl, `X #=< Y + C` und lineare Summen (`L #=< R`) als `#<` oder `#=<` –
jeweils mit der betragsmäßig kleineren Konstante (`X #> 1` statt
`X #>= 2`, aber `X #=< 2` statt `X #< 3`); steht in einer Summe eine Zahl
allein, kommt sie nach rechts:

```prolog
?- A #> 1, A #< B, C #< 3.
A#>1, A#<B, B#>2, C#=<2.          % Scryer: A in 2..sup, A#=<B+ -1, B in 3..sup, C in inf..2
?- X #=< Y - 3.
X#<Y-2.                          % Scryer: X#=<Y+ -3
?- 2*X+3*Y #> 5, X+Y #< Z.
X+Y#<Z, 2*X+3*Y#>5.              % Scryer: X+Y+1#=<Z, 6#=<2*X+3*Y
```

`#=` und `#\=` über Summen bleiben wie bei Scryer.

Dazu rechnet PrologEx Hilfsvariablen heraus, die clpz für Teilausdrücke
und verschachtelte Reifikation anlegt, und schreibt Vergleiche in
Reifikationen ebenso lesbar:

```prolog
?- X #= Y*Z - 1.
X#=Y*Z-1.                        % Scryer: X+1#=_A, Y*Z#=_A
?- X #< Y #<==> B.
B in 0..1, X#<Y#<==>B.           % Scryer: B in 0..1, Y#>=_A#<==>B, X+1#=_A
?- X #\= 3 #==> X #> Y.
X#\=3#==>Y#<X.                   % Scryer: drei Hilfsvariablen, sechs Ziele
?- X #= abs(Y - Z) + 1.
X#>0, X#=abs(Y-Z)+1.
```

Eingesetzt wird eine Hilfsvariable A nur, wenn sie weder in der Anfrage
noch im kopierten Term (`copy_term/3`) steht, eine Definition hat
(`E #= A`, `A + S #= R` oder `E #<==> A`) und sonst nur in Zielen von
clpz vorkommt: höchstens in einer Domäne (die auf E umgerechnet wird) und
in einem weiteren Ziel, in mehreren nur bei einfachem E (`V`, `V + C`).
Ein Wahrheitswert wird nur als Operand von `#==>` usw. ersetzt. Das ist
gleichwertig, denn A ist nur existenziell gebunden;
`test/clpz_residuals_test.exs` postet die Restziele wieder und vergleicht
alle Lösungen. Was nicht passt (etwa `max/2`-Hilfsziele mit mehreren
Verwendungen eines zusammengesetzten Ausdrucks), bleibt mit `_A` stehen.
Der Nachlauf zählt die Vorkommen einmal sortiert und setzt alles in
einem Durchgang ein (4000 Restziele: gut eine Sekunde).

Andere Domänen (`X in 1..3`, `X in 1..3\/7..sup`) und alles mit
`clpz:monotonic` bleiben wie bei Scryer; `set_prolog_flag(clpz_residuals,
scryer)` stellt die Form Scryers ganz her (damit vergleicht
`test/clpz_golden_test.exs` mit der ursprünglichen Fassung; die lesbare
Form prüft `test/clpz_residuals_test.exs`, auch dass sie wieder gepostet
dasselbe bedeutet).

Klauseln, die clpz-Bedingungen enthalten, übersetzt clpz beim Laden über
`user:goal_expansion/2` in schnellere Ziele (wie Scryer;
`clpz:goal_expansion(false)` schaltet das ab). Scryer expandiert auch
`call/1` zur Laufzeit, PrologEx wie SWI nur beim Laden: dieselbe Bedingung
kann als Aufruf deshalb andere (gleichwertige) Restziele zeigen.

Dafür kamen `library(arithmetic)`, `library(debug)`, `library(terms)`,
`library(freeze)` dazu (siehe „Bibliotheken aus Scryer Prolog“), die
Hilfsprädikate vor einer `goal_expansion` (siehe „Expansion“) und die
Regel für Operatoren und gleichnamige Prädikate von Bibliotheken (siehe
„Module“).

Getestet (`test/clpz_test.exs`, `test/clpz_golden_test.exs`):

  * Beispiele der Dokumentation und Fehler;
  * Triskas Beispielprogramme aus github.com/triska/clpz (Public Domain,
    `test/fixtures/clpz/`): Damen, SEND+MORE, Sudoku, magische Quadrate,
    Springerweg, Aufgabenplanung mit `cumulative/2`, Fakultät in beide
    Richtungen, magisches Sechseck – alle mit denselben Ausgaben wie
    Scryer;
  * 400 zufällige Anfragen (Arithmetik, Domänen, Reifikation, globale
    Bedingungen, Labeling mit Optionen, `fd_*`) mit den Antworten der
    ursprünglichen Fassung samt Restzielen (`test/fixtures/clpz/
    gen_golden.exs`). Dieselben und weitere 1200 Anfragen laufen über
    `test/fixtures/clpz/harness.pl` auch in Scryer und geben dieselben
    Ergebnisse; verschieden sind nur die Reihenfolge der Variablen in
    Summen (`C+D` statt `D+C`: die Standardordnung der Variablen ist
    Sache des Systems) und dass Scryer zwei `freeze/2` auf derselben
    Variablen zu einem zusammenfasst.

Geschwindigkeit: ohne Start (PrologEx rund 1 s, das Laden von clpz,
Scryer 0,4 s) gemessen braucht PrologEx für die Beispielprogramme das 9-
bis 17-Fache (alle 92 Lösungen der 8 Damen 2,4 s statt 0,18 s,
Aufgabenplanung 9,6 statt 0,6 s). Wie bei clpb soll clpz nach und nach in
Elixir rechnen (`PrologEx.Builtins.ClpzPrims`); die Golden-Anfragen und der
Vergleich mit Scryer sind die Referenz dafür, Triskas Fassungen bleiben
als `…_ref` in `clpz.pl` für Zufallsvergleiche (`test/clpz_prims_test.exs`).

Wohin die Zeit geht (Eigenzeit je Ziel, den clpz-Prädikaten zugeordnet,
in deren Klauseln die Ziele stehen): bei Damen, Sechseck und Planung gut
die Hälfte in der Verwaltung – Domäne ablegen (`fd_put`), betroffene
Propagatoren auslösen, die Warteschlange, die clpz (für Scryer, ohne
veränderliche Werte) in Attributen von Hilfsvariablen führt; bei Sudoku
und Springerweg der größte Teil in `all_distinct/1` und `circuit/1`
(Paarungen und starke Zusammenhangskomponenten über Attribute); Domänen
und Schranken 2–19 %, die arithmetischen Propagatoren um 10 %.

**Schranken ohne `n/1`.** Das Original hüllt ganze Schranken in `n(N)`,
damit seine Klauseln die Fälle Zahl/`inf`/`sup` über das erste Argument
auswählen können (`from_to(n(1),n(5))`). PrologEx speichert die Zahl
selbst (`from_to(1,5)`); die Fälle unterscheiden Typtests (`integer/1`).
Das spart je Schranke eine Struktur und je Zugriff ein Auspacken, auf
beiden Seiten: in Elixir rechnen die Domänenbuiltins ohnehin mit
`:inf | :sup | Zahl`, in Prolog fallen `n(X)`-Muster und `X = n(V)` weg.
Zwei Stellen sind nicht rein mechanisch: In der Standardordnung sortieren
`inf` und `sup` als Atome *hinter* allen Zahlen, also bekommt `keysort/2`
über Intervallen einen eigenen Schlüssel (`merge_intervals_ref/2`); und
wo das Original mit `X = n(V)` zugleich prüfte, dass eine Schranke
endlich ist (`domain_infimum(D, n(I))`, `from_to(F,F) -> F = n(X)`),
steht jetzt ein ausdrücklicher `integer/1`-Test, damit `inf`/`sup` wie
bisher scheitern statt gebunden zu werden. Ein Test sucht nach vielen
Constraints aller Art die Attribute nach `n(_)` ab. Reduktionen im
Korpus −2 bis −14 % (8 Damen −10 %, Tripel −14 %, Sechseck −10 %), die
Attribute der Planung 5 % kleiner; Laufzeit im Rauschen.

**Die Darstellung hat eine benannte API.** Lebender Prolog-Code baut und
prüft Domänen nur noch über vier Builtins: `interval(L, U, D)` (die
Domäne L..U, leer bei L > U; die 17 Stellen in den Propagatoren, die
`from_to(L,U)` als Argument von `domains_intersection/3` bauten, dazu
`default_domain/1`, `element_domain/2`), `empty_domain(D)`,
`singleton_domain(D, V)` (der Einzelwert-Test `from_to(F,F)` in
`put_terminating` und `put_full`) und `is_domain(D)`; das Labeling mit
`enum` läuft über `domain_intervals/2`. Alles, was die Struktur
(`empty`, `from_to/2`, `split/3`) zerlegt, sitzt damit in den
Elixir-Builtins. Die Darstellung ist so austauschbar, ohne `clpz.pl`
anzufassen. Dabei kam heraus, dass `ptzdiv` bei `Z = 0` ein festes
`split(0, …)` baute, während `domains_union/3` den Spalt anders legt –
dieselbe Menge, anderer Term; der Vergleichstest hatte das sofort
gesehen.

**Domänen als kanonische Intervallliste.** Statt Triskas balancierter
Bäume (`split(S, from_to(…), from_to(…))`) ist eine Domäne eine Liste
maximaler Intervalle, aufsteigend, paarweise nicht benachbart, Punkte als
Zahl: `[inf..3, 5, 9..13, 16..sup]`, `[]` leer, `[inf..sup]` alle Zahlen.
Jede Menge hat genau eine Darstellung, `==` auf Domänen ist
Mengengleichheit, und die Terme sind die Dreps von clpz als Liste
(`fd_dom/2` ist ein `\/`-Falten). Alle Operationen stehen in
`PrologEx.Builtins.ClpzDom` (reines Elixir, Mischläufe über sortierte
Listen, O(k+m)); die Mengenoperationen sind exakt, `expand`,
`expand_more`, `contract`, `contract_less` rechnen wie das Original
intervallweise mit den Schranken – bewusste Obermengen, von denen die
Propagation von `ptimes` abhängt. Geprüft wird das Modul gegen ein
Mengenorakel (test/clpz_dom_test.exs: Elemente in einem Fenster plus
„unten offen“/„oben offen“), und vor dem Umschalten wurden die alten
Baum-Builtins auf 9000 Zufallsfällen als Mengen mit ihm verglichen (keine
Abweichung, auch nicht in den Eigenheiten: für `inf..sup` ist die
„kleinste endliche Schranke“ `sup` und die Spannweite `inf`, und
`domain_subdomain/2` scheitert für die leere Domäne). Die
`_ref`-Originale der Domänenprädikate und ihre Helfer sind gelöscht (rund
450 Zeilen); eine Eingabe, die keine Domäne ist, gibt jetzt
`type_error(clpz_domain, T)` statt der zufälligen Klauselwahl des
Originals. Baum gegen Liste: O(log k) gegen O(k) je Zugriff bei k
Intervallen. Gemessen (alt/neu abwechselnd): im Korpus kein Beispiel
langsamer, die Reduktionen für 8 Damen −5 %; die Stressfälle mit großen,
löchrigen Domänen sind mit der Liste *schneller* – aus 1..8000 jeden
zweiten Wert streichen (4000 Löcher) 8,7 → 6,5 s, 100 Damen mit `ff`
1,77 → 1,49 s, `all_distinct` über 100 Variablen mit je 50 Löchern gleich
(39 → 37 s, die Zeit liegt dort in `all_distinct`). Der Grund: jeder
Zugriff dekodierte schon beim Baum den ganzen Term, und die Liste braucht
dabei weder Pfadkopien noch Knoten. Damit das stimmt, arbeiten die
häufigsten Zugriffe ohne Dekodieren auf dem Term (Infimum, Supremum,
Einzelwert-Test, `domain_contains/2` mit frühem Abbruch, die Spannweite
aus erstem und letztem Intervall); ohne das kosteten Dekodieren und
Prüfen 5–15 %. Die Operationen prüfen die Ordnung der Liste nicht mehr
(nur `is_domain/1` tut das), sie vertrauen den Termen aus ClpzDom.
Entfernen (`remove`, `remove_greater_than`, `remove_smaller_than`) und
`contains?` laufen nur bis zur betroffenen Stelle und übernehmen den Rest
der Liste unverändert; kommt der Wert nicht vor, ist das Ergebnis die
Domäne selbst (sieve(2000) −2,5 % Reduktionen, Laufzeit gleich: dort
kosten Dekodieren und Kodieren des Terms mehr). Für dichte
Domänen nahe 0 bleibt eine Bitmengen-Darstellung (`0b101000`, verschoben
als `shifted_dombits(3, 0b101)`) vorgemerkt; sie passte hinter dieselbe
API.

**Merkzettel für kodierte Domänen; `OldDom == Dom` ohne Termvergleich.**
Jede Kodierung einer Domäne (Liste → Term) und jedes Dekodieren in
`fdget` vermerkt das Paar (Term, Liste) in einem Merkzettel mit 4 Plätzen;
erkannt wird ein Term an seiner physischen Identität (`:erts_debug.same`,
O(1)) – ein gefundener Eintrag ist also garantiert die Liste genau dieses
Terms. Nur kanonische Paare kommen hinein (sonst ergäben `[5..5]` und
`[5]` dieselbe Liste). Damit: `fdput` erkennt, ob die gespeicherte Domäne
die ist, aus der die neue berechnet wurde, und entscheidet „geändert“ per
`===` auf den kanonischen Listen – unverändert: das Attribut neu ohne
Kodieren und ohne `==`; verändert: direkt zur Terminierungslogik.
`put_terminating` vergleicht zwei bekannte Domänen als Listen statt mit
`==` auf den Termen (bei `X #\= N` aus Prolog, sieve: gleich bis zur
Löschstelle, also Hunderte Intervalle je Vergleich). Und eine eben
kodierte Domäne wird nicht noch einmal dekodiert. Lesende Zugriffe (`Ps`
verworfen) tragen nichts ein und schlagen nicht nach – sonst kostete es
bei vielen Variablen ohne Treffer (holes). Reduktionen sieve(2000) −72 %,
Pythagoras −16 %, Sechseck −6 %, n_queens −4 %, übrige ±0,4 %; Laufzeit
(6 Runden, Median) sieve(5000) −44 %, Pythagoras −6 %, holes(50) −5 %.

**`cumulative/2` bei fester Dauer: ein reifiziertes `in/2` je Zeitscheibe.**
Triskas Zerlegung legt für jede Aufgabe und jeden Zeitpunkt T des
Horizonts `((T #>= Start) #/\ (T #< End)) #<==> B` an: zwei reifizierte
Vergleiche, eine Konjunktion, zwei Hilfsvariablen. Ist die Dauer D eine
Zahl, läuft die Aufgabe zum Zeitpunkt T genau dann, wenn `Start in
T-D+1..T`; PrologEx legt dann `B #<==> (Start in T-D+1..T)` an – ein
Propagator, domänenkonsistent (bei `B = 0` fällt das ganze Intervall aus
der Domäne). Mit variabler Dauer bleibt es beim Original. Dieselben
Lösungen (test/clpz_cumulative_test.exs prüft gegen die ursprüngliche
Zerlegung); `label/1` und `labeling([min(E)])` liefern sie in derselben
Reihenfolge wie Scryer, Strategien mit Domänengrößen (`ff`, `ffc`) wegen
der stärkeren Propagation in anderer. Die Restziele sind kürzer als in
Scryer (`S in 2..3 #<==> B` statt der Paare von Vergleichen). Das Beispiel
von Triska (vier Aufgaben, Starts in 0..100, `labeling([min(End)])`):
Aufstellen 364 → 201 ms, mit Optimieren 505 → 291 ms (Scryer 262 bzw.
509 ms); bei Horizont 400: 2,1 → 1,0 s (Scryer 1,9 s).

**Paarung in `all_distinct` ohne MapSet und Access.** Die Propagation von
`all_distinct/1` sucht eine maximale Paarung (augmentierende Pfade) und
streicht dann Werte, die weder von einem freien Wert aus erreichbar noch
mit ihrer Variablen in einer starken Zusammenhangskomponente sind
(Tarjan). Die Mengen darin sind jetzt Maps mit `is_map_key` statt
`MapSet`, Zugriffe `Map.get` statt `mv[j]` (das Access-Protokoll allein
kostete 12 % der Gesamtzeit), die Schleifen direkte Rekursion statt
`reduce_while` mit Closure je Wert; Reihenfolge und Ergebnis sind
unverändert. holes(30)/holes(40): Reduktionen −49 %/−55 %, Laufzeit
holes(50) 1,16–1,33 → 0,84–0,87 s, holes(60) 2,5–2,7 → 1,85–1,88 s;
die übrigen Beispiele unberührt. Danach noch die Adjazenz (Wert →
Variablen) einmal und ohne Closure je Paar gebaut; ihre Schlüssel sind
zugleich die vorkommenden Werte (vorher eigens mit `flat_map` + `uniq`
gesammelt): Reduktionen holes −15 %, Laufzeit im Median −3 %.

**Attribute schreiben ohne Aus- und Einpacken.** clpz schreibt seine
Attribute über `Atts.put_one/4` (das Elixir-Gegenstück zu
`put_atts(V, +A)`; die Prolog-Builtins `get_atts/2`, `put_atts/2` liegen
nur noch auf kalten Pfaden). Ein vorhandenes Attribut wird jetzt direkt in
der gespeicherten Liste ersetzt (Schlüsselvergleich ohne Tupel je
Element, der Rest hinter der Stelle bleibt, wie er ist); die Deklaration
wird nur noch gelesen, wenn ein neues Attribut einsortiert wird, und die
Variable nur einmal dereferenziert. Nebenbei: `update_attr/4` wertete die
Änderungsfunktion für schon attributierte Variablen zweimal aus (der
Default `%{module => fun.(nil)}` wurde vorab berechnet) – jetzt einmal.
Reduktionen pyth −5,9 %, magic_hexagon −3,2 %, n_queens(30) −2,9 %,
zebra −1,6 %; Laufzeit im Median pyth −7,5 %, magic_hexagon −4,5 %.
Ein *neues* Attribut wird in einem Durchlauf einsortiert (vor das erste,
das in der Deklaration danach kommt – die Liste ist schon sortiert),
statt Schlüssel zu bilden, mit `sort_by`/`find_index` zu sortieren und
zurückzuwandeln. Das ist häufiger, als man denkt: `clpz_aux(queued)`
wird ständig entfernt und neu gesetzt. Reduktionen pyth −2,8 %,
magic_hexagon −2,5 %, n_queens −2,3 %; Laufzeit im Median pyth −4,6 %,
magic_hexagon −3,9 %.

Bisher in Elixir:

  * die Domänen (`domain_remove/3`, Schnitt, Vereinigung, Differenz,
    Komplement, Infimum/Supremum, Strecken, Stauchen, Verschieben,
    Spiegeln, Intervalle, Listen) und die Schranken-Arithmetik (`cis_*`,
    mit `inf`/`sup`): reine Funktionen, die clpz.pl über `goal_expansion/2`
    direkt aufruft (kein zusätzlicher Schritt). Weg entlang eines Pfads
    (`domain_remove/3`, `domain_contains/2`, Infimum, Supremum) auf dem
    Term, die übrigen Teilbäume bleiben geteilt wie im Original.
    Unerwartete Argumente (ungebunden, keine Domäne) und alles, was im
    Original einen Fehler wirft, rechnet das Original. Einzeln gemessen
    (ohne Aufrufrahmen): `domain_remove/3` 10 → 2 µs (16 Intervalle 28 →
    1,5), Schnitt 65 → 6 µs, `domain_contains/2` 11 → 0,5 µs. Insgesamt
    (abwechselnd gemessen, je Bestwert aus 5): 8 Damen alle Lösungen
    −5 bis −9 %, 40 Damen −11 bis −21 %, Sechseck −6 bis −9 %, Planung
    −3 bis −8 %, Sudoku −3 bis −5 %, Fakultät rückwärts −9 bis −22 %;
    kein Beispiel langsamer.
  * die Verwaltung der Propagation: `fd_get/3,5`, Domäne ablegen
    (`put_terminating//3`, auch `fd_put//3`: Terminierung über Ränder und
    Spanne, dann die betroffenen Propagatoren auslösen), `trigger_props//1,2,3`,
    `trigger_prop//1`, Einreihen (`insert_queue//2`, `queue_goal//1`, …)
    und Entnehmen (`do_queue//0` als kleine Schleife über
    `'$clpz_queue_next'/2`: Queue eingeschaltet?, dann Ziele, schnelle,
    langsame Propagatoren). Der Zustand bleibt der des Originals – das
    Attribut `clpz_attr/6` an jeder Variablen, die Warteschlange als
    offene Listen in Attributen ihrer vier Variablen, `clpz_aux(queued)` am
    Zustand eines eingereihten Propagators –, die Propagatoren selbst
    rechnen weiter in Prolog. Abwechselnd gemessen (je Bestwert aus 5):
    alle Lösungen der 8 Damen 1,6–1,8 → 0,6 s, 40 Damen 2,1–2,3 → 0,8–0,9 s,
    Sechseck 1,7–1,9 → 0,9–1,0 s, magische Quadrate (3×3, alle) 0,4–0,5 →
    0,2 s, Fakultät rückwärts 0,33 → 0,13 s, Planung 6,8–7,5 → 4,7 s,
    Springerweg 2,6–2,7 → 1,9–2,2 s, Sudoku 0,65–0,8 → 0,57–0,61 s.
    Geprüft wie die Domänen gegen die `_ref`-Fassungen, hier über den
    ganzen Zustand: Zufallsbedingungen bauen einen Zustand auf, dann
    dieselbe Operation mit beiden Fassungen (Domäne ablegen, auslösen,
    einreihen, die ganze Propagation bis zum Fixpunkt); alle erreichbaren
    Attribute samt Warteschlangen müssen Varianten sein
    (`test/clpz_queue_test.exs`).
  * die häufigsten Propagatoren in `activate_propagator//1`: `pneq`
    (`X #\= Y`), `absdiff_neq` (`abs(X-Y) #\= C`, Damen), `pexclude` und
    `pdifferent` (`all_different/1`), `pplus` (`X+Y #= Z`) und
    `scalar_product_eq` (lineare Gleichungen, mit `sum_finite_domains` und
    dem Kürzen der Schranken) – je in den Zweigen, die nur Domänen ändern,
    Propagatoren töten oder prüfen. Ein Zweig, der direkt bindet (`Z is
    X + Y`) oder neue Bedingungen aufstellt, und jeder andere Propagator
    rechnet das Original (`activate_propagator_ref//1`); vorher ist nichts
    geändert, Reihenfolge und Wecken bleiben also wie dort. Abwechselnd
    gemessen: Sechseck 0,91–0,95 → 0,20–0,23 s, magische Quadrate (3×3,
    alle) 0,22 → 0,08 s, 8 Damen (alle) 0,52 → 0,24–0,26 s, SEND+MORE
    10–16 → 4 ms, Fakultät rückwärts 0,13 → 0,09–0,10 s; Planung (noch
    ohne ihre Propagatoren) unverändert. Geprüft mit synthetischen
    Propagatoren (zufällige Argumente aus Variablen mit Domänen, Zahlen,
    Wiederholungen) und mit denen aufgestellter Zustände, je einzeln und
    bis zum Fixpunkt gegen das Original.
  * `all_distinct/1` und `circuit/1` (`pdistinct`, `pcircuit`): Triskas
    `distinct//1` rechnet unter `with_local_attributes/3` über
    Hilfsattribute (Kanten, Fluss, Eltern, Tarjans Indizes) eine Liste
    `neq_num(V, N)` und wendet sie bei abgeschalteter Queue an. Die Liste
    rechnet jetzt Elixir: eine maximale Paarung (augmentierende Pfade),
    dann entfällt eine Kante V–N, die nicht gepaart ist, deren Wert nicht
    von einem freien Wert aus erreichbar ist und deren Enden in
    verschiedenen starken Komponenten liegen (Tarjan) – nach Régin genau
    die Kanten in keiner maximalen Paarung, also dieselbe Menge, welche
    Paarung man auch findet, in der Reihenfolge des Originals (Variablen
    wie in der Liste, Werte absteigend). `circuit/1` prüft danach, ob der
    Graph der möglichen Nachfolger stark zusammenhängt. Eine Variable, die
    doppelt in der Liste steht, rechnet das Original. Sudoku 0,59–0,68 →
    0,05 s, Springerweg 2,0 → 0,31–0,33 s.
  * die Propagatoren der Planung: `reified_geq` (`X #>= Y #<==> B`),
    `reified_and` (`#/\` reifiziert), `scalar_product_leq` (`Σ C·V #=< P`)
    und `pgeq` (`A #>= B`). Hier binden viele Zweige (`B = 1`, `A = B`);
    das darf Elixir, wenn die Bindung die letzte Aktion des Zweigs ist –
    die Maschine weckt danach wie nach dem Original. Zweige mit zwei
    Bindungen oder mit neuen Bedingungen (`B = 0` stellt `X #< Y` auf)
    rechnet das Original; mit dem Ergebnis sterben auch die Propagatoren
    der Teilausdrücke (`kill/2` über die `Ps`-Liste). Planung 4,0–4,1 →
    3,3–3,4 s, die übrigen Beispiele unverändert.
  * `ptimes` (`X*Y #= Z`, mit `min_max_factor/8`, `min_factor/5`,
    `max_factor/5` als Schranken-Arithmetik; die zwei Sonderfälle, die unter
    `findall/3` Hilfsbedingungen aufstellen, und `X*X #= Z` rechnet das
    Original), `pmax` und `pmin` (Ziele wie im Original über
    `queue_goal//1`, nur `X #=< Y` aufstellen nicht), dazu die bindenden
    Zweige von `pplus` (`Z is X+Y`, `Y = Z` bei `X = 0`, …), später auch
    `pabs` (`abs(X) #= Y`, ohne `X in -Y \/ Y`; Springerweg −5 %
    Reduktionen). Ein Beispiel
    mit Produkt, Maximum und Minimum (`Z #= X*Y, M #= max(X,Y), N #=
    min(X,Y)`, alle 1628 Lösungen) 1,05 → 0,54–0,64 s; Planung 2,9–3,2 →
    2,9–3,0 s, Reduktionen −3 bis −6 % in Planung, Sechseck, Springerweg
    und magischen Quadraten.
  * `reified_eq` und `reified_neq` (`#<==>` mit `#=` und `#\=`), wie
    `reified_geq`; `pexp` (`X^Y #= Z`) mit den ganzzahligen Wurzeln und
    Logarithmen des Originals (dieselbe Bisektion). Das Original rechnet
    `X = 0`, `Y == Z`, ein gerades `Y` bei bekanntem `Z` (`X in -R \/ R`)
    und `B = 1` bzw. `B = 0` mit neuer Bedingung. Pythagoreische Tripel
    bis 40 (`X^2 + Y^2 #= Z^2`, alle) 640 → 55–81 ms (Scryer 176 ms),
    magische Folge (7) 77–80 → 42–57 ms (Scryer 39 ms).
  * `ptzdiv` (`X // Y #= Z`), `prem` (`X rem Y #= Z`) und `pmod` (`X mod
    Y #= Z`, mit `pmodz` und `pmody`). Das Original rechnet `Y = -1` bei
    `//`, `X rem Y` mit bekanntem `X` (neue Bedingung `Z in L..U`) und den
    Fall `Z = X` mitten im Propagator. Teilbarkeitsrätsel 29 → 4–5 ms
    (Scryer 10 ms).
  * `reified_or`, `reified_not`, `pimpl` (`#\/`, `#\`, `#==>`) und
    `x_leq_y_plus_c` (`X #=< Y + C`). Das Original rechnet `B = 0` bei
    `reified_or` (zwei Bindungen). Implikationsrätsel −9 % Reduktionen.
  * `pelement` (`element/3`): die Vereinigung der Domänen der möglichen
    Elemente in einem Schritt statt Element für Element. Ein Rätsel mit
    `element/3` 10 → 7 ms.
  * `pgcc_check` und `pgcc_check_single` (`gcc_check//1`, die einfache
    Prüfung von `global_cardinality/2,3`). Das Original bindet mitten in
    der Schleife bei abgeschalteter Queue (der Hook reiht dann nur ein);
    Elixir rechnet eine einzige Bindung im letzten Paar, wenn die Variable
    die laufende Queue hat, und bindet sie nach `enable_queue//0` als
    letzte Aktion (der Hook rechnet die Queue dann gleich statt der
    äußeren Schleife, der Fixpunkt ist derselbe); mehrere Bindungen oder
    eine früher: das Original. Das gcc-Beispiel 122–134 → 101–115 ms
    (−8 % Reduktionen); den größten Teil rechnet weiter `gcc_global//2`.
  * `gcc_global//2` (`pgcc`, `pgcc_single`, Régins Flussverfahren): der
    reine Kern unter `with_local_attributes/3` – Wertenetz, zulässiger und
    maximaler Fluss, Tarjans Komponenten, die Liste der `neq_num/2` – als
    `$clpz_gcc_goals/3` in Elixir (`PrologEx.Builtins.ClpzGcc`) mit Maps
    statt Attributen, Schritt für Schritt in derselben Reihenfolge; die
    Ziele werden wie bisher in Prolog gesetzt. Unendliche Grenzen einer
    Anzahl: das Original. Welche Variablen-Wert-Kanten wegfallen, hängt
    nach Régin nicht davon ab, welcher maximale Fluss gefunden wird. Das
    gcc-Beispiel 83–94 → 18 ms (Scryer 16 ms), 11,6 → 2,5 Mio.
    Reduktionen.
  * zwei Kosten, die mit der Zahl der Constraints an einer Variablen
    wuchsen (Aufstellen insgesamt also überlinear): `get_atts/2` und
    `put_atts/2` kopierten das ganze Attribut (mit den Propagatorlisten)
    bei jedem Zugriff, um Markierungen zu entfernen – jetzt nur die oberste
    Ebene; `phrase/2,3` löste den ganzen Rumpf samt Argumenten der
    Nichtterminale auf (clpz ruft `phrase(init_propagator_(…), …)` und
    `fd_put/3` mit dem Attribut als Argument) – jetzt nur Steuerkonstrukte
    und Listengerüste (ein Fehler: wie bisher über den ganz aufgelösten
    Rumpf). `fd_get` + `fd_put` an einer Variable mit 120 Propagatoren:
    170 → 25 µs. Aufstellen von 30 Damen 270–290 → 180–260 ms, 60 Damen
    1,64 → 1,1 s.
  * `x_neq_y_plus_z` (`X #\= Y + Z`), `scalar_product_neq` (nur die Zweige
    ohne neue Bedingungen: keine Variable mehr, sonst nichts zu tun),
    `reified_in` (`B #<==> X in D` bei offenem B), `reified_fd`, `pxor` und
    `psign`; `neq/2` aus einem Zweig, `domain/2` bei bekanntem B und die
    Zweige von `scalar_product_neq` mit neuen Bedingungen rechnet das
    Original. Im Korpus kommen sie nicht vor (dort läuft in Prolog kein
    Propagator mehr außer Rückfällen).
  * Aufstellen: `v_or_i/1` (jede Klausel des Matchers von `#=`, `#\=`,
    `#>=` prüft damit ihre Argumente) als Builtin – eine Zahl oder eine
    Variable mit clpz-Attribut, eine Variable ohne (`non_monotonic/1`,
    Fehler bei `clpz:monotonic`): das Original; `trigger_once_/2`,
    `fd_put/3` und die vom Matcher erzeugten Klauseln rufen die DCG-Regeln
    direkt statt über `phrase/3`. Ein `X #\= Y` 160 → 70–100 µs, 30 Damen
    aufstellen 150–205 → 125–135 ms (Scryer 51 ms).
  * Queue: bindet ein Propagator in der Schleife von `do_queue//0` eine
    Variable mit Domäne, ging es bisher zurück nach Prolog (die Maschine
    weckt `verify_attributes/3`, das reiht die Propagatoren der Variablen
    ein und ruft `do_queue//0` geschachtelt). Ist clpz das einzige Modul
    mit `verify_attributes/3`, hat die Variable nur clpz-Attribute (kein
    `freeze`/`dif`) und ist ihre Queue die laufende, rechnet die Schleife
    das Wecken selbst wie die Maschine (Bindungen zurück, Hook je
    Variable, Bindungen wieder) und läuft weiter – das geschachtelte
    `do_queue//0` hätte genau diese Queue geleert. Planung 1,63–1,85 →
    1,34–1,49 s (−5 % Reduktionen), Springerweg und Sechseck etwas
    schneller.
  * `variables_same_queue/1` bindet beim Zusammenlegen die Variablen der
    übrigen Queues; deren Wecken tut nichts (kein clpz/1, nur
    clpz-Attribute, `verify_attributes/3` gibt `[]`). Ist clpz das einzige
    Hook-Modul, weckt die Maschine sie nicht mehr: beim Aufstellen der
    Planung 10435 → 4570 Hook-Aufrufe, −5 % Reduktionen.
  * Abkürzer für `#\=`: der Matcher probiert seine Klauseln der Reihe nach
    (bei `abs(X-Y) #\= D` zehn, bevor die passende greift). Ein Builtin
    erkennt einfache Formen – Zahl oder Variable mit Domäne auf beiden
    Seiten, `abs(X-Y)` gegen eine Zahl –, bei denen alle früheren Klauseln
    ohne Wirkung scheitern, und es läuft gleich der Rumpf der Klausel, die
    das Original nähme; sonst der Matcher wie bisher. 30 Damen aufstellen
    143 → 83 ms (Scryer 51 ms).
  * `left_right_linsum_const/5` (zerlegt beide Seiten von `#=`, `#\=`,
    `#>=` in Σ C·V + Konstante; `#>=` ruft es immer, die anderen für
    lineare Ausdrücke) in Elixir. Eine Variable ohne Domäne bei
    `clpz:monotonic`, `?(X)`/`#(X)` und Koeffizient 0 bei einer Variablen
    ohne Domäne (beides gibt ihr eine): das Original. SEND+MORE −16 %
    Reduktionen, Rucksack −9 %, magische Reihe −7 %, Planung −4 %.
  * Reifikation (`#<==>`, `#==>`, `#/\`, …), erste Stufe: Abkürzer für
    die häufigen Teile, alles Übrige wie bisher.
    * `in/2` mit einer Zahl oder `N..M` (Zahlen, `inf`, `sup`): die
      Domäne gleich, ohne `fd_variable/1`, `must_be/2` und
      `drep_to_domain/2` (jede reifizierte Teilbedingung stellt `B in 0..1`).
    * `reifiable/1` in Elixir, wenn es gelingt (`?(V)`/`#(V)` mit V ohne
      Domäne: V bekommt `inf..sup` wie bei `must_be_fd_integer/1`);
      scheitert es, sucht das Original weiter (und bindet dabei Variablen
      oder wirft `instantiation_error` – auch das bleibt so).
    * `parse_reified_clpz//3` für eine Zahl oder eine Variable mit
      Domäne: gleich `R = E, D = 1`.
    * `fd_put/3` und `trigger_once_/2` (neue Queue, ablegen bzw. auslösen,
      `do_queue//0`) als ein Builtin; braucht die Schleife Prolog, geht es
      mit `do_queue_/3` weiter.

    Ein Schalter (`'$clpz_fast'(off)`) schaltet die Abkürzer für die
    Vergleichstests ab. Planung: Aufstellen 0,9–1,05 → 0,8 s, ganz
    1,41–1,49 → 0,97–1,11 s (Scryer 0,9 s), −23 % Reduktionen; magische
    Reihe −18 %.
  * Reifikation, zweite Stufe: `pit/4` (Propagator bauen, neue Queue,
    `init_propagator_//2`, `variables_same_queue/1`) als ein Builtin –
    `propagator_init_trigger//2`, die vom Matcher erzeugten Klauseln und
    der Abkürzer von `#\=` rufen es, danach `trigger_once_/2`; mit einem
    weiteren Hook-Modul das Original. `a//3`, `a//2`, `a//1` (die
    Einträge für Hilfsvariablen) in Elixir. Planung: Aufstellen
    0,63–0,72 → 0,55–0,63 s, ganz 0,84–0,93 s (Scryer 0,81–0,9 s).
  * `verify_attributes/3`, der Hook bei jeder Bindung: eine Variable ohne
    clpz-Attribut (der Zustand eines getöteten Propagators, eine
    zusammengelegte Warteschlange – die meisten Aufrufe) gibt gleich `Gs =
    []`; bekommt eine Variable mit Domäne eine Zahl, prüft Elixir die Domäne
    und reiht alle ihre Propagatoren ein, `Gs = [phrase(do_queue, [Q], _)]`
    wie im Original. Ein Wert, der keine Zahl ist (Typfehler), rechnet das
    Original. Später auch zwei Variablen mit Domänen (Schnitt, Propagatoren
    zusammen, Queues zusammenlegen, ablegen, auslösen), wenn clpz das
    einzige Modul mit `verify_attributes/3` ist (das Zusammenlegen bindet
    Queue-Variablen; deren Wecken kommt hier erst nach dem Hook): Planung
    −15 % Reduktionen. Abwechselnd gemessen: Planung
    2,8–3,1 → 2,4–2,7 s, 8 Damen (alle) 250–300 → 190–220 ms, Springerweg
    0,34 → 0,29–0,37 s; Reduktionen −19 % (Planung), −32 % (8 Damen),
    −10 bis −11 % (Springerweg, Sechseck, magische Quadrate).
  * `variables_same_queue/1`, das Zusammenlegen der Warteschlangen bei jedem
    Aufstellen eines Propagators: die Queues der Variablen sortiert, die
    erste bleibt, jede weitere wird wie im Original an die *vorige*
    angehängt (eine Kette), dann geleert und mit der ersten unifiziert.
    Planung 2,4–2,6 → 1,6–1,65 s, Springerweg 0,30–0,32 → 0,25–0,26 s,
    Sechseck 0,20–0,21 → 0,17–0,20 s.
  * die Schleife von `do_queue//0`: Elixir arbeitet die Propagatoren der
    Queue selbst der Reihe nach ab und kehrt nur für ein Ziel aus der Queue,
    einen Propagator für das Original und nach einer Bindung, nach der die
    Maschine wecken muss, nach Prolog zurück. Das Binden des Zustands eines
    getöteten Propagators (`State = dead`, nach fast jeder Aktivierung)
    gilt als erledigt, wenn sein Wecken nichts tun kann: nur clpz-interne
    Attribute, und clpz ist das einzige Modul mit `verify_attributes/3`
    (sonst läuft das Wecken wie bisher; geprüft mit einem Modul, das jedes
    Wecken ausgibt, und mit `freeze/2` am Zustand). 8 Damen (alle) 190 →
    125–135 ms, Planung 1,65–1,8 → 1,54–1,6 s.
  * das Einhängen beim Aufstellen: `init_propagator_//2` und
    `init_propagator/2` (den Propagator je nach `constraint_wake/2` vorn in
    die Liste der Ziel-, Schranken- oder übrigen Propagatoren, dann
    `fd_put//3`) und `reinforce/1` (nach jedem Aufstellen: Ränder und
    Spanne der Variablen zurücksetzen; eine Variable mit Einzelwert-Domäne,
    noch ungebunden, rechnet das Original, weil es sie bindet). Dazu in der
    Maschine `put_atts/2` für ein schon vorhandenes Attribut: an seiner
    Stelle ersetzen statt die Liste neu nach der Deklaration zu sortieren.
    Ebenso `kill_entailed/1` mit einem noch ungebundenen Propagator `p(P)`
    (wie im Original wird `P = propagator(_, dead)`): in der Planung
    fielen deshalb fast alle `reified_geq` auf das Original zurück.
    Planung 1,55–1,8 → 1,29–1,46 s, Springerweg 0,25–0,26 → 0,20–0,21 s,
    Sechseck 0,16–0,19 → 0,14–0,16 s, magische Quadrate 56–69 → 46–52 ms.

**Weitere Hook-Module.** PrologEx ruft wie SICStus `verify_attributes/3`
in *jedem* Modul mit Attributdeklarationen, auch für Variablen ohne
Attribute dort (Scryer nur in den Modulen, in denen die Variable Attribute
hat) – ein solches Modul sieht also auch die internen Variablen von clpz:
den Zustand getöteter Propagatoren, die Variablen der Warteschlangen. Im
Original werden sie mitten im Propagator geweckt, in Elixir gesammelt
danach. Damit das Ergebnis von der Anwesenheit anderer Hooks nicht
abhängt, rechnet in diesem Fall das Original: jeder Propagator, der eine
attributierte Variable bindet oder scheitert, das Zusammenlegen von
Warteschlangen und `verify_attributes/3` von zwei Variablen mit Domänen;
ebenso, wenn an einem Zustand oder einer Queue-Variablen freeze, dif oder
when hängt. Ohne weitere Hook-Module (freeze, dif, when sind eingebaut und
zählen nicht) bleibt alles in Elixir. Geprüft mit einem Modul, das bei
jedem Wecken etwas ausgibt: 300 Zufallsfälle gegen das Original, und 8
Damen (alle 92 Lösungen) mit genau so vielen Hook-Aufrufen (9530) wie mit
dem reinen Prolog-Code.

clpz verlässt sich auf die Bindungsrichtung der WAM:
`variables_same_queue/1` legt die Warteschlangen mehrerer Variablen
zusammen – sortiert, die erste (älteste) bleibt, die übrigen werden
geleert und mit ihr unifiziert (`Q = Qi`). Band PrologEx früher die linke
an die rechte Variable, ging so die bleibende Queue verloren: falsche
Lösungen, etwa blieb nach `T #= Y*Y, Y + Z #\= 4*Z, Y = 2` `T` offen, und
Labeling fand Lösungen, die eine Bedingung verletzen (1380 statt 390;
gefunden beim Vergleich von 1600 Zufallsanfragen mit Scryer). Seit die
Maschine wie die WAM die jüngere an die ältere bindet, läuft Triskas Code
hier unverändert; die 400 Vergleichsanfragen weichen nur noch in 4 Fällen
von Scryer ab (vorher 7): drei zusammengefasste `freeze`-Ziele und eine
Reihenfolge in einer Summe.

## Tabling: `library(tabling)`

Wie in Scryer Prolog: `:- table Name/N` (auch `Name//N`, mehrere mit
Komma oder als Liste), `abolish_all_tables/0`, `start_tabling/2`, Operator
`table`; dazu wie SWI `tnot/1` und Modi, außerdem `table_statistics/1,2`. Ein getabltes Prädikat
terminiert auch bei Links- und Zyklenrekursion, solange jede Variante
endlich viele Antworten hat:

```prolog
:- use_module(library(tabling)).
:- table path/2.
path(X, Y) :- path(X, Z), edge(Z, Y).
path(X, Y) :- edge(X, Y).

:- table expr//0.                % links-rekursive Grammatik
expr --> expr, "+", term.
expr --> term.
```

  * Die Antworten sind eine Menge: keine zwei Varianten, Reihenfolge die
    des Findens (nicht festgelegt). Seiteneffekte in getablten Prädikaten
    laufen unbestimmt oft.
  * Umsetzung ohne Eingriff in die Maschine: Fixpunkt je stark
    zusammenhängender Komponente (Tarjan). Eine neue Variante wird
    ausgewertet; liest sie dabei eine noch unvollständige Tabelle, liest
    sie sie live – auch Antworten, die während des Lesens dazukommen (so
    schließt Links-Rekursion in einer Runde). Der Anführer einer Komponente
    wiederholt Runden (sich und jedes Mitglied neu auswerten), solange
    jemand eine Antwort verpasst hat (das Ende einer Tabelle gelesen, bevor
    noch eine dazukam). Eifrig: eine Variante ist vollständig, bevor ihre erste
    Antwort zurückkommt – ein `once/1` des Aufrufers spart nichts, die
    Tabelle ist danach aber fertig.
  * Eine Ausnahme in einer Auswertung (auch Zeit- oder Speichergrenze)
    verwirft die unvollständigen Tabellen; vollständige bleiben.
  * Schlüssel wie bei `library(memo)` (Varianten; attributierte Variablen
    im Aufruf: `representation_error`). Neu laden leert die Tabellen des
    Prädikats; hängt es von dynamischen Prädikaten ab, veralten sie still:
    `abolish_all_tables/0`.
  * Geprüft gegen Scryer mit zufälligen Programmen (Links-, Rechts- und
    doppelte Rekursion, verschränkte und geschachtelte Komponenten); `min`
    mit zufälligen gewichteten Graphen gegen die Suche über alle
    einfachen Pfade.
  * Kosten: Programme ohne `:- table` zahlen nichts (der Hook lebt nur,
    solange eine Datei mit `table/1` lädt). Links-Rekursion über einen
    Ring aus n Knoten (alle Paare): n = 100 in 0,08 s, n = 150 in 0,16 s
    (Scryer: 60 s für n = 100); kürzeste Wege mit `min` über 80 Knoten:
    0,09 s. Ungünstig ist doppelte Rekursion über lange Ketten
    (`tc(X,Y) :- tc(X,Z), tc(Z,Y)` über einem Ring): die Kette der
    Tabellen `tc(k,_)` braucht etwa n Runden, und das Live-Lesen bringt
    dort mehr doppelte Ableitungen (Ring aus 40: 0,7 s). Echte semi-naive
    Auswertung gibt es nicht.
  * Modi wie SWI (über Scryer hinaus): `:- table path(_, _, min).` – je
    Belegung der übrigen Argumente bleibt eine Antwort, die beste:
    `min`, `max` (Standardordnung der Terme), `first` (die zuerst
    gefundene), `lattice(P/3)` (`call(P, Alt, Neu, Verbund)`; besser heißt:
    der Verbund ist nicht `==` dem Alten). Höchstens ein Argument mit
    Modus; `_` oder `index` für die übrigen. Ein gebundenes Argument mit
    Modus wird frei gerechnet und dann unifiziert (`path(a, d, 8)`
    scheitert, wenn der kürzeste Weg 4 kostet). Terminiert nur, wenn sich
    jeder Wert endlich oft verbessert (bei `min`: keine negativen Zyklen).
    `sum`, `last` und `po` gibt es nicht (`domain_error(table_mode, M)`).
  * `tnot(:G)`: Negation über ein getabltes Prädikat, stratifiziert und
    geprüft. G (grundiert, getablt) wird ganz ausgewertet: hat es eine
    Antwort, scheitert `tnot`; ist seine Tabelle vollständig ohne Antwort,
    gelingt es. Bleibt sie unvollständig, hängt G negativ von einer gerade
    laufenden Auswertung ab – das Programm ist nicht stratifiziert, etwa
    `win(X) :- move(X, Y), tnot(win(Y)).` über einem Zyklus:
    `permission_error(tnot, incomplete_table, M:G)` statt einer Antwort,
    die von der Reihenfolge der Aufrufe abhinge (mit `\+` heute so; für
    stratifizierte Programme ist `\+` gleichwertig, nur ungeprüft).
    Nicht getablt: `type_error(tabled_predicate, M:N/A)`, nicht grundiert:
    `instantiation_error`.
  * `table_statistics(-S)`: `[tables(T), answers(A), rounds(R)]` über alle
    vollständigen Tabellen (R: Runden seit dem letzten
    `abolish_all_tables/0`); `table_statistics(:PI, -S)`: `[tables(T),
    answers(A)]` für ein Prädikat.
  * Beispiele: `examples/tabling_negation.pl` (stratifiziert gegen nicht
    stratifiziert, `tnot/1`) und `examples/tabling_left_recursion.pl`
    (Links-Rekursion; dazu naiv und semi-naiv von Hand zum Vergleich).
  * Nicht (noch nicht): Well-Founded Semantics (`undefined` statt Fehler),
    semi-naive Auswertung, inkrementelles Tabling.

## Memoisierung: `library(memo)`

Ein memoisiertes Prädikat rechnet jede Variante eines Aufrufs nur einmal
ganz durch und liefert sie danach aus einer Tabelle. Anders als Tabling
(`library(tabling)`) bleibt die Bedeutung die des normalen Prolog:
dieselben Antworten in derselben Reihenfolge, Duplikate bleiben,
Seiteneffekte laufen beim ersten Rechnen. Das Prädikat muss dafür auch
ohne Memo terminieren – Memo spart nur Arbeit.

```prolog
:- use_module(library(memo)).
:- memo fib/2.
fib(0, 0).
fib(1, 1).
fib(N, F) :- N > 1, N1 is N-1, N2 is N-2, fib(N1, F1), fib(N2, F2), F is F1+F2.

:- memo edit/3 as lru(10000).
:- memo number//1 as [first, fifo(500)].
```

  * Optionen nach `as` (einzeln oder als Liste): `lru(N)` (höchstens N
    Einträge, der am längsten nicht benutzte fällt), `fifo(N)` (der älteste
    fällt), `first` (nur die erste Lösung rechnen und merken, wie
    `once/1`), `reentrant` (siehe unten). Verdrängt werden nur fertige
    Einträge; an der Bedeutung ändert eine Grenze nichts, nur an der
    Laufzeit (ist sie kleiner als die Arbeitsmenge, wird neu gerechnet).
  * Schlüssel ist die Variante des Aufrufs: `p(X, a)` und `p(Y, a)` teilen
    sich einen Eintrag, `p(a, a)` nicht. Attributierte Variablen im Aufruf:
    `representation_error(memo_attributed_variable)`.
  * Eifrig: Der erste Aufruf einer Variante sammelt alle Antworten (wie
    `findall/3`), erst dann wird gemerkt. Eine Ausnahme dabei (auch eine
    Zeit- oder Speichergrenze) hinterlässt nichts.
  * Ruft sich eine Variante selbst auf, bevor sie fertig ist (auch über
    andere Prädikate), wäre das in reinem Code eine Endlosschleife:
    `permission_error(reenter, memo, N/A)` – hier ist eher `table/1`
    gemeint. Mit `reentrant` rechnet der innere Aufruf wie normales Prolog
    (für Code, der über globalen Zustand doch terminiert).
  * Die Direktive steht vor den Klauseln (`Name/N` oder `Name//N`); diese
    werden zu `'Name memo'/N`, `Name/N` ruft die Tabelle. Neu laden leert
    die Tabelle. Hängt das Prädikat von dynamischen Prädikaten ab, veraltet
    sie still, wenn diese sich ändern.
  * `abolish_memo/0` (alle), `abolish_memo(:PI)`,
    `memo_statistics(:PI, [entries(E), hits(H), misses(M), evictions(V)])`.
  * Kosten: Programme ohne `:- memo` zahlen nichts, auch nicht beim Laden
    – den Expansions-Hook gibt es nur, solange eine Datei mit `memo/1`
    geladen wird. Ein Aufruf eines memoisierten Prädikats kostet Schlüssel
    bilden und nachschlagen, linear in der Größe des Aufrufs (Listen als
    Argument: deren Länge). Die Tabellen liegen im Prozess und überleben
    die Anfragen der Sitzung.

## Globale Werte: `library(blackboard)`, `library(mutables)`

Wie SICStus (dort eingebaut, hier nach `use_module`):

  * `bb_put(:Key, +T)`, `bb_get(:Key, ?T)`, `bb_delete(:Key, ?T)`,
    `bb_update(:Key, ?Old, ?New)` – Werte je Modul (Key ein Atom oder eine
    Ganzzahl, auch `M:Key`), als Kopie gespeichert, nicht backtrackbar.
    `bb_get/2` und `bb_put/2` führt die Maschine selbst aus, wenn der Aufruf
    sie meint (aus `blackboard` importiert, auch über `iso_ext`, und nicht
    selbst definiert): ohne den Aufrufweg eines Bibliotheks-Builtins,
    atomare und variablenfreie Werte ohne Kopie, eine freie Zielvariable
    direkt gebunden (attributierte: Unifikation, die weckt). `bb_get` und
    `bb_put` kosten so rund 45 % weniger, ein Zähler
    (`bb_get(c, V), V1 is V+1, bb_put(c, V1)`) rund 35 %. Die Werte liegen
    weiter in der Datenbank (gehören zum Programm, nicht zum Prozess).
  * `bb_b_put(:Key, +T)` wie in Scryers `library(iso_ext)` (dort auch
    weitergegeben): backtrackbar und ohne Kopie, wie SWIs `b_setval/2` –
    `bb_get/2` liefert dann dieselben Variablen. Solche Werte stehen in der
    Substitution (Backtracking nimmt sie zurück, die Kompaktierung hält sie
    am Leben) und gelten bis zum Ende der Anfrage; `bb_put/2` ersetzt sie.
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

## Ressourcen begrenzen: `call_with_inference_limit/3`, `call_with_depth_limit/3`, `library(rlimit)`

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

**Standardgrenze, Flag `stack_limit`** (wie SWI, Bytes, Voreinstellung
1 GiB, oder `unlimited`): Jede Anfrage darf den Heap ihres Prozesses um
höchstens so viel wachsen lassen, gemessen ab ihrem Start; die Grenze
gilt nur, solange die Maschine dieser Anfrage läuft (auch beim
Backtracking nach weiteren Antworten), und das Flag wirkt ab der nächsten
Anfrage. So reißt eine endlose Rekursion nicht mehr die ganze VM mit:

```
?- p(X) :- p(X), p(X).   % (in einer Datei)
?- p(a).
Fehler: resource_error(memory)
% Speichergrenze überschritten: stack_limit = 1.0 GiB (ändern: set_prolog_flag(stack_limit, Bytes) oder unlimited). Offene Ziele: 9704695, Choice Points: 0. Wahrscheinlich endlose Rekursion in p/1.
```

Der Fehlerterm trägt die Diagnose:
`error(resource_error(memory), context(Quelle, memory(Bytes, Tiefe,
ChoicePoints, Rekursion)))` mit Quelle `stack_limit` oder
`call_with_memory_limit/2`, Tiefe = offene Ziele, Rekursion = `[N/A]`, wenn
ein Prädikat die offenen Ziele beherrscht (unter den ersten 100 000
mindestens 1000-mal und zur Hälfte), sonst `[]` – dann wachsen die Daten
(`p(X) :- p(X+X)`), nicht der Stapel. Bei eingebauten Prädikaten, die
vorab ablehnen: `memory(Bytes)`. Kosten: gemessen im Rauschen (der
Inferenzzähler liefert beim Erhöhen gleich seinen Stand, die Prüfung ist
ein Vergleich je Schritt und alle 1000 Inferenzen ein Blick auf den Heap).

`assertz/1` und `asserta/1` zählen vorab die Baumgröße der Klausel (mit
Gedächtnis, so teuer wie der geteilte Term; kleine Klauseln ohne): Das
Übersetzen schreibt geteilte Teilterme als Baum aus (`X+X` über 40 Stufen
wären 2^40 Knoten). Ab 10 000 Knoten prüfen sie vorab gegen die
Speichergrenze, ohne Grenze gibt es ab 50 Mio. Knoten
`resource_error(memory)` statt minutenlang zu rechnen.

`call_with_memory_limit(G, Bytes)` (`library(iso_ext)`): `G` wie
`once/1`; wächst der Heap des Prozesses, in dem die Anfrage läuft, dabei
um mehr als `Bytes`, gibt es `error(resource_error(memory),
context(call_with_memory_limit/2, memory(...)))` – fangbar, aber wie bei den Zeitgrenzen nicht
verschluckbar: Fängt `G` die Ausnahme selbst, kommt sie am nächsten
Prüfpunkt wieder, solange der Speicher über der Grenze bleibt.

```prolog
?- catch(call_with_memory_limit((length(L, 1000000), maplist(=(x), L)), 1000000), E, true).
E = error(resource_error(memory),context(call_with_memory_limit/2,memory(1000000))).
```

  * Geprüft wird an denselben Prüfpunkten wie die Zeitgrenzen (alle 1000
    Inferenzen, `Process.info(self(), :total_heap_size)`, etwa 1 µs); vor
    einem Wurf räumt eine Speicherbereinigung Müll weg, damit nur Lebendes
    zählt. Gezählt wird der Zuwachs gegenüber dem Eintritt. Ohne Grenze
    kostet das nichts zusätzlich (gemessen: nrev, tak, queens, clpz im
    Rauschen).
  * Eingebaute Prädikate, die aus kleiner Eingabe auf einen Schlag viel
    anlegen, prüfen vorab (`PrologEx.reserve!/1`): `length/2` und
    `numlist/3,5` ab 10 000 Elementen, `functor/3` ab Stelligkeit 10 000,
    `^`, `**` und `<<` ab 2^65536. Ohne Grenze ist das ein Vergleich und,
    bei so großen Werten, ein Blick ins Prozess-Dictionary. Alle anderen
    legen höchstens ein Vielfaches ihrer Eingabe an; das fängt der nächste
    Prüfpunkt.
  * Nicht gezählt: große Binaries außerhalb des Heaps (lange Atomnamen,
    Stromtexte) und andere Prozesse.

`library(rlimit)` wie SWI: `rlimit(+Resource, -Old, +New)` liest und setzt
die weiche Grenze des Betriebssystems für den ganzen Prozess (`as`,
`core`, `cpu`, `data`, `fsize`, `locks`, `memlock`, `msgqueue`, `nice`,
`nofile`, `nproc`, `rss`, `rtprio`, `rttime`, `sigpending`, `stack`; Bytes
bzw. Sekunden oder `unlimited`). Die BEAM
kennt kein `setrlimit`; PrologEx ruft dafür das Linux-Werkzeug `prlimit`
(util-linux) für die eigene PID auf – ohne es `existence_error(program,
prlimit)`. Ungebundenes oder gleiches New liest nur: `rlimit(nofile, L,
L)`. Über der harten Grenze: `permission_error(modify, rlimit, R)`.

```prolog
?- use_module(library(rlimit)), rlimit(core, Old, 4096).
Old = 0.
```

Die Grenze gilt wie bei SWI für die ganze VM mit allen Anfragen.
`nofile` zeigt sich als Fehler beim Öffnen (`permission_error`) – aber
auch beim Laden von Modulen und bei `rlimit/3` selbst
(`resource_error(file_descriptors)`), also vorher Ströme schließen. Reißt
`as`, `data`, `cpu` oder `fsize`, beendet das Betriebssystem bzw. die
Speicherverwaltung die ganze VM, ohne fangbare Ausnahme. Für Grenzen je
Anfrage: `library(time)` (`call_with_time_limit/2`, siehe dort).

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

## Ohne Seiteneffekte: `call_with_no_side_effects/1`

`call_with_no_side_effects(:G)` (`library(iso_ext)`) ruft G wie `call/1`,
aber jede Wirkung ist **vorher** ein Fehler – sie geschieht nicht:

```
?- call_with_no_side_effects(assertz(f(1))).
error(permission_error(perform,side_effect,assertz(f(1))),context(assertz/1,database))
```

Super-strikt; die Kategorie steht im Kontext:

  * `database`: `assert*`, `retract*`, `abolish`, `dynamic/1` zur
    Laufzeit, Dateien und Bibliotheken laden.
  * `state`: Flags, `op/3`, `char_conversion/2`, globale Variablen
    (`nb_setval/2`, auch `b_setval/2`), `bb_put/2` & Co., `gensym/2`.
  * `io`: jeder Stream-Verkehr – schreiben, **lesen** (es verbraucht
    Eingabe), öffnen, schließen, `set_input/1`, `print/1`, `time/1`,
    `statistics/0`, `listing/1`. Ausnahme: Speicher-Streams, die der
    Bereich selbst öffnet und wieder schließt – `format/3` in eine Senke
    (`format(atom(A), ...)`, `chars(Cs)`, `codes(Cs)`) und
    `with_output_to/2`; darin darf auf die aktuelle Ausgabe (bzw. diesen
    Stream) geschrieben werden, auf andere Streams nicht. Ein innerer
    Bereich schreibt nicht in den Stream eines äußeren. `portray/1` (bei
    `print/1` und `~p`) läuft im Bereich.
  * `external`: Dateisystem ändern, Prozesse, Shell, Umgebung, Netz,
    `halt`.
  * `random`: Zufall (er ändert den Zustand des Generators), auch
    `random/1` und `random_float` in Ausdrücken. Ausnahme: in den Kindern
    von `library(concurrent)` (siehe dort).
  * `memo`, `tabling`: Aufrufe memoisierter und getablter Prädikate (sie
    schreiben in Tabellen).

Erlaubt ist Lesen von Zustand, das ihn nicht ändert: Aufrufe dynamischer
Prädikate, `clause/2`, `current_op/3`, Flags lesen, `nb_getval/2`,
`get_time/1`, `statistics/2`, Dateien abfragen; reine Text-Funktionen
(`term_to_atom/2`, `format_//2` aus `library(format)`); Mutables und
Attribute (backtrackbar, an Termen); Steuerkonstrukte, die ihren Zustand
selbst wieder abräumen (`call_with_time_limit/2`,
`call_with_inference_limit/3`, `call_with_memory_limit/2`, ...).

  * Durchsichtig für Nichtdeterminismus: der Bereich ist ein Zähler in der
    Substitution. Nach der ersten Lösung ist draußen alles erlaubt;
    Backtracking in G hinein öffnet den Bereich wieder, Scheitern und
    Ausnahmen schließen ihn.
  * `findall/3`, `\+`, `forall/2` & Co. laufen im Bereich (sie teilen die
    Substitution).
  * Im Bereich registrierter Code läuft im Bereich, auch wenn er erst
    danach ausgelöst wird: der Cleanup von `setup_call_cleanup/3` (etwa
    durch einen späteren Cut), Ziele von `freeze/2` und `when/2`. Und ein
    draußen eingefrorenes Ziel, das im Bereich geweckt wird, ist dort
    gesperrt.
  * Ein `catch/3` im Bereich darf den Fehler fangen – die Wirkung ist ja
    nicht geschehen.
  * Kosten: Builtins mit Wirkung sind in der Tabelle der Builtins markiert;
    nur sie prüfen den Zähler. Programme ohne den Bereich zahlen nichts
    Messbares.

## Parallel: `library(concurrent)`

Ziele parallel in BEAM-Prozessen, aufgebaut auf `call_with_no_side_effects/1`:
jedes Kind läuft mit einer Kopie des Interpreter-Zustands, super-strikt ohne
Seiteneffekte. Darum ist die Reihenfolge egal, und ein Kind kann jederzeit
beendet werden, ohne etwas halb getan zu haben.

Kosten: Der Zustand (vor allem die Klauseldatenbank samt Bibliotheken, leicht
einige MiB) liegt je Aufruf einmal als `persistent_term`; die Arbeiter lesen
ihn, ohne ihn in ihren Heap zu kopieren (die BEAM kopiert sonst alles, was
ein Prozess einem anderen gibt). **Blockung** wie `schedule(dynamic)` bei
OpenMP mit guided-Paketen: höchstens so viele Arbeiter wie Scheduler (bzw.
`threads(N)`), jeder bekommt ein Paket von Elementen – Rest / (2·Arbeiter),
mindestens eines, oder `chunk(K)` – und holt sich danach das nächste. Jedes
Element läuft auf einem frischen Zustand (eigener Zufall, eigene Ausgabe,
eigenes `concurrent_child/1`, nichts vom Vorgänger); für das Programm sieht
es aus wie ein Kind je Element. `first_solution/3` hat einen Arbeiter je Ziel
(sie laufen gegeneinander). Ein Aufruf kostet damit einmal rund 2 ms
(Ablegen und Freigeben des Zustands), jedes Element rund 20 µs Verwaltung
(frischer Zustand, eigene Anfrage). Vorher kostete jedes Element ein eigenes
Kind mit eigener Kopie des Zustands, rund 2 ms. Lohnend ist Parallelität
also ab etwa 0,1 ms Arbeit je Element.

```prolog
?- use_module(library(concurrent)), use_module(library(iso_ext)).
?- concurrent_maplist(succ, [1,2,3], Ys).           % Ys = [2,3,4]
?- first_solution(X, [(repeat, fail), X = schnell], []).   % X = schnell
?- concurrent_findall(X, [member(X,[a,b]), between(1,3,X)], Bs).
% Bs = [[a,b],[1,2,3]]   (member/between aus library(lists)/library(between))
```

| Prädikat | Bedeutung |
|---|---|
| `concurrent_maplist/2,3,4` | wie `maplist`, je Element ein Prozess (`once`) |
| `concurrent(N, Goals, Opts)` | alle Ziele, höchstens N gleichzeitig; Bindungen werden zusammengeführt |
| `concurrent_forall(Cond, Action[, [threads(N), chunk(K)]])` | `Action` je Lösung von `Cond` (im Aufrufer berechnet) |
| `concurrent_findall(T, Goals, Bags)` | je Ziel alle Lösungen |
| `concurrent_and(Gen, Test[, [threads(N), chunk(K)]])` | wie `(Gen, Test)`, die Tests parallel: `Gen` vorab im Aufrufer (muss endlich sein), je Lösung ein Kind mit allen Lösungen von `Test`; per Backtracking in der Reihenfolge von `(Gen, Test)` (SWI: beliebige Reihenfolge, `Gen` nebenher) |
| `first_solution(X, Goals, [on_fail(stop\|continue), on_error(stop\|continue), output(winner\|all)])` | der Erste gewinnt, die anderen werden beendet; mit `on_error(continue)` zählt eine Ausnahme wie ein Scheitern (werfen oder scheitern alle: scheitert, wie SWI) |
| `concurrent_child(I/N)` | im Kind: Position seines Ziels (1-basiert) und Anzahl der Ziele des innersten Aufrufs; außerhalb scheitert es |
| `concurrent_child_stack(Stack)` | der Stapel der Aufrufe `[I/N, …]`, innerster oben (`concurrent_child(P)` ist `concurrent_child_stack([P\|_])`); außerhalb jedes Kinds `[]`, `length(Stack, D)` ist die Tiefe |

* **Ausnahmen:** wirft ein Kind – auch den Seiteneffekt-Fehler
  `permission_error(perform, side_effect, G)` –, werden alle anderen sofort
  beendet (kein Warten), und die Ausnahme kommt beim Aufrufer an; werfen
  mehrere, entscheidet der Scheduler.
* **Grenzen** des Aufrufers gelten weiter: `call_with_time_limit` als
  gemeinsame Deadline, `call_with_inference_limit` als Budget für alle
  zusammen (die Kinder zählen im selben Zähler), Speichergrenze je Kind,
  `call_with_depth_limit` mit der Ebene, die am Aufrufpunkt erreicht ist (die
  Kinder schreiben größte Ebene und „überschritten“ direkt in den Rahmen des
  Aufrufers – `R` ist dasselbe wie nacheinander). Abfangen kann ein Kind
  keine davon: die Frist überwacht der Aufrufer, Inferenz- und Tiefengrenze
  setzt die Maschine durch (auch ohne `concurrent` nicht per `catch/3`).
* **Fristen** – ohne eigene Optionen, mit `call_with_time_limit/2`:
  - für den ganzen Aufruf drumherum:
    `call_with_time_limit(0.3, concurrent_maplist(G, Xs, Ys))` – läuft sie
    ab, kommt `time_limit_exceeded`, und alle Kinder werden beendet. Die
    Frist überwacht der Aufrufer: ein Kind kann sie nicht abfangen und
    weiterlaufen (auch `catch(…, _, true)` im Kind nützt nichts).
  - je Element innen im Ziel (im Kind erlaubt, der Timer räumt sich selbst
    ab): `concurrent_maplist(\X^Y^call_with_time_limit(0.2, work(X, Y)),
    Xs, Ys)` – eine Überschreitung beendet alles; als Wert statt als Fehler:
    `catch(call_with_time_limit(0.2, work(X, Y)), time_limit_exceeded,
    Y = timeout)`, dann laufen die übrigen weiter.
  - bei `first_solution/3` scheidet eine Strategie mit eigener Frist aus,
    die anderen laufen weiter:
    `first_solution(X, [S1, call_with_time_limit(0.2, S2), S3],
    [on_error(continue)])`.
* **Ergebnisse** kommen als Kopien zurück und werden nach Index unifiziert.
  Geteilte Teilbäume werden dabei ausgerollt (große DAG-Terme werden teuer).
  Attributierte Variablen (`dif`, `freeze`, clpz …) in Zielen oder
  Ergebnissen: `representation_error(concurrent_attributed_variable)`,
  zyklische Terme: `representation_error(cyclic_term)`.
* Teilen Ziele Variablen, rechnet jedes auf seiner Kopie; erst das
  Zusammenführen prüft, ob es passt.
* **Wer bin ich:** `concurrent_child(I/N)` gibt im Kind die Position
  seines Ziels und die Anzahl der Ziele – etwa um einen Suchraum
  aufzuteilen („jedes N-te Element ab I“). Damit hängt ein Ziel aber von
  seinem Platz in der Liste ab, ohne dass man es sieht; sichtbar wird das,
  wenn man den Index mitgibt: `numlist(1, N, Is), concurrent_maplist(G, Is,
  Xs)`.
* **memo/tabling und `b_setval/2`** sind in den Kindern erlaubt: das Kind
  hat Kopien der Tabellen und globalen Variablen des Aufrufers, Neues
  verschwindet mit ihm (der Aufrufer profitiert also nicht davon).
  `nb_setval/2`, `assertz/1` & Co., Flags, `op/3` und `gensym/2` bleiben
  verboten: wer sie schreibt, meint meist eine Wirkung über das Kind
  hinaus. Ein innerer `call_with_no_side_effects/1` im Kind bleibt streng.
* **Ausgabe:** jedes Kind schreibt in einen eigenen Puffer (die aktuelle
  Ausgabe; andere Streams wie `user_error` bleiben verboten). Ausgegeben
  wird beim Aufrufer, wenn alles entschieden ist: nach Erfolg alle Puffer
  in der Reihenfolge der Ziele – wie bei `maplist` nacheinander, unabhängig
  vom Scheduler –, bei `first_solution/3` nur der des Gewinners; bei
  Scheitern oder Ausnahme nichts. Ein beendetes Kind hat also nichts
  ausgegeben. Zum Debuggen gibt `first_solution/3` mit `output(all)` die
  übrigen zusätzlich auf `user_error` aus, je mit Kopfzeile
  (`% Ziel 2: abgebrochen | gescheitert | Ausnahme`, bei abgebrochenen
  das bis dahin Geschriebene), auch wenn es scheitert oder wirft. Im
  Bereich ohne Seiteneffekte geht die Ausgabe nur in einen Stream des
  Bereichs (`with_output_to/2`).
* **Zufall** ist in den Kindern erlaubt: jedes Kind hat einen eigenen
  Generator, der mit ihm verschwindet. Die Startwerte kommen aus dem
  Generator des Aufrufers (eine Zahl je Aufruf, Kind i bekommt Startwert
  aus Zahl und i) – unabhängig vom Scheduler und nach
  `set_random(seed(N))` reproduzierbar; zwei Aufrufe nacheinander geben
  verschiedene Folgen. Hat die Sitzung noch keinen Generator, bleibt das
  so (Startwerte zufällig). Im Bereich ohne Seiteneffekte wird der
  Generator des Aufrufers nur angesehen, nicht weitergeschaltet; ein
  innerer `call_with_no_side_effects/1` im Kind bleibt streng. Beispiel
  für Neustarts: `first_solution(X, [G1, G2], [])` mit randomisierten
  Suchen.
* **Ausgabe in Text** (`format(atom(A), ...)`, `with_output_to/2`) geht
  in den Kindern wie im Bereich ohne Seiteneffekte.
* Unbenutzt kostet die Bibliothek nichts (nichts in der Maschine ändert sich).

Zum Ausprobieren: `mix prolog examples/concurrent.pl -g main -q -g halt`.

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
X = Y geht die Menge an die ältere der beiden über, bei einem Term mit Variablen (X = f(Z))
wird jeder Wert wieder ein `dif` (dabei oft eine kleinere Menge, etwa an
Z). Als Restziele erscheint die Menge wie gewohnt als `dif(X,a), dif(X,b)`
(jeder Wert einmal). Ausschlussmengen werden beim Wecken vor den übrigen
Weckzielen geprüft; alle anderen in der Reihenfolge des Anhängens.

**Bindungsrichtung.** Bei zwei ungebundenen Variablen wird wie in der
WAM (Scryer) die jüngere an die ältere gebunden (größere Kennung, siehe
`PrologEx.Vars`), eine normale aber immer an eine attributierte (nichts
zu wecken). Eine attributierte Variable ist so alt wie ihr erstes
Attribut. Bei `X = Y` mit zwei attributierten wird also die jüngere
gebunden und ihre Hooks sehen die ältere als Wert – Reihenfolge der
`freeze`-Ziele, `dif`-Restziele und `verify_attributes/3` wie in Scryer.
Anders nur `when/2`: Scryers `library(when)` stellt die Bedingungen der
gebundenen Variablen vor die der anderen; hier teilen sich freeze, when
und dif eine Liste, angehängt wird hinten.

**Wecken.** Eine Suspension ist ein kleiner Term am Attribut `"$susp"`
der Variablen: `'$fz'(M:G)` (freeze), `'$wh'(C, M:G)` (when) und
`'$df'(L, R)` (dif-Front). Wartet eine Bedingung auf *mehrere* Variablen
(`when` mit `?=`/`;`, eine dif-Front mit zwei Variablen), hängt derselbe
Eintrag an allen, mit einer `Done`-Variablen davor – gebunden heißt
erledigt, die übrigen Einträge sind tot. Eine Suspension auf *einer*
Variablen braucht das nicht: ist die Variable gebunden, werden ihre
Attribute nie mehr gelesen. Wird eine attributierte Variable gebunden,
verarbeitet die Maschine die Suspensionen direkt nach der Unifikation in
Elixir (`wake_builtin`), ohne Weckziele: Ausschlussmengen und
dif-Fronten werden geprüft, `freeze`-Einträge wandern bei `X = Y` zur
anderen Variablen (hinter deren Einträge), `when`-Bedingungen werden neu
gestellt, und nur Ziele,
die wirklich laufen, kommen auf den Stapel – mit ihrem Modul, ein
Schritt je Ziel. Steht so ein Ziel an, wird alles Weitere aus derselben
Bindung zu Zielen hinter ihm, damit die Reihenfolge des Anhängens auch
gegenüber laufenden Zielen erhalten bleibt. Tote Einträge wirft die
Kompaktierung weg. Nur wenn ein Modul `verify_attributes/3` definiert,
läuft das Wecken als Ziel (Hooks, dann die eingebauten Suspensionen).

Gemessen (`mix run bench/dif_bench.exs`, `bench/psort_bench.exs`,
100 000 Variablen): `freeze` anlegen und wecken in einer Schleife 6,1 →
3,0 µs je Variable (Rest ohne Coroutining: 2,9), `when(nonvar(X), G)`
7,0 → 3,6 µs; 100 000 lebende `freeze` binden 3,3 → 2,1 s, dieselben über
`X = Y` weiterreichen 4,4 → 2,8 s, 100 000 `freeze` an einer Variablen
1,3 → 0,9 s, `dif` an 300 Variablen paarweise 440 → 380 ms. Permutation
Sort (13 Elemente, Sortiertheit mit `freeze` auf den Elementen) 241 → 162
ms, mit `when` 194 → 135 ms – dort waren von 75 000 Maschinenschritten
63 000 Weck-Verwaltung, jetzt 48 000 insgesamt. Was bleibt, ist bei
großen Substitutionen der Preis der Map-Zugriffe (ein Schreibzugriff auf
eine Map mit 300 000 Einträgen kostet 2–3 µs statt 0,2) – siehe
`PrologEx.bind/3` (`:wake`) und die Kompaktierung lebender attributierter
Variablen. `mix run bench/memberd_bench.exs`: `memberd(X, L)` mit 1000
Elementen, alle Antworten, 2200 ms → 3 ms.

`frozen/2`, `copy_term/3` (Body als Konjunktion) und `term_attvars/2` wie
SICStus. Mit `library(iso_ext)` ist `copy_term/3` das von Scryer (und SWI):
die Ziele als Liste, `[]` ohne Attribute, `can_be(list, Gs)` vorab. Die
Bibliotheken aus Scryer (clpz, clpb, ...) zeigen in ihren Beispielen diese
Form. `copy_term/2` und `findall/3` kopieren Attribute nicht mit.

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

Wie Scryer und SWI gibt es auch die Hooks `attribute_goals//1` (Restziele
als DCG; Ziele ohne Modul bekommen `M:` davor) und
`project_attributes(QueryVars, AttrVars)`, den der Toplevel vor den
Restzielen aufruft (etwa damit `library(clpb)` Hilfsvariablen
herausrechnet). Danach ruft PrologEx `M:'$post_residuals'(Vis, Gs0, Gs)`
der Attributmodule, die es haben, mit allen Restzielen und den sichtbaren
Variablen (Anfrage bzw. kopierter Term) – `library(clpz)` rechnet dort
Hilfsvariablen heraus. `copy_term/3` sammelt die Restziele in `findall/3`: Hooks,
die dabei Attribute abbauen (wie bei clpb), lassen das Original unberührt.

## Module

### Interne Prädikate: Namen mit `$`

Prädikate, deren Name mit `$` beginnt (`'$wot_open'/2`, `'$clpz_…'`,
`'$nse_call'/1`, …), gehören dem System. Es sind Hilfsprädikate der
Maschine und der Bibliotheken (gut die Hälfte der Prädikate in `system`):

  * Sie sind intern und können sich ohne Vorwarnung ändern oder
    verschwinden. Ein direkter Aufruf ist nicht vorgesehen und kann
    Zustand durcheinanderbringen – `'$wot_open'/2` etwa leitet die
    Ausgabe um und stellt sie nicht zurück (das macht erst
    `with_output_to/2` als Ganzes).
  * Aufrufbar sind sie trotzdem von überall (wie in SWI); neu definieren
    kann man die vorhandenen nicht (`permission_error`).
    `current_predicate/1` zeigt sie nicht, `predicate_property/2` schon.
  * Eigene Prädikate sollte man nicht so benennen: ein späteres
    Systemprädikat gleichen Namens machte das Programm unladbar
    (`permission_error`). Das Laden warnt darum bei jedem
    Benutzerprädikat mit `$` am Anfang (einmal je Prädikat; nicht für die
    Bibliotheken des Systems); abschalten mit `style_check(-dollar)`.

### Module und Sichtbarkeit

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
    `current_module/1` (Bibliotheken in Elixir erst, wenn aus ihnen
    importiert wurde, wie in SWI ohne Autoload), `strip_module/3`,
    `predicate_property/2` (wie
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
    | `library(iso_ext)` (wie Scryer) | `forall/2`, `succ/2`, `setup_call_cleanup/3`, `call_nth/2`, `countall/2`, `call_with_inference_limit/3`, `copy_term_nat/2`, `copy_term/3` (Liste, wie Scryer); `call_with_memory_limit/2` (siehe Ressourcen begrenzen), `cached_is(X, E)` (rechnet wie `X is E`, wertet aber einen geteilten Teilausdruck nur einmal aus – ein Term wie `X+X` über 60 Stufen kostet 60 Schritte statt 2^60; Fehler wie bei `is/2`; Teile mit `random`, `random_float`, `cputime`, `realtime` werden nicht gemerkt und liefern je Vorkommen einen neuen Wert); dazu aus Logtalks „Prolog commons“ `atomic_concat/3` (`atomic_concat(a, 42, a42)`) und `evaluable_property/2` (`built_in`, `static`, `template(abs(number), number)`, `template(pi, float)`; Typen `integer`, `float`, `number`); weitergegeben: `call_cleanup/2`, `call_residue_vars/2`, `bb_get/2`, `bb_put/2`, `bb_b_put/2` |
    | `library(between)` | `between/3`, `repeat/1` (dazu `numlist/2,3` usw.) |
    | `library(fastrw)` | `fast_read/1,2`, `fast_write/1,2` |
    | `library(swi)` | vorläufig der Rest aus SWI: `ignore/1`, `not/1`, `*->/2`, `plus/3`, `atomic_list_concat/2,3`, `atom_number/2`, `term_to_atom/2`, `read_term_from_atom/3`, `=@=/2`, `\=@=/2`, `term_attvars/2`, `findnsols/4,5`, `call_with_depth_limit/3`, `exists_file/1`, `exists_directory/1`, `delete_file/1`, `fast_term_serialized/2`, `time/1`, `statistics/0`, `style_check/1`, `expand_goal/2`, `dcg_translate_rule/2`, `strip_module/3`, `upcase_atom/2`, `downcase_atom/2` (Zeichen für Zeichen wie SWI: `upcase_atom('Grüße', 'GRÜßE')`); Ausgabe: `writeln/1,2`, `tab/1,2` (Ausdruck), `with_output_to/2` (Senken `atom(A)`, `chars(Cs)`, `chars(Cs, Rest)`, `codes(Cs)`, `codes(Cs, Rest)`; das Ziel wie `once/1`); Listen: `select/4`, `selectchk/3,4`, `flatten/2`, `predsort/3`, `sort/4` (Schlüssel 0 oder Argumentnummer, `@<`/`@>` entfernen gleiche Schlüssel, `@=<`/`@>=` nicht; stabil); `code_type/2` mit SWIs Typen (`alpha`, `csym`, `csymf`, `digit(W)`, `xdigit(W)`, `to_lower(L)`, `upper(L)`, `punct`, …; `char_type/2` bleibt Scryers aus `library(charsio)`); globale Variablen `nb_setval/2`, `nb_getval/2`, `b_setval/2`, `b_getval/2`, `nb_current/2` (eigene Schlüssel neben `bb_put/2`; unbekannt: `existence_error(variable, K)`); `term_variables/3`, `string/1` (scheitert immer: keine Strings), `garbage_collect/0`, `get_time/1` – und gibt alle obigen weiter. `format/3` nimmt (eingebaut, ohne Import) dieselben Senken wie `with_output_to/2`: `format(atom(A), "~w", [x])` |

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
    importiert wird aus `apply`, beide zusammen ergeben keinen Konflikt),
    wie bei Scryer auch `foldl/4..6`.
  * Rümpfe laufen im Modul, in dem das Prädikat definiert ist;
    Meta-Argumente (`0..9`, `^`, `//`, `:`) werden beim Aufruf mit dem
    Kontextmodul qualifiziert. Prädikate von `system` sind geschützt.
  * Dateien werden schrittweise gelesen: Operatoren aus der Exportliste
    eines mit `use_module` geladenen Moduls gelten schon für den Rest der
    ladenden Datei. Operatoren sind global (nicht modul-lokal). Lädt nur
    eine Bibliothek des Systems ein solches Modul (clpz lädt
    `library(debug)` mit `*` und `$` als Präfixoperatoren), gelten dessen
    Operatoren nur beim Lesen seiner eigenen Datei und werden danach
    zurückgenommen, auch frühere Definitionen derselben Operatoren – wie in
    Scryer ist `* a` nach `use_module(library(clpz))` kein Term. Ein
    eigenes `use_module(library(debug))` setzt sie.
  * Gleichnamige Prädikate zweier Bibliotheken: der erste Import gilt,
    mit Warnung. (`library(lists)` hat deshalb kein `chain/2` mehr: das
    aus clpz, `chain(Relation, Zs)`, hat die umgekehrte Argumentfolge.)
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
    aus einem Term macht, dürfen sich abwechseln; nicht für die
    Bibliotheken des Systems, wie Scryer) und Prädikate, deren Name mit
    `$` beginnt (siehe unten, „Interne Prädikate“). Abschalten mit
    `style_check(-singleton)`, `style_check(-(discontiguous))`,
    `style_check(-dollar)` – die
    Klammern braucht ISO, weil `discontiguous` ein Präfixoperator ist;
    `style_check(?(X))` fragt ab. Fehler in Direktiven nennen ebenfalls die
    Zeile.
  * `:- include(F)`: die Terme von F stehen an dieser Stelle (relativ zur
    einschließenden Datei, `.pl` darf fehlen).
  * `:- if(C)` … `:- elif(C)` … `:- else` … `:- endif` (verschachtelbar,
    wie SWI/SICStus/GNU): C läuft als Anfrage und sieht das bisher
    Geladene, ein Fehler gilt als falsch. In inaktiven Zweigen wird alles
    übersprungen, auch Direktiven und Syntaxfehler.

### Was wohin importiert wird: Flag `verbose_load`

Werte wie SWI; Vorgabe hier `full` (SWI: `silent`), abschalten mit
`set_prolog_flag(verbose_load, silent)`; `mix prolog … -q` setzt es auf
`silent` (das Programm kann es wieder setzen). Mit `normal` meldet das Laden auf
stderr jede geladene Datei bzw. Bibliothek und je Import, wie viele
Prädikate in welches Modul kamen. Mit `full` stehen die Prädikate und
Operatoren einzeln dabei. Was eine Bibliothek beim Laden selbst importiert,
steht eingerückt darunter:

```
?- set_prolog_flag(verbose_load, normal), use_module(library(dcgs)).
% lade library(dcgs) ...
%   dcgs ← lists: 1 Prädikat
% library(dcgs) geladen (Modul dcgs, 9 ms)
% user ← dcgs: 8 Prädikate
?- set_prolog_flag(verbose_load, full), use_module(library(pairs)).
% lade library(pairs) ...
% library(pairs) geladen (Modul pairs, 0 ms)
% user ← pairs: 6 Prädikate
%     group_pairs_by_key/2, map_list_to_pairs/3, pairs_keys/2,
%     pairs_keys_values/3, pairs_values/2, transpose_pairs/2
```

Bibliotheken in Elixir (`lists`, `assoc`, ...) werden nicht geladen, nur
importiert. Ist alles schon da: `user ← lists: nichts Neues` (nur bei
`full`).

## Expansion: `term_expansion/2`, `goal_expansion/2`

Wie SWI/SICStus: Hooks im Quellmodul oder in `user`, ab der Klausel nach
ihrer Definition wirksam. Was ein `goal_expansion`-Hook aufruft, muss
schon definiert sein, und alles, was in der Datei vor der Klausel steht,
ist es (vorher kompiliert; nur das Prädikat der Klausel selbst nicht, sonst
würde es mit jeder Klausel neu übersetzt) – clpz übersetzt so seine
eigenen Klauseln mit Hilfsprädikaten weiter oben.

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
  * Bibliotheken: Ein Modul, das die Direktive `:- '$expansion_hooks'.`
    enthält, meldet seine eigenen `term_expansion/2` und `goal_expansion/2`
    an; `:- '$expansion_hooks'(goal_expansion, P).` nur sein `P/2` als
    Hook dieser Art (die eigenen `term_expansion/2`/`goal_expansion/2`
    gelten dann weiter nur für das Modul selbst). Angemeldete Hooks gelten
    für alles, was danach geladen wird, nach Quellmodul und `user` (in der
    Reihenfolge der Anmeldung). So stören sich Bibliotheken und Programm
    nicht: Definieren zwei Dateien `user:goal_expansion/2`, ersetzt die
    zweite die erste – früher nahm so ein eigenes `goal_expansion/2` im
    Programm `library(clpz)` seine Übersetzung von `#=` & Co. weg.
  * `prolog_load_context(?Key, ?Value)` beim Laden (in Hooks und
    Direktiven): `module`, `dialect` (`prolog_ex`), `source` (die geladene
    Datei), `file` (bei `include/1` die eingebundene), `directory`;
    außerhalb des Ladens scheitert es.
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
negativen Zahlen scheitert (ISO sieht keinen Fehler vor). Arithmetik
streng nach ISO: `round(X)` ist `floor(X + 1/2)`, Halbwerte also immer
nach oben (`round(-3.5)` ist -3, nicht -4 wie in C, SWI und Scryer;
exakt gerechnet, nicht über eine Gleitkommaaddition), und `round/1`,
`floor/1`, `ceiling/1`, `truncate/1`, `float_integer_part/1`,
`float_fractional_part/1` nehmen nur Floats – eine Ganzzahl ist
`type_error(float, X)` (SWI und Scryer nehmen sie; unsere Fassung von
Scryers `library(format)` wandelt bei `~Nf` deshalb vorher in einen
Float). `max_arity` ist 255 wie in SICStus und Scryer: größere Stelligkeiten bei
`functor/3`, `=../2`, `abolish/1`, `read_term/2,3` und beim Aufruf (`call/N`) sind
`representation_error(max_arity)` (beim Laden einer Datei ein
Syntaxfehler). Gesamt: 4 127 bestanden, 80 fehlgeschlagen,
205 übersprungen.
Wo Logtalk Neumerkels ISO-Entwürfen (siehe unten) widerspricht, folgen wir
den Entwürfen und Scryer: `length/2` scheitert, wenn das erste Argument
weder Liste noch Teilliste ist (Logtalk: `type_error(list, L)`), und die
Werte von `variables/1`, `variable_names/1`, `singletons/1` werden bei
`read_term/2,3` erst nach dem Lesen unifiziert (Logtalk:
`domain_error(read_option, O)`, `lgt_read_term_3_32` bis `_37`). Die
übrigen Fehlschläge betreffen Logtalk-, ECLiPSe- und „commons“-Erweiterungen
(Klauselreferenzen – `assertz/2`, `clause/3`, `erase/1`, `instance/2` –
bewusst nicht: sie sind nicht portabel, und eindeutige Schlüsselargumente
mit `retract/1` leisten dasselbe; die logical-update-Tests über `lgt:`), Unicode-Optionen von `open/4`,
Escapes außerhalb von ISO (`0'\e`, `0'\d`, `0'\s`, `0''` – bewusst
Syntaxfehler),
`4/2` ist `2`
(siehe Arithmetik). Wie Logtalk und
Scryer: `call_nth(G, 0)` scheitert, negativ ist
`domain_error(not_less_than_zero, N)`; `setof/3` scheitert, wenn die
Ergebnisvariable über eine freie Variable gebunden wird; `keysort/2` prüft
die Elemente des Ergebnisses (`type_error(pair, E)`), `findall/4` den Rest;
`atom_concat(A, A, Z)` ist deterministisch; bei `open/4` gilt von
wiederholten Optionen die letzte; `set_stream_position/2` auch auf
Schreibströmen; Flag `version_data` (`prolog_ex(0,1,0,[])`, wie SWI).

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
    (ISO 6.4.7), `\0\` ist im Atom erlaubt, `1.0e400` ist kein `inf`:
    `read_term/2,3` und `number_chars/2` melden
    `representation_error(max_float)` (Neumerkel stc #73), beim Laden einer
    Datei ist es ein Syntaxfehler.
  * Nach einem Syntaxfehler geht es hinter dem nächsten Endepunkt weiter
    (wie gprolog, aber Kommentare zählen als Ganzes).

Neumerkels Konformitätstabelle zur ISO-Syntax (in der Fassung von Scryer
Prolog, 266 Fälle zum Lesen und Schreiben): 260 bestehen.
`mix run conformance/neumerkel/run.exs /pfad/scryer-prolog` (Checkout
von github.com/mthom/scryer-prolog). Die übrigen sieben sind Absicht oder
von ISO offen gelassen: Backquotes lesen sich als Atom (#113; ISO: kein
Term), `|` ist wie bei gprolog und SWI vordefiniert (#285), dazu Abstände
und Variablennamen in der Ausgabe (#142, #151, #226, #227). Geschrieben
wird nach dem Entwurf zu 7.10.5 (WDCor.3): nach dem Präfix `-` stehen
Klammern um eine Zahl und um einen Term in Operatorform (`- (1)`,
`- (a^2)`).

Weitere Tabellen Neumerkels stehen als tabellengetriebene Tests in
`test/neumerkel_*_test.exs` (je Zeile Anfrage und erwartete Antwort; wo
die Tabelle mehrere Antworten zulässt, genügt eine):

  * [Prologue](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/prologue)
    (`member/2`, `append/3`, `length/2`, `between/3`, `select/3`, `succ/2`,
    `maplist/2..`, `nth0/3,4`, `nth1/3,4`, `foldl/4`): `succ/2` prüft
    beide Argumente (`succ(1, 1+1)` ist `type_error(integer, 1+1)`, negativ
    `domain_error(not_less_than_zero, N)`), `nth0(-1, Es, E)` ist ein
    `domain_error`, `nth1(0, Es, E)` scheitert, `length([a|b], L)`
    scheitert. Nicht aufgenommen: `length(L, L)` (läuft endlos) und die
    Zeilen mit `max_integer` (unbeschränkte Ganzzahlen).
  * [phrase](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/phrase):
    ungebundener Rumpf und Teillisten (`phrase([a|L], K)`) geben
    `instantiation_error`; der übersetzte Rumpf wird vor der Ausführung
    ganz geprüft (`phrase(([a],{1}), [])` ist `type_error(callable, _)`);
    `\+` übersetzt erst bei der Ausführung, wenn der Rumpf sich nicht
    übersetzen lässt; `call([], A)` ruft `'[]'/1`; `-->/2` ist reserviert
    (`asserta((a-->b))`: `permission_error(modify, static_procedure, (-->)/2)`).
  * [variable_names](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/variable_names)
    (`write_term/2`, `read_term/2`, Optionen von `open/4`): bei mehrfacher
    `variable_names/1`-Option gilt die letzte; `read_term/2,3` liest erst
    und unifiziert dann (`variable_names(42)` scheitert, ein Syntaxfehler
    geht vor).
  * [length](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/length)
    (`length/2`, `atom_length/2`): eine zyklische Liste scheitert
    (`L = [a|L], length(L, 7)`); bei offener Liste und offener Länge wird
    Zelle für Zelle verlängert, so dass `freeze(L, L = []), length(L, L)`
    scheitert statt endlos zu suchen. Nicht aufgenommen: die Fälle, die
    endlos laufen dürfen (#21, #22, #30), und #31 (`freeze(L, L=[_|L])` mit
    Länge 2^64: hier `resource_error(memory)`, die Tabelle erwartet `false`).
  * [cleanup](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/cleanup)
    (`setup_call_cleanup/3`, alle Beispiele aus 7.8.11.4; wo der Entwurf
    mehrere Ausgänge zulässt, läuft die Aufräumung, sobald das Ziel
    deterministisch fertig ist).
  * [number_chars](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/number_chars)
    vollständig, auch #46 (zyklische Liste: `type_error(list, L)`).
  * Kleinere Seiten in `test/neumerkel_misc_test.exs`:
    [digit_separators](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/digit_separators),
    [noname_operators](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/noname_operators)
    (`'[]'` und `'{}'` sind keine Operatoren:
    `permission_error(create, operator, [])`),
    [syntax_extension](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/syntax_extension)
    (`|` als `op(1105, xfy, '|')` wie SWI/YAP; `f(a|b)`, `[a|b|c]`, `f(|)`
    sind Syntaxfehler, `(fail|true)` ist `existence_error`, da `'|'/2` kein
    Steuerkonstrukt ist),
    [error_k](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/error_k)
    (`open/3,4` mit gebundenem Stream: `uninstantiation_error(S)`) und
    [draft-7.10.5](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/draft-7.10.5)
    (Schreiben).
  * Die Korrigenda-Seiten in `test/neumerkel_corrigenda_test.exs`:
    [dtc2](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/dtc2)
    (Cor.2: `subsumes_term/2`, `compare/3`, `sort/2`, `keysort/2`,
    `term_variables/2`, `retractall/1`, `call/N`, Arithmetik, `'.'`
    schreiben),
    [WDCor3](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/WDCor3)
    mit [WDR3](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/WDR3)
    (Fehler bei Optionen, `max_arity`, `-1 ^ -2`),
    [stc](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/stc)
    (negative Zahlen, `(:-B)`, `current_predicate/1`, `abolish/1`,
    `max_float`/`max_arity` beim Lesen als `representation_error`, ein
    zyklisches `keysort/2` gibt `type_error(list, L)` mit der zyklischen
    Liste), [built-in_predicates](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/built-in_predicates)
    (`?=/2`) und eine Auswahl aus
    [evaluable_functors](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/evaluable_functors)
    (`nexttoward/2` und `cbrt/1` fehlen); ungültiges UTF-8 gibt
    `representation_error(character)` (stc #76). Bewusst anders:
    `close('$stream'(S))` ist `domain_error(stream_or_alias, _)` (stc #72
    erwägt `instantiation_error`).

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

### Vergleich mit Scryer Prolog

`bench/compare.pl` läuft unverändert in PrologEx, Scryer und SWI (jeder
Fall fünfmal, kleinste CPU-Zeit aus `statistics(runtime, _)`):

```sh
MIX_ENV=prod mix prolog bench/compare.pl -g main -q
scryer-prolog -g main -g halt bench/compare.pl
swipl -g main -t halt bench/compare.pl
```

Stand 1. November 2026 (OTP 28, Scryer `master` b7066b4 als Release-Build,
dieselbe Maschine; Zeiten in ms):

| Fall | PrologEx | Scryer | Faktor |
|---|---|---|---|
| nrev (30, 2000-mal) | 1248 | 142 | 8,8 |
| loop (1 Mio., `is`) | 1525 | 121 | 12,6 |
| tak (18, 12, 6) | 181 | 10 | ≈ 18 |
| queens (8, alle) | 64 | 7 | ≈ 9 |
| deriv (20 000) | 714 | 115 | 6,2 |
| facts (Backtracking) | 722 | 79 | 9,1 |
| foldl/4 (300 000) | 720 | 172 | 4,2 |
| dieselbe Summe von Hand | 623 | 138 | 4,5 |
| findall + sort (200 000) | 588 | 266 | 2,2 |
| clpb (kleine Formeln) | 80 | 265 | 0,3 |

Im geometrischen Mittel ist PrologEx rund 5-mal langsamer als Scryer
(clpb: Stand mit `sat/1` in Elixir, siehe dort);
reine Maschinenarbeit (Schleifen, Arithmetik, Klauselwahl) 9–18-mal,
wo eingebaute Prädikate einen großen Teil tragen (findall, sort, Listen)
nur 2–4-mal. tak und queens sind bei Scryer so kurz, dass ihre Faktoren
grob sind.

Mit `set_prolog_flag(occurs_check, error)` (Messung vom 6. 11. 2026,
geometrische Mittel, Faktor gegenüber `false`):

| | PrologEx | Scryer |
|---|---|---|
| Maschine (8 Programme) | 1,09 | 1,12 |
| clpz (13 Programme) | 1,26 | 2,17 |
| clpz, groß (100 Damen, holes(60), sieve(8000)) | 1,97 | 3,73 |

Am teuersten ist 100 Damen mit `ff`: 709 → 3 157 ms (Scryer
705 → 6 880 ms); holes(60) kostet nichts extra.

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

`plus/3`, `functor/3`, `arg/3`, `=../2`, `copy_term/2`, `once/1`,
`ignore/1` und `current_prolog_flag/2` (mit gebundenem Namen) führt die
Maschine selbst aus, statt
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

`copy_term/2` bindet eine gewöhnliche ungebundene Zielvariable direkt
(die Kopie enthält nur frische Variablen, ein Occurs-Check ist nie
nötig; an eine attributierte unifiziert es wie bisher). Frische
Variablen der Kopie heißen `{:var, n}` statt `"_B<n>"`: eine Binary je
Variable kostete etwa ein Viertel der Kopie. `copy_term/2` ground ≈ 35 %,
mit Variablen ≈ 43 % schneller, `findall/3` über Terme mit Variablen
≈ 14 %.

Kennungen der Variablen kommen aus einem gemeinsamen Zähler der VM
(`PrologEx.Vars`, `:atomics`): der Reader gibt jeder Variablen eines
Terms `{Name, n}`, `copy_term/2`, `read/1`, attributierte Variablen und
die Bibliotheken nehmen je eine Zahl, die Maschine nimmt sich Blöcke von
4096 und zählt darin lokal weiter (eine Prüfung je Klauselversuch, ob
der Block reicht; in Reduktionen nicht messbar). Vorher begann jede
Anfrage bei 0, und Kennungen aus `read/1`, Kopien, Bibliotheken und
Anfrage hatten je eigene Formen (`_G12`, `_C7`, `_B34`, `_0`, `_B`);
Terme aus `term_expansion/2` mussten deshalb umbenannt werden. Jetzt
kann eine Kennung nie zweimal vorkommen, auch nicht über Anfragen,
Unter-Maschinen (`findall/3`, `portray/1`) und Prozesse hinweg.

Allgemein werden Ziele aus Daten jetzt wie bei `call/1` zum Rumpf (ISO
7.6.2) – auch `M:Rumpf` (`call/1` stieg bisher nicht hinein) und bei
`\+`, `findall/3`, `findnsols/4,5`, `countall/2`, `catch/3`, `forall/2`,
`call_nth/2`, den Grenzen und `time/1` (sie führten das Ziel bisher roh
aus): beim Aufruf ungebundene Variablen innen werden `call(V)` (Cut darin
lokal, `findall(x, ((G = !, G, fail) ; true), L)` gibt `L = [x]` wie
SWI), gebundene werden eingesetzt, nicht Aufrufbares gibt
`type_error(callable, _)` vor jeder Ausführung. Ohne eigenen
`call`-Schritt umgewandelt: keine messbaren Kosten.

`call/1..8` mit einem Atom oder einer Struktur ohne Steuer-Funktor
(`,` `;` `->` `*->` `:`) – auch als `M:G` mit Atom `M`, so wie
Meta-Argumente ankommen – startet das Ziel direkt: keine
Rumpfumwandlung (sie ließe es ohnehin unverändert), kein geschützter
Abschluss, kein zweites Dereferenzieren. Steuerkonstrukte, verschachteltes
`M:M2:G`, Variablen und Fehler gehen den allgemeinen Weg wie bisher.
Der Mehraufwand von `call/N` gegenüber dem direkten Ziel sank um rund
45 % (gemessen in BEAM-Reduktionen; die Wanduhr ist dafür zu
verrauscht), `maplist/3` und `foldl/4` brauchen rund 10 % weniger
Arbeit, `call((A, B))` unverändert, Inferenzen wie bisher. Behoben
nebenbei: `G = member(X), call(lists:G, [a])` gab `instantiation_error`
(das innere Ziel von `M:G` wurde bei `call/N` mit Zusatzargumenten nicht
dereferenziert).

`foldl/4..6` (aus `library(apply)`, auch über `library(lists)`) führt die
Maschine selbst aus: je Element `call(G, X…, V0, V1)` über den Schnellweg
von `call/N` und dahinter der nächste Schritt – ohne Klauselwahl,
Kopfunifikation und Rumpfaufbau für die Schleife selbst, je Stelligkeit
ein eigener Fall, die Ziele ohne Ground-Prüfung gebaut (sie enthalten die
frische Variable V1). Offene, ungleich lange oder fehlende Listen gehen
den Weg über die Klauseln (Aufzählen und Scheitern wie bisher); Inferenzen
wie bisher. 200 000 Elemente (abwechselnd gemessen, je Minimum):
`foldl(add, L, 0, S)` 630 → 421 ms, mit leerem Schritt 534 → 311 ms,
`foldl/5` 670 → 431 ms – rund ein Drittel weniger; die Schleife von Hand
braucht 365 ms, der Rahmen von `foldl` kostet also kaum noch etwas.

`==/2` und `\==/2` führt die Maschine selbst aus (ISO, geschützt; sie
werfen nie) über einen eigenen Gleichheitstest statt `compare/3`: oben
atomar einmal `===`, zusammengesetzt erst die physische Identität
(geteilte Terme in O(1)), sonst strukturell (geteilte Teilterme mit
Memo) mit
billigen Blättern, der Listenrest per Tail Call. Innen bewusst kein
`===`: auf jeder Ebene wiederholt, wäre es bei spät verschiedenen Termen
quadratisch. Was sich nicht billig entscheiden lässt (Floats wie
`-0.0`, `'.'(a, [])` gegen `[a]`, verschiedene Klassen oder Funktoren),
entscheidet weiter `compare/3`, die Ergebnisse bleiben also dieselben.
Einfache Fälle (`X == X`, `a == a`, `a \== b`) kosten rund 50–60 %
weniger, `f(a,b,c) == f(a,b,c)` 80 %; zwei getrennt gebaute gleiche
Listen mit 100 000 Zahlen ≈ 12 ms → 0,3 ms, mit gebundenen Variablen
≈ 40 → 1 ms, spät verschiedene Listen ≈ 3- bzw. 1,4-mal schneller,
tiefe Terme 25–40 %. Nirgends langsamer; Inferenzen wie bisher.

`compare/3` und `@<`, `@>`, `@=<`, `@>=` führt die Maschine ebenfalls
selbst aus. `compare/3` bindet ein ungebundenes `Order` direkt und
vergleicht ein schon gebundenes nur noch (`compare(<, X, Y)`);
attributiertes `Order` und Fehler gehen über das Builtin. Die
Standardordnung selbst (`Order.compare/3`) entscheidet direkt auf dem
Paar statt über Klassennummern, Listen ohne Umweg über `'.'/2`
(vorher zwei Hilfstupel je Zelle), Markierungen ohne `unmark_top`. Ein
`===` vorweg wie bei `==/2` bringt hier nichts: Ungleiche kleine Terme
sind der Normalfall, und dort kostete es rund 20 %. Einfache Aufrufe
kosten rund die Hälfte (`compare(O, a, b)` 106 → 52 Reduktionen,
`a @< b` 62 → 26), kleine Listen 3,5-mal, lange spät verschiedene Listen
3-mal schneller, kleine Strukturen ≈ 20 %. Nirgends langsamer;
geprüft gegen die Sortierschlüssel als zweite, unabhängige Umsetzung der
Standardordnung (20 000 zufällige Termpaare).

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
mix test                  # Tests (ohne die langsamen, @tag :slow)
mix test --include slow   # mit den langsamen (Minuten)
mix run bench/bench.exs   # Speicher- und Laufzeitmessung
```
