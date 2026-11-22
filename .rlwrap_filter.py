#!/usr/bin/env python3
r"""rlwrap-Filter für PrologEx (start_ex): TAB-Ergänzung mit Klammern.

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
  X is ma<TAB>               max(                (auswertbare Funktionen, auch
                             nach =:= < >= usw., in Klammern, nach + - ...;
                             mit leerem Wort auch "(")
  X is A m<TAB>              mod                 (nach einem Operanden: die
                             Operatoren aus Buchstaben: div mod rdiv rem xor)
  X #= ab<TAB>               abs(                (ebenso nach #= #< ..., mit
                             den Funktionen von clpz: abs max min sign ...)
  char_type(C, <TAB>         alnum), ..., upper( (die Klassen von charsio;
  code_type(C, <TAB>         alnum), ..., digit(  code_type: die von swi)
  evaluable_property(<TAB>   _*_,, ..., abs(_),, ..., pi,, ... (die
                             auswertbaren Funktoren; symbolische als
                             Operator: evaluable_property(_<TAB> _*_, ...)
  predicate_property(<TAB>   _:  user:           (Modul des Kopfs)
  X =:<TAB>                  =:=                 (symbolische Wörter: =.. \==
                             @< ...; auch ohne Leerzeichen: X=:<TAB>)
  sonst                      die Wörter aus .rlwrap_completions; ein
                             Prädikat nur mit Argumenten gleich mit
                             Klammer (mem<TAB> member(), auch ohne
                             Argumente nur ohne (halt, repeat); Operatoren
                             ohne (is, =.., \+)

Wörter: start_ex ruft rlwrap mit -b "(){}[],;|!'\"%" – nur diese Zeichen
(und Leerraum) trennen, also auch "=:=" ist ein Wort. Was rlwrap als Wort
übergibt ("X=:" ohne Leerzeichen), zerlegt der Filter selbst wie Prolog:
ergänzt wird das letzte Token (eine Folge aus Buchstaben, Ziffern und _
oder eine aus Symbolzeichen), der Rest bleibt davor stehen.

Die Bibliotheken stehen in .rlwrap_libraries (eine Auswahl, ein Name je
Zeile), die Stelligkeiten aller Prädikate in .rlwrap_predicates ("name
a1 a2 ...", erzeugt), die Flags in .rlwrap_flags ("name" oder "name =
wert ...", erzeugt), die Standard-Operatoren in .rlwrap_ops ("Priorität
Typ Name", erzeugt), die auswertbaren Funktionen in .rlwrap_evaluables
("name a1 a2 ...", erzeugt), Terme dazu für evaluable_property/2 in
.rlwrap_evaluable_terms (einer je Zeile, erzeugt), die von clpz in
.rlwrap_clpz (ebenso), die
Zeichenklassen in .rlwrap_char_types
("char_type t1 t2 ...", erzeugt); test/rlwrap_test.exs prüft sie, dort
auch, wie man die erzeugten neu schreibt.
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
    """Name -> Menge der Stelligkeiten (auch für .rlwrap_evaluables)."""
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


def read_char_types(path=os.path.join(HERE, ".rlwrap_char_types")):
    """Prädikat -> Typen (mit Argument als "name(")."""
    try:
        with open(path, encoding="utf-8") as f:
            return {p[0]: p[1:] for p in (l.split() for l in f) if p}
    except OSError:
        return {}


def read_words(path=os.path.join(HERE, ".rlwrap_completions")):
    """Die Wörter aus .rlwrap_completions (rlwrap gibt dem Filter nur die,
    die schon zu seinem Wort passen – bei X=:<TAB> keines)."""
    try:
        with open(path, encoding="utf-8") as f:
            return [w for l in f for w in l.split()]
    except OSError:
        return []


def read_lines(path):
    """Die nicht leeren Zeilen einer Datei (ohne Zeilenende)."""
    try:
        with open(path, encoding="utf-8") as f:
            return [l.rstrip("\n") for l in f if l.strip()]
    except OSError:
        return []


def load():
    """Alle Daten des Filters (die Dateien neben ihm)."""
    return {
        "words": read_words(),
        "libraries": read_libraries(),
        "predicates": read_predicates(),
        "flags": read_flags(),
        "ops": read_ops(),
        "evaluables": read_predicates(os.path.join(HERE, ".rlwrap_evaluables")),
        "evaluable_terms": read_lines(os.path.join(HERE, ".rlwrap_evaluable_terms")),
        "char_types": read_char_types(),
        "clpz": read_predicates(os.path.join(HERE, ".rlwrap_clpz")),
    }


CHAR_TYPE = re.compile(r"\b(char_type|code_type)\([^,]*,\s*$")

# erstes Argument von evaluable_property/2 bzw. predicate_property/2
EVAL_PROP = re.compile(r"\bevaluable_property\(\s*$")
PRED_PROP = re.compile(r"\bpredicate_property\(\s*$")

# in einem arithmetischen Ausdruck: nach is oder einem Vergleich (nicht
# -> --> >> << @< \= ...); in einem von clpz nach #= #\= #< #> #=< #>=
# (nicht #<==> #==> ...)
ARITH_REL = re.compile(
    r"(?P<is>\bis\b|(?<![=<>\\:@#-])(?:=:=|=\\=|=<|>=|<|>)(?![=<>:]))"
    r"|(?P<clpz>#(?:=<|>=|\\=|=|<|>)(?![=<>]))"
)


def arith_tail(before):
    """(Art, Ausdruck): der Ausdruck nach dem letzten is/Vergleich bis zum
    Cursor, Art "is" oder "clpz"; None, wenn der Cursor nicht (mehr) darin
    steht (auch nach #<==>, #/\\ usw.)."""
    last = None
    for last in ARITH_REL.finditer(before):
        pass
    if last is None:
        return None
    tail = before[last.end() :]
    depth = 0
    for i, ch in enumerate(tail):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth < 0:
                return None
        elif depth == 0 and (
            ch in ",;|#" or tail.startswith("->", i) or (ch == "." and tail[i + 1 : i + 2] in ("", " "))
        ):
            return None
    return ("is" if last.group("is") else "clpz"), tail


def complete_arith(before, prefix, data):
    """Ergänzungen in einem arithmetischen Ausdruck oder None."""
    r = arith_tail(before)
    if r is None:
        return None
    kind, tail = r
    evaluables = data["evaluables" if kind == "is" else "clpz"]
    # die Operatoren aus Buchstaben, die auch auswertbar sind (mod, rem, ...)
    infix = sorted(
        {n for _, t, n in data["ops"] if t in ("xfx", "xfy", "yfx") and 2 in evaluables.get(n, ())}
    )
    t = tail.rstrip()
    if t == "" or t[-1] in "([{,+-*/^\\<>=:" or (t.split() and t.split()[-1] in infix):
        # auch "(" für einen geklammerten Teilausdruck
        cands = ["("] + with_paren(sorted(evaluables), evaluables)
    elif tail != t and (t[-1].isalnum() or t[-1] in ")]_"):
        cands = infix
    else:
        return None
    return [c for c in cands if c.startswith(prefix)]


def with_paren(words, predicates, bare=frozenset()):
    """Wörter als Ergänzungen: Prädikate nur mit Argumenten mit Klammer;
    gibt es sie auch ohne (halt, repeat), nur ohne; ebenso symbolische
    Namen und die in bare (Infix-Operatoren wie is)."""
    out = []
    for w in words:
        ars = predicates.get(w)
        if ars and min(ars) > 0 and w not in bare and not is_symbolic(w):
            out.append(w + "(")
        else:
            out.append(w)
    return out


SYMBOL_CHARS = set("+-*/\\^<>=~:.?@#&$")


def is_symbolic(w):
    return w != "" and all(ch in SYMBOL_CHARS for ch in w)


def split_token(prefix):
    """(davor, Token): das letzte Prolog-Token des Worts von rlwrap – eine
    Folge aus Buchstaben, Ziffern und _ oder eine aus Symbolzeichen."""
    if prefix == "":
        return "", ""
    if prefix[-1] in SYMBOL_CHARS:
        part = lambda ch: ch in SYMBOL_CHARS
    else:
        part = lambda ch: ch.isalnum() or ch == "_"
    i = len(prefix)
    while i > 0 and part(prefix[i - 1]):
        i -= 1
    return prefix[:i], prefix[i:]


def complete(line, prefix, words, data):
    """Ergänzungen für das angefangene Wort prefix am Ende von line (data:
    load()). rlwrap ersetzt das ganze Wort: ergänzt wird dessen letztes
    Token, der Teil davor kommt wieder davor. Ein symbolisches Token in
    einem Ausdruck, oder eines, zu dem nichts passt, gilt als fertig: dann
    wie nach einem Trennzeichen (leeres Token)."""
    # erstes Argument von evaluable_property/2, predicate_property/2: das
    # ganze Wort (_/ ist der Anfang von _/_, kein Token für sich)
    whole = line[: len(line) - len(prefix)] if line.endswith(prefix) else line
    if EVAL_PROP.search(whole):
        return [t + "," for t in data["evaluable_terms"] if t.startswith(prefix)]
    if PRED_PROP.search(whole):
        return [m for m in ("_:", "user:") if m.startswith(prefix)]
    lead, tok = split_token(prefix)
    if is_symbolic(tok) and arith_tail(line[: len(line) - len(tok)]) is not None:
        # in einem Ausdruck ist ein Symbol ein Operator: weiter mit dem
        # Operanden (X is 3*<TAB>)
        lead, tok = prefix, ""
    if lead:
        # rlwrap hat nur die Wörter, die zu seinem ganzen Wort passen
        words = list(words) + data.get("words", [])
    r = complete_token(line, tok, words, data)
    if not r and is_symbolic(tok):
        lead, tok = prefix, ""
        r = complete_token(line, tok, words, data)
    return [lead + c for c in r]


def complete_token(line, prefix, words, data):
    """Ergänzungen für das Token prefix am Ende von line."""
    before = line[: len(line) - len(prefix)] if line.endswith(prefix) else line
    flags, libraries = data["flags"], data["libraries"]
    r = complete_op(before + prefix, prefix, data["ops"])
    if r is not None:
        return r
    m = CHAR_TYPE.search(before)
    if m:
        return [
            c if c.endswith("(") else c + ")"
            for c in data["char_types"].get(m.group(1), [])
            if c.startswith(prefix)
        ]
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
    r = complete_arith(before, prefix, data)
    if r is not None:
        return r
    if before.endswith("library("):
        cands = [n + ")" for n in libraries]
    elif before.endswith("use_module("):
        cands = ["library(%s)" % n for n in libraries]
    else:
        infix = {n for _, t, n in data["ops"] if t in ("xfx", "xfy", "yfx")}
        cands = with_paren(words, data["predicates"], infix)
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

    data = load()
    f = rlwrapfilter.RlwrapFilter()
    f.help_text = "PrologEx: TAB ergänzt auch je nach Stelle (Bibliotheken, Flags, ...)"
    f.completion_handler = lambda line, prefix, words: complete(line, prefix, words, data)
    f.run()


if __name__ == "__main__":
    main()
