# Demos: library(concurrent) und library(clpz_concurrent)

```sh
examples/parallel/run.sh                      # alle vier Demos, Größe klein
examples/parallel/run.sh mittel eine alle     # Größe mittel, nur zwei Demos
examples/parallel/run.sh -k 4 gross           # mit höchstens 4 Kernen
```

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

Ein Teil des Faktors kommt nicht von den Kernen: die Kinder rechnen in
frischen BEAM-Prozessen mit kleinem Heap, der Toplevel mit einem großen
(mehr Speicherbereinigung). Mit `run.sh -k 1` sieht man diesen Anteil –
die Primzahlen etwa laufen auch mit einem Kern knapp doppelt so schnell.
