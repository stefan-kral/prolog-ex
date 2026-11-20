#!/usr/bin/env python3
"""rlwrap-Filter für PrologEx (start_ex): TAB-Ergänzung mit Klammern.

rlwrap trennt Wörter an ( ) [ ] , usw.; ein Eintrag in
.rlwrap_completions kann deshalb keine Klammer enthalten. Dieser Filter
bekommt bei jedem TAB die Zeile und das angefangene Wort und ergänzt je
nach Stelle:

  use_mod<TAB>               use_module, use_module(library(lists)), ...
  use_module(<TAB>           library(lists)), library(clpz)), ...
  use_module(library(cl<TAB> clpz)), clpb))
  library(cl<TAB>            clpz), clpb)        (überall sonst)
  use_module(library(si)<TAB> )                  (nur die fehlenden Klammern)
  sonst                      die Wörter aus .rlwrap_completions; ein
                             Prädikat nur mit Argumenten gleich mit
                             Klammer (mem<TAB> member(), mit und ohne
                             Argumente beides (halt, halt()

Die Bibliotheken stehen in .rlwrap_libraries (eine Auswahl, ein Name je
Zeile), die Stelligkeiten aller Prädikate in .rlwrap_predicates ("name
a1 a2 ...", erzeugt; test/rlwrap_test.exs prüft beide, dort auch, wie
man .rlwrap_predicates neu schreibt).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def read_libraries(path=os.path.join(HERE, ".rlwrap_libraries")):
    try:
        with open(path, encoding="utf-8") as f:
            return [l.strip() for l in f if l.strip() and not l.startswith("#")]
    except OSError:
        return []


# library(Name mit schon getippten schließenden Klammern, am Ende der Zeile
LIB_CLOSING = re.compile(r"(use_module\()?library\(([A-Za-z0-9_/]+)(\)+)$")


def read_predicates(path=os.path.join(HERE, ".rlwrap_predicates")):
    try:
        with open(path, encoding="utf-8") as f:
            return {p[0]: {int(a) for a in p[1:]} for p in (l.split() for l in f) if p}
    except OSError:
        return {}


def with_paren(words, predicates):
    """Wörter als Ergänzungen: Prädikate mit Argumenten mit Klammer."""
    out = []
    for w in words:
        ars = predicates.get(w)
        if ars and min(ars) > 0:
            out.append(w + "(")
        elif ars and max(ars) > 0:
            out += [w, w + "("]
        else:
            out.append(w)
    return out


def complete(line, prefix, words, libraries, predicates=None):
    """Ergänzungen für das angefangene Wort prefix am Ende von line."""
    before = line[: len(line) - len(prefix)] if line.endswith(prefix) else line
    m = LIB_CLOSING.search(before) if prefix == "" else None
    if m:
        # ) ist für rlwrap ein Trennzeichen: nach "use_module(library(si)"
        # ist das Wort leer – nur die noch fehlenden Klammern anbieten
        # (sonst passte das leere Wort auf alles)
        missing = (2 if m.group(1) else 1) - len(m.group(3))
        return [")" * missing] if missing > 0 and m.group(2) in libraries else []
    if before.endswith("library("):
        close = "))" if before.endswith("use_module(library(") else ")"
        cands = [n + close for n in libraries]
    elif before.endswith("use_module("):
        cands = ["library(%s))" % n for n in libraries]
    else:
        cands = with_paren(words, predicates or {}) + [
            "use_module(library(%s))" % n for n in libraries
        ]
    seen = set()
    out = []
    for c in cands:
        if c.startswith(prefix) and c not in seen:
            seen.add(c)
            out.append(c)
    return out


def main():
    # rlwrap setzt RLWRAP_FILTERDIR, aber nicht den Python-Suchpfad
    sys.path.insert(0, os.environ.get("RLWRAP_FILTERDIR", "/usr/share/rlwrap/filters"))
    import rlwrapfilter

    libraries = read_libraries()
    predicates = read_predicates()
    f = rlwrapfilter.RlwrapFilter()
    f.help_text = "PrologEx: TAB ergänzt auch use_module(library(...))"
    f.completion_handler = lambda line, prefix, words: complete(
        line, prefix, words, libraries, predicates
    )
    f.run()


if __name__ == "__main__":
    main()
