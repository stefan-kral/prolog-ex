# Demos: library(concurrent) und library(clpz_concurrent)

```sh
examples/parallel/run.sh                      # alle vier Demos, Größe klein
examples/parallel/run.sh mittel eine alle     # Größe mittel, nur zwei Demos
examples/parallel/run.sh -k 4 gross           # mit höchstens 4 Kernen
examples/parallel/run.sh -t "1 2 4 8 max" > tabellen.md   # Tabellen (Markdown)
```

Mit `-t` läuft jede Demo einmal je Kernzahl (`max`: ohne Grenze), und
`run.sh` setzt daraus je Demo eine Markdown-Tabelle zusammen – die
Fortschrittszeilen gehen auf stderr:

| Aufgabe | nacheinander | parallel, 1 Kern | parallel, 2 Kerne |
|---|---:|---:|---:|
| maplist fib(18), 16 mal | 0,36 s | 0,30 s (1,2×) | 0,27 s (1,4×) |
| Primzahlen bis 100000, Blöcke zu 10000 | 2,93 s | 2,87 s (1,0×) | 1,57 s (1,9×) |

„nacheinander“ ist die schnellste Messung aus allen Läufen, der Faktor
bezieht sich darauf. Mehr Kerne als der Rechner hat lassen sich angeben
(`+S` startet dann einfach mehr Scheduler), bringen aber nichts.

Braucht einen Build (`mix compile` im Projekt). Jede Zeile zeigt die Zeit
nacheinander, die parallele Zeit, den Faktor und das Ergebnis; die
parallele Fassung muss genau dasselbe liefern (sonst `VERSCHIEDEN!`).

| Datei | Demo | zeigt |
|---|---|---|
| `concurrent_grundlagen.pl` | `grundlagen` | `concurrent_maplist/3`, `first_solution/3`, `concurrent_and/2`, `concurrent_child/1`, die Sperre für Seiteneffekte |
| `clpz_eine.pl` | `eine` | `concurrent_labeling/3`: dieselbe erste Lösung wie `once(labeling/2)`, Work Stealing in der Reihenfolge der Suche; auch, wo es nichts bringt |
| `clpz_alle.pl` | `alle` | `concurrent_labelings/4`: alle Lösungen in derselben Reihenfolge; feste Teile gegen Work Stealing (`parts(K)`) |
| `clpz_optimieren.pl` | `optimieren` | `min`/`max`: Branch and Bound mit gemeinsamer Schranke (Rucksack, Damen, Golomb-Lineal) |
| `hilfen.pl` | – | `vergleich/4` und die gemeinsamen Modelle (mit `include/1`) |

Einzeln, mit eigenen Zielen:

```sh
cd examples/parallel
../../start_ex clpz_alle.pl -g 'main(mittel)' -g halt
../../start_ex clpz_eine.pl          # dann z. B. ?- vergleich(x, eine, damen_ohne_ff(19), []).
```

**Kerne begrenzen.** Die BEAM startet so viele Scheduler wie Kerne; `+S
N:N` begrenzt sie (`run.sh -k N` setzt das). Das Flag `cpu_count` und damit
die Vorgabe für die Zahl der Arbeiter folgen:

```sh
ERL_FLAGS="+S 4:4" ./start_ex           # start_ex behält ERL_FLAGS bei
ERL_FLAGS="+S 4:4" mix prolog
ERL_FLAGS="+SP 50:50" ./start_ex        # die Hälfte der Kerne
```

Je Aufruf geht es auch ohne Neustart: `parts(N)` bei `concurrent_labeling/3`
(Arbeiter), `threads(N)` bei `concurrent_forall/3` und `concurrent_and/3`,
`concurrent/3` mit N.

Was zu erwarten ist (2 Kerne gemessen): eine Lösung bringt je nach Modell
zwischen nichts und fast das Doppelte – nur die Arbeit links der Lösung
lässt sich teilen, und die eigene Suchschleife kostet 7–40 % gegenüber
`labeling/2` (am meisten bei billiger Propagation wie beim Taubenschlag);
alle Lösungen und das Optimieren gewinnen verlässlich, das Optimieren oft
mehr als die Zahl der Kerne (die gemeinsame Schranke schneidet früher ab).
Kleine Aufgaben bleiben nacheinander (`serial(S)`, Vorgabe 0,1 s).

Vorsicht mit offenen Choice Points beim Messen: Mit `fib(0, 0). fib(1, 1).
fib(N, F) :- N > 1, ...` passen auf `fib(1, _)` und `fib(0, _)` je zwei
Klauseln, jeder solche Aufruf lässt einen Choice Point offen – 16 ×
`fib(22)` nacheinander fast eine Million, gut 850 MB, die bis zum Ende der
Anfrage leben, und jede Speicherbereinigung kopiert sie. Nacheinander lief
das so 14 statt 2 s, und alles danach in derselben Anfrage wurde
langsamer (die Primzahlen 25-mal); die Kinder dagegen räumen ihre Choice
Points mit sich ab – das sah aus wie ein Gewinn der Parallelität, auch
mit einem Kern. Darum ist `fib/2` hier deterministisch (`N < 2, !`), und
`ms/2` misst mit `once/1`.
