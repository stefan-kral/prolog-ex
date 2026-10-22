# prolog-ex
Elixir does Prolog!

Ein Prolog-Kern in Elixir: Unifikation über persistente Substitutions-Maps,
explizite Ziel- und Choice-Point-Stacks mit Last-Call-Optimierung,
Indexierung nach dem ersten Argument und Kompaktierung der Bindungen
(konstanter Speicher bei endrekursiven Schleifen).

```sh
mix test                  # Tests
mix run bench/bench.exs   # Speicher- und Laufzeitmessung
```
