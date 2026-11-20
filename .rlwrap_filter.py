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
  sonst                      die Wörter aus .rlwrap_completions

Die Bibliotheken stehen in .rlwrap_libraries (ein Name je Zeile; ein
Test prüft, dass die Liste zu PrologEx passt: test/rlwrap_test.exs, dort
auch, wie man sie neu schreibt).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def read_libraries(path=os.path.join(HERE, ".rlwrap_libraries")):
    try:
        with open(path, encoding="utf-8") as f:
            return [l.strip() for l in f if l.strip() and not l.startswith("#")]
    except OSError:
        return []


def complete(line, prefix, words, libraries):
    """Ergänzungen für das angefangene Wort prefix am Ende von line."""
    before = line[: len(line) - len(prefix)] if line.endswith(prefix) else line
    if before.endswith("library("):
        close = "))" if before.endswith("use_module(library(") else ")"
        cands = [n + close for n in libraries]
    elif before.endswith("use_module("):
        cands = ["library(%s))" % n for n in libraries]
    else:
        cands = list(words) + ["use_module(library(%s))" % n for n in libraries]
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
    f = rlwrapfilter.RlwrapFilter()
    f.help_text = "PrologEx: TAB ergänzt auch use_module(library(...))"
    f.completion_handler = lambda line, prefix, words: complete(line, prefix, words, libraries)
    f.run()


if __name__ == "__main__":
    main()
