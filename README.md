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
mix compile                          # Elixir und den Reader (gplc) übersetzen;
                                     # GPLC=/pfad/zu/gplc falls nicht im PATH
mix prolog                           # interaktiver Toplevel
mix prolog examples/demo.pl          # Datei laden, dann Toplevel
mix prolog examples/demo.pl -g main -q   # laden, main ausführen, Ende
cat prog.pl | mix prolog - -g main   # Programm von stdin
```

Bauen: `mix compile` übersetzt neben dem Elixir-Code auch den gprolog-Reader
(`priv/gprolog/reader.pl`), sobald die Quelle neuer ist als das Programm –
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

Unterstützt: Klauseln, DCG (`-->`, `phrase/2,3`), Direktiven (`op/3`,
`dynamic/1`, `initialization/1`, beliebige Ziele), Reconsult (erneutes
Laden ersetzt Prädikate), `,` `;` `->` `\\+` `!` `call/N` `time/1`,
`=` `\\=` `==` `\\==`, Standardordnung (`@<` `@>` `@=<` `@>=` `compare/3`,
`sort/2` `msort/2` `keysort/2`), `term_variables/2`, `subsumes_term/2`, `is` und Vergleiche (Ganzzahlen beliebiger Größe,
Floats), Typprüfungen, `functor/3`, `=../2`, `append/3`, `length/2`, `member/2`, `between/3`, `select/3`, `permutation/2`, `memberchk/2`, `last/2`, `reverse/2`,
`proper_length/2`, `sum_list/2`, `max_list/2`, `min_list/2`, `max_member/2`,
`min_member/2`, `delete/3`, `list_to_set/2`, `nextto/3`, `subtract/3`,
`intersection/3`, `union/3`, `include/3`, `exclude/3`, `partition/4`, `foldl/4..6`,
`same_length/2`, `nth0/3,4`, `nth1/3,4`, `maplist/2..8`, `succ/2`, `call_nth/2`,
`findall/3,4`, `findnsols/4,5`, `countall/2`, `bagof/3`, `setof/3` (ISO;
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
Leerraum folgen) und Ganzzahl-Literale beliebiger Größe; beides schreibt
`PrologEx.NumberSyntax` vor dem gprolog-Reader um.

Ausnahmen: `catch/3`, `throw/1`; alle Fehler der Builtins sind ISO-Terme
`error(Formal, Kontext)` (`type_error`, `instantiation_error`,
`existence_error`, `permission_error`, `domain_error`, `evaluation_error`, …)
und fangbar. Nicht Gefangenes meldet der Toplevel als `Fehler: …`.

## Ausgabe: Terme mit Operatoren

`write/1`, `print/1`, `writeq/1`, `write_canonical/1`, `write_term/2` und die
Antworten im Toplevel schreiben mit Operatoren, nach ISO und im Stil von
gprolog (mit dem wir auch lesen); jede `writeq`-Ausgabe liest sich wieder als
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
    nicht; `write_canonical` schreibt ohne Operatoren (`+(1,2)`).
  * `'$VAR'(N)` erscheint als `A`, `B`, …, `Z`, `A1`, … (außer bei
    `write_canonical`).
  * Zeichenlisten bei `double_quotes=chars` wie Scryer als `"..."`
    (`number_chars(123, X)` → `X = "123"`).
  * Antworten und `listing` setzen Leerzeichen nach Kommas (`f(a, b)`,
    `[a, b|T]`) wie SWI; `writeq` schreibt kompakt (`f(a,b)`) wie ISO.
  * `write_term/2`: `quoted/1`, `ignore_ops/1`, `numbervars/1`,
    `variable_names/1` (ISO), `max_depth/1`, `spacing/1`, `priority/1` (SWI).
  * Die Operatortabelle für die Ausgabe spiegelt die des Readers: `op/3`,
    Operatoren aus Bibliotheken und aus `module/2`-Exportlisten.
  * `listing/1` wie `portray_clause`, mit eingerücktem Wenn-dann-sonst.

Abweichung von gprolog: Nach einem alphanumerischen Präfix-Operator steht
immer ein Leerzeichen (`dynamic -a`, gprolog: `dynamic-a`), damit auch andere
Systeme es als Präfix lesen.

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

## Coroutining

`freeze/2`, `frozen/2`, `dif/2`, `when/2` (Bedingungen `nonvar/1`,
`ground/1`, `?=/2`, `,`, `;`), dazu `?=/2` und `ground/1`. Verzögerte Ziele
laufen, sobald eine ihrer Variablen gebunden wird – vor dem nächsten Ziel,
auch nach Bindungen im Klauselkopf oder in Builtins. Offene Bedingungen
zeigt der Toplevel als Restziele:

```
?- dif(f(X, Y), f(1, 2)), X = 1.
X = 1, dif(f(1, Y), f(1, 2)).
```

`dif/2` merkt sich nur die *Front*: die Paare des Unifikators, die noch
offen sind. Wird eine ihrer Variablen gebunden, wird die Front gemeinsam
neu unifiziert (erfüllt, gescheitert oder kleinere Front); das Restziel
schrumpft entsprechend (`dif(f(X,Y,Z), f(1,2,3)), X = 1` →
`dif(f(Y, Z), f(2, 3))`).

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
    `library(apply)`, `library(random)`, `library(atts)`,
    `library(blackboard)`, `library(mutables)`, `library(lambda)`,
    `library(lambda_pl)`, `library(si)`), `ensure_loaded/1`, `consult/1`, `M:Ziel`,
    `M:Kopf :- Rumpf`, `assert(M:Klausel)`, `meta_predicate/1`,
    `current_module/1`, `strip_module/3`, `predicate_property/2` (wie
    SICStus, dazu `number_of_clauses/1`); `clause/2`, `retract/1`,
    `dynamic/1`, `listing/1`, `current_predicate/1` mit `M:`.
  * Auflösung eines Aufrufs in Modul `m` wie SICStus: in `m` definiert →
    nach `m` importiert → `system`. Kein Rückgriff auf `user` (sonst
    `user:foo` schreiben) und kein Autoload:
    Bibliotheksprädikate wie `append/3`, `member/2`, `maplist/2..8` gibt es
    nur nach `:- use_module(library(lists)).` bzw. `library(apply)` – auch
    im Toplevel. Eigene Definitionen gehen Importen vor.
  * Rümpfe laufen im Modul, in dem das Prädikat definiert ist;
    Meta-Argumente (`0..9`, `^`, `//`, `:`) werden beim Aufruf mit dem
    Kontextmodul qualifiziert. Prädikate von `system` sind geschützt.
  * Dateien werden schrittweise gelesen: Operatoren aus der Exportliste
    eines mit `use_module` geladenen Moduls gelten schon für den Rest der
    ladenden Datei. Operatoren sind global (nicht modul-lokal).
  * Relative Pfade in einer Datei gelten ab deren Ordner.

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

## Entwicklung

```sh
mix test                  # Tests (Integrationstests mit gprolog nur,
                          # wenn der Reader übersetzt ist)
mix run bench/bench.exs   # Speicher- und Laufzeitmessung
```
