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
  current_op(<TAB>           1200,, 1150,, ...   (Prioritäten)
  current_op(700,<TAB>       xfx,                (Typen, passend zur Priorität)
  current_op(P, fx,<TAB>     dynamic), table), ... (Namen, passend zu P
                             und Typ; auch angefangene symbolische: =.)
  sonst                      die Wörter aus .rlwrap_completions; ein
                             Prädikat nur mit Argumenten gleich mit
                             Klammer (mem<TAB> member(), mit und ohne
                             Argumente beides (halt, halt()

Die Bibliotheken stehen in .rlwrap_libraries (eine Auswahl, ein Name je
Zeile), die Stelligkeiten aller Prädikate in .rlwrap_predicates ("name
a1 a2 ...", erzeugt), die Flags in .rlwrap_flags ("name" oder "name =
wert ...", erzeugt), die Standard-Operatoren in .rlwrap_ops ("Priorität
Typ Name", erzeugt); test/rlwrap_test.exs prüft sie, dort auch, wie man
die erzeugten neu schreibt.
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


def read_ops(path=os.path.join(HERE, ".rlwrap_ops")):
    """Liste der Operatoren (Priorität, Typ, Name wie writeq)."""
    try:
        with open(path, encoding="utf-8") as f:
            return [tuple(p) for p in (l.split() for l in f) if len(p) == 3]
    except OSError:
        return []


# current_op(P, T, N): die Argumente bis zur Stelle des Cursors (das
# letzte angefangen, auch symbolisch: rlwrap trennt dort Wörter)
OP_ARGS = re.compile(r"\bcurrent_op\(((?:\s*[^,()\s]*\s*,){0,2})\s*([^,()\s]*)$")


def complete_op(line, prefix, ops):
    """Ergänzungen in current_op/3 oder None, wenn nicht dort."""
    m = OP_ARGS.search(line)
    if not m:
        return None
    given = [a.strip() for a in m.group(1).split(",")[:-1]]
    typed = m.group(2)
    if not typed.endswith(prefix):
        return None
    pos = len(given)
    # schon angegebene Argumente schränken ein (Variablen nicht)
    def fits(op):
        return all(not g or g[0].isupper() or g[0] == "_" or g == v for g, v in zip(given, op))

    cands = sorted({op[pos] for op in ops if fits(op)}, key=lambda c: (-int(c), c) if pos == 0 else c)
    close = ")" if pos == 2 else ","
    # rlwrap ersetzt nur das Wort prefix: ein angefangenes symbolisches
    # Argument ("=.") steht schon da, nur der Rest kommt dazu
    cut = len(typed) - len(prefix)
    return [c[cut:] + close for c in cands if c.startswith(typed)]


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


def complete(line, prefix, words, libraries, predicates=None, flags=None, ops=None):
    """Ergänzungen für das angefangene Wort prefix am Ende von line."""
    before = line[: len(line) - len(prefix)] if line.endswith(prefix) else line
    flags = flags or {}
    if ops:
        r = complete_op(before + prefix, prefix, ops)
        if r is not None:
            return r
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
    ops = read_ops()
    f = rlwrapfilter.RlwrapFilter()
    f.help_text = "PrologEx: TAB ergänzt auch Bibliotheken und Flags"
    f.completion_handler = lambda line, prefix, words: complete(
        line, prefix, words, libraries, predicates, flags, ops
    )
    f.run()


if __name__ == "__main__":
    main()
