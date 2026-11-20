#!/usr/bin/env python3
"""rlwrap-Filter für PrologEx (start_ex): TAB-Ergänzung mit Klammern.

rlwrap trennt Wörter an ( ) [ ] , usw.; ein Eintrag in
.rlwrap_completions kann deshalb keine Klammer enthalten. Dieser Filter
bekommt bei jedem TAB die Zeile und das angefangene Wort und ergänzt je
nach Stelle:

  use_mod<TAB>               use_module(           (wie jedes Prädikat)
  use_module(<TAB>           library(lists), library(clpz), ...
  use_module(library(cl<TAB> clpz), clpb)
  library(cl<TAB>            clpz), clpb)        (überall sonst)
  use_module(library(si)<TAB> )                  (nur die fehlenden Klammern)
  (use_module bleibt offen: danach kann noch die Importliste kommen)
  current_prolog_flag(<TAB>  bounded,, dialect,, ... (alle Flags)
  set_prolog_flag(<TAB>      double_quotes,, ...  (nur die schreibbaren)
  set_prolog_flag(occurs_check,<TAB>  false), true), error)
  sonst                      die Wörter aus .rlwrap_completions; ein
                             Prädikat nur mit Argumenten gleich mit
                             Klammer (mem<TAB> member(), mit und ohne
                             Argumente beides (halt, halt()

Die Bibliotheken stehen in .rlwrap_libraries (eine Auswahl, ein Name je
Zeile), die Stelligkeiten aller Prädikate in .rlwrap_predicates ("name
a1 a2 ...", erzeugt), die Flags in .rlwrap_flags ("name" oder "name =
wert ...", erzeugt); test/rlwrap_test.exs prüft alle drei, dort auch,
wie man die erzeugten neu schreibt.
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


def read_flags(path=os.path.join(HERE, ".rlwrap_flags")):
    """Flag -> Liste der Werte (schreibbar) oder None (nur lesbar)."""
    try:
        with open(path, encoding="utf-8") as f:
            return {p[0]: (p[2:] if p[1:2] == ["="] else None) for p in (l.split() for l in f) if p}
    except OSError:
        return {}


# Flag als erstes Argument bzw. Wert als zweites, am Ende der Zeile
FLAG_NAME = re.compile(r"\b(current|set)_prolog_flag\(\s*$")
FLAG_VALUE = re.compile(r"\bset_prolog_flag\(\s*([a-z_]+)\s*,\s*$")


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


def complete(line, prefix, words, libraries, predicates=None, flags=None):
    """Ergänzungen für das angefangene Wort prefix am Ende von line."""
    before = line[: len(line) - len(prefix)] if line.endswith(prefix) else line
    flags = flags or {}
    m = FLAG_NAME.search(before)
    if m:
        # set_prolog_flag: nur die schreibbaren
        names = [n for n, vs in flags.items() if m.group(1) == "current" or vs is not None]
        return [n + "," for n in sorted(names) if n.startswith(prefix)]
    m = FLAG_VALUE.search(before)
    if m:
        return [v + ")" for v in flags.get(m.group(1)) or [] if v.startswith(prefix)]
    m = LIB_CLOSING.search(before) if prefix == "" else None
    if m:
        # ) ist für rlwrap ein Trennzeichen: nach "use_module(library(si)"
        # ist das Wort leer – nur die noch fehlenden Klammern anbieten
        # (sonst passte das leere Wort auf alles)
        missing = (2 if m.group(1) else 1) - len(m.group(3))
        return [")" * missing] if missing > 0 and m.group(2) in libraries else []
    if before.endswith("library("):
        cands = [n + ")" for n in libraries]
    elif before.endswith("use_module("):
        cands = ["library(%s)" % n for n in libraries]
    else:
        cands = with_paren(words, predicates or {})
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
    flags = read_flags()
    f = rlwrapfilter.RlwrapFilter()
    f.help_text = "PrologEx: TAB ergänzt auch Bibliotheken und Flags"
    f.completion_handler = lambda line, prefix, words: complete(
        line, prefix, words, libraries, predicates, flags
    )
    f.run()


if __name__ == "__main__":
    main()
