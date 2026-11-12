defmodule PrologEx.Builtins.ListSicstus do
  @moduledoc """
  Die übrigen Prädikate aus SICStus' `library(lists)` (SICStus 4.9), in
  Prolog. Bedeutung nach der SICStus-Dokumentation; wo sie die
  Reihenfolge der Lösungen offen lässt, die der klassischen Definitionen
  (DEC-10/Quintus-Bibliothek von R. A. O'Keefe), aus denen SICStus'
  Bibliothek stammt.

    * Listen zerlegen: `append/5`, `append_length/3,4`, `prefix/2`,
      `proper_prefix/2`, `prefix_length/3`, `proper_prefix_length/3`,
      `suffix/2`, `proper_suffix/2`, `suffix_length/3`,
      `proper_suffix_length/3`, `sublist/3,4,5`, `segment/2`,
      `proper_segment/2`, `subseq/3`, `subseq0/2`, `subseq1/2`, `cons/3`,
      `head/2`, `tail/2`, `last/3` (Fore, Last, List)
    * Umordnen: `rev/2`, `rotate_list/2,3`, `perm/2`, `perm2/4`,
      `remove_dups/2` (wie `sort/2`)
    * Löschen und Auswählen: `delete/4` (die ersten Count Elemente, die
      mit Kill unifizierbar sind – wie `delete/3`), `correspond/4`,
      `select_max/3,4`, `select_min/3,4` (das erste größte bzw. kleinste;
      der Rest in der alten Reihenfolge), `max_member/3`, `min_member/3`
      (`max_member(:P, ?Max, +L)`: bei Gleichstand das erste)
    * Mit Prädikat: `scanlist/4,5,6` (wie `foldl/4,5,6`), `cumlist/4,5,6`
      (die Zwischenergebnisse), `map_product/4` (zeilenweise),
      `some/2,3,4`, `somechk/2,3,4` (die erste Lösung), `include/4,5`,
      `exclude/4,5` (Elemente der ersten Liste), `convlist/3`,
      `group/3,4,5`, `increasing_prefix/3,4`, `decreasing_prefix/3,4`
      (wie SICStus: Prefix samt erstem Element von Suffix monoton, also
      ohne das letzte Element des monotonen Anfangs)
    * Gruppieren (gleich heißt `==/2`): `clumps/2`, `clumped/2`,
      `keyclumps/2`, `keyclumped/2`
  """
  use PrologEx.Builtin, module: "lists"

  def meta do
    for {n, spec} <- [
          {"cumlist", [3, "+", "?", "?"]},
          {"cumlist", [4, "+", "+", "?", "?"]},
          {"cumlist", [5, "+", "+", "+", "?", "?"]},
          {"scanlist", [3, "+", "?", "?"]},
          {"scanlist", [4, "+", "+", "?", "?"]},
          {"scanlist", [5, "+", "+", "+", "?", "?"]},
          {"map_product", [3, "+", "+", "?"]},
          {"some", [1, "+"]},
          {"some", [2, "+", "?"]},
          {"some", [3, "+", "?", "?"]},
          {"somechk", [1, "+"]},
          {"somechk", [2, "+", "?"]},
          {"somechk", [3, "+", "?", "?"]},
          {"include", [2, "+", "+", "?"]},
          {"include", [3, "+", "+", "+", "?"]},
          {"exclude", [2, "+", "+", "?"]},
          {"exclude", [3, "+", "+", "+", "?"]},
          {"convlist", [2, "+", "?"]},
          {"group", [2, "+", "?"]},
          {"group", [1, "+", "?", "?"]},
          {"group", [2, "+", "+", "?", "?"]},
          {"increasing_prefix", [2, "?", "?", "?"]},
          {"decreasing_prefix", [2, "?", "?", "?"]},
          {"max_member", [2, "?", "+"]},
          {"min_member", [2, "?", "+"]},
          {"select_max", [2, "?", "+", "?"]},
          {"select_min", [2, "?", "+", "?"]}
        ],
        do: {"lists", n, spec}
  end

  # aus dem Prolog-Quelltext erzeugt (Klauseln wie geschrieben)
  def library do
    import PrologEx, only: [s: 2, v: 1, a: 1, fact: 1, rule: 2]

    %{
      "lists" => [
        fact(s("append", [[], v("T1"), v("T1"), v("T2"), v("T2")])),
        rule(
          s("append", [
            [v("H") | v("T")],
            v("T1"),
            [v("H") | v("L1")],
            v("T2"),
            [v("H") | v("L2")]
          ]),
          [s("append", [v("T"), v("T1"), v("L1"), v("T2"), v("L2")])]
        ),
        rule(s("append_length", [v("Prefix"), v("Suffix"), v("List"), v("Length")]), [
          s(";", [
            s("->", [
              s("var", [v("Length")]),
              s("$append_length", [v("Prefix"), v("Suffix"), v("List"), 0, v("Length")])
            ]),
            s(",", [
              s("length", [v("Prefix"), v("Length")]),
              s("append", [v("Prefix"), v("Suffix"), v("List")])
            ])
          ])
        ]),
        fact(s("$append_length", [[], v("L"), v("L"), v("N"), v("N")])),
        rule(
          s("$append_length", [[v("H") | v("T")], v("S"), [v("H") | v("L")], v("N0"), v("N")]),
          [
            s("is", [v("N1"), s("+", [v("N0"), 1])]),
            s("$append_length", [v("T"), v("S"), v("L"), v("N1"), v("N")])
          ]
        ),
        rule(s("append_length", [v("Suffix"), v("List"), v("Length")]), [
          s(";", [
            s("->", [
              s("var", [v("Length")]),
              s("$append_length", [v("List"), v("Suffix"), 0, v("Length")])
            ]),
            s(";", [
              s("->", [
                s(",", [s("integer", [v("Length")]), s(">=", [v("Length"), 0])]),
                s("$drop", [v("Length"), v("List"), v("Suffix")])
              ]),
              s("length", [v("_"), v("Length")])
            ])
          ])
        ]),
        fact(s("$append_length", [v("L"), v("L"), v("N"), v("N")])),
        rule(s("$append_length", [[v("_") | v("T")], v("S"), v("N0"), v("N")]), [
          s("is", [v("N1"), s("+", [v("N0"), 1])]),
          s("$append_length", [v("T"), v("S"), v("N1"), v("N")])
        ]),
        rule(s("$drop", [0, v("L"), v("S")]), [a("!"), s("=", [v("S"), v("L")])]),
        rule(s("$drop", [v("N"), [v("_") | v("T")], v("S")]), [
          s("is", [v("N1"), s("-", [v("N"), 1])]),
          s("$drop", [v("N1"), v("T"), v("S")])
        ]),
        fact(s("prefix", [v("_"), []])),
        rule(s("prefix", [[v("H") | v("T")], [v("H") | v("P")]]), [s("prefix", [v("T"), v("P")])]),
        fact(s("proper_prefix", [[v("_") | v("_")], []])),
        rule(s("proper_prefix", [[v("H") | v("T")], [v("H") | v("P")]]), [
          s("proper_prefix", [v("T"), v("P")])
        ]),
        rule(s("prefix_length", [v("List"), v("Prefix"), v("Length")]), [
          s("append_length", [v("Prefix"), v("_"), v("List"), v("Length")])
        ]),
        rule(s("proper_prefix_length", [v("List"), v("Prefix"), v("Length")]), [
          s("append_length", [v("Prefix"), [v("_") | v("_")], v("List"), v("Length")])
        ]),
        fact(s("suffix", [v("L"), v("L")])),
        rule(s("suffix", [[v("_") | v("T")], v("S")]), [s("suffix", [v("T"), v("S")])]),
        rule(s("proper_suffix", [[v("_") | v("T")], v("S")]), [s("suffix", [v("T"), v("S")])]),
        rule(s("suffix_length", [v("List"), v("Suffix"), v("Length")]), [
          s("length", [v("List"), v("N")]),
          s(";", [
            s("->", [
              s("integer", [v("Length")]),
              s(",", [
                s("is", [v("D"), s("-", [v("N"), v("Length")])]),
                s(",", [s(">=", [v("D"), 0]), s("$drop", [v("D"), v("List"), v("Suffix")])])
              ])
            ]),
            s(";", [
              s("->", [s("nonvar", [v("Length")]), s("length", [v("_"), v("Length")])]),
              s(";", [
                s("->", [
                  s(",", [s("$skip_list", [v("K"), v("Suffix"), v("R")]), s("==", [v("R"), []])]),
                  s(",", [
                    s("=", [v("Length"), v("K")]),
                    s(",", [
                      s("is", [v("D"), s("-", [v("N"), v("K")])]),
                      s(",", [s(">=", [v("D"), 0]), s("$drop", [v("D"), v("List"), v("Suffix")])])
                    ])
                  ])
                ]),
                s("$suffix_length", [v("List"), v("N"), v("Suffix"), v("Length")])
              ])
            ])
          ])
        ]),
        fact(s("$suffix_length", [v("L"), v("N"), v("L"), v("N")])),
        rule(s("$suffix_length", [[v("_") | v("T")], v("N0"), v("S"), v("N")]), [
          s("is", [v("N1"), s("-", [v("N0"), 1])]),
          s("$suffix_length", [v("T"), v("N1"), v("S"), v("N")])
        ]),
        rule(s("proper_suffix_length", [[v("_") | v("T")], v("Suffix"), v("Length")]), [
          s("suffix_length", [v("T"), v("Suffix"), v("Length")])
        ]),
        rule(s("sublist", [v("Whole"), v("Part"), v("Before"), v("Length"), v("After")]), [
          s("append_length", [v("Rest"), v("Whole"), v("Before")]),
          s("append_length", [v("Part"), v("Omega"), v("Rest"), v("Length")]),
          s("length", [v("Omega"), v("After")])
        ]),
        rule(s("sublist", [v("Whole"), v("Part"), v("Before"), v("Length")]), [
          s("sublist", [v("Whole"), v("Part"), v("Before"), v("Length"), v("_")])
        ]),
        rule(s("sublist", [v("Whole"), v("Part"), v("Before")]), [
          s("sublist", [v("Whole"), v("Part"), v("Before"), v("_"), v("_")])
        ]),
        rule(s("segment", [v("List"), v("Segment")]), [
          s("suffix", [v("List"), v("S")]),
          s("prefix", [v("S"), v("Segment")])
        ]),
        rule(s("proper_segment", [v("List"), v("Segment")]), [
          s("proper_prefix", [v("List"), v("Segment")])
        ]),
        rule(s("proper_segment", [[v("_") | v("T")], v("Segment")]), [
          s("segment", [v("T"), v("Segment")])
        ]),
        fact(s("subseq", [[], [], []])),
        rule(s("subseq", [[v("H") | v("T")], v("S"), [v("H") | v("C")]]), [
          s("subseq", [v("T"), v("S"), v("C")])
        ]),
        rule(s("subseq", [[v("H") | v("T")], [v("H") | v("S")], v("C")]), [
          s("subseq", [v("T"), v("S"), v("C")])
        ]),
        fact(s("subseq0", [v("L"), v("L")])),
        rule(s("subseq0", [v("L"), v("S")]), [s("subseq1", [v("L"), v("S")])]),
        rule(s("subseq1", [[v("_") | v("T")], v("S")]), [s("subseq0", [v("T"), v("S")])]),
        rule(s("subseq1", [[v("H") | v("T")], [v("H") | v("S")]]), [
          s("subseq1", [v("T"), v("S")])
        ]),
        fact(s("cons", [v("H"), v("T"), [v("H") | v("T")]])),
        fact(s("head", [[v("H") | v("_")], v("H")])),
        fact(s("tail", [[v("_") | v("T")], v("T")])),
        rule(s("last", [v("Fore"), v("Last"), v("List")]), [
          s("$last", [v("List"), v("Fore"), v("Last")])
        ]),
        rule(s("$last", [[v("X") | v("Xs")], v("Fore"), v("Last")]), [
          s("$last", [v("Xs"), v("X"), v("Fore"), v("Last")])
        ]),
        fact(s("$last", [[], v("X"), [], v("X")])),
        rule(s("$last", [[v("Y") | v("Ys")], v("X"), [v("X") | v("Fore")], v("Last")]), [
          s("$last", [v("Ys"), v("Y"), v("Fore"), v("Last")])
        ]),
        rule(s("delete", [v("List"), v("Kill"), v("Count"), v("Residue")]), [
          s("$count", [v("Count")]),
          s("$delete", [v("List"), v("Kill"), v("Count"), v("Residue")])
        ]),
        fact(s("$delete", [[], v("_"), v("_"), []])),
        rule(s("$delete", [[v("H") | v("T")], v("K"), v("N"), v("R")]), [
          s(";", [
            s("->", [s("=:=", [v("N"), 0]), s("=", [v("R"), [v("H") | v("T")]])]),
            s(";", [
              s("->", [
                s("\\+", [s("\\=", [v("H"), v("K")])]),
                s(",", [
                  s("is", [v("N1"), s("-", [v("N"), 1])]),
                  s("$delete", [v("T"), v("K"), v("N1"), v("R")])
                ])
              ]),
              s(",", [
                s("=", [v("R"), [v("H") | v("R1")]]),
                s("$delete", [v("T"), v("K"), v("N"), v("R1")])
              ])
            ])
          ])
        ]),
        rule(s("$count", [v("N")]), [
          s(";", [
            s("->", [
              s("var", [v("N")]),
              s("throw", [s("error", [a("instantiation_error"), s("/", [a("delete"), 4])])])
            ]),
            s(";", [
              s("->", [
                s("\\+", [s("integer", [v("N")])]),
                s("throw", [
                  s("error", [s("type_error", [a("integer"), v("N")]), s("/", [a("delete"), 4])])
                ])
              ]),
              s(";", [
                s("->", [
                  s("<", [v("N"), 0]),
                  s("throw", [
                    s("error", [
                      s("domain_error", [a("not_less_than_zero"), v("N")]),
                      s("/", [a("delete"), 4])
                    ])
                  ])
                ]),
                a("true")
              ])
            ])
          ])
        ]),
        rule(s("correspond", [v("X"), [v("X") | v("_")], [v("Y") | v("_")], v("Y")]), [a("!")]),
        rule(s("correspond", [v("X"), [v("_") | v("T")], [v("_") | v("U")], v("Y")]), [
          s("correspond", [v("X"), v("T"), v("U"), v("Y")])
        ]),
        fact(s("perm", [[], []])),
        rule(s("perm", [v("List"), [v("First") | v("Perm")]]), [
          s("select", [v("First"), v("List"), v("Rest")]),
          s("perm", [v("Rest"), v("Perm")])
        ]),
        fact(s("perm2", [v("X"), v("Y"), v("X"), v("Y")])),
        fact(s("perm2", [v("X"), v("Y"), v("Y"), v("X")])),
        rule(s("rev", [v("List"), v("Reversed")]), [s("$rev", [v("List"), [], v("Reversed")])]),
        fact(s("$rev", [[], v("R"), v("R")])),
        rule(s("$rev", [[v("H") | v("T")], v("A"), v("R")]), [
          s("$rev", [v("T"), [v("H") | v("A")], v("R")])
        ]),
        rule(s("rotate_list", [v("List"), v("Rotated")]), [
          s("rotate_list", [1, v("List"), v("Rotated")])
        ]),
        rule(s("rotate_list", [v("Amount"), v("List"), v("Rotated")]), [
          s("same_length", [v("List"), v("Rotated")]),
          s("length", [v("List"), v("N")]),
          s(";", [
            s("->", [s(">=", [v("Amount"), 0]), s("=", [v("P"), v("Amount")])]),
            s("is", [v("P"), s("+", [v("N"), v("Amount")])])
          ]),
          s(">=", [v("P"), 0]),
          s("=<", [v("P"), v("N")]),
          s("length", [v("Prefix"), v("P")]),
          s("append", [v("Prefix"), v("Suffix"), v("List")]),
          s("append", [v("Suffix"), v("Prefix"), v("Rotated")])
        ]),
        rule(s("remove_dups", [v("List"), v("Pruned")]), [s("sort", [v("List"), v("Pruned")])]),
        rule(s("scanlist", [v("P"), v("Xs"), v("V0"), v("V")]), [
          s("foldl", [v("P"), v("Xs"), v("V0"), v("V")])
        ]),
        rule(s("scanlist", [v("P"), v("Xs"), v("Ys"), v("V0"), v("V")]), [
          s("foldl", [v("P"), v("Xs"), v("Ys"), v("V0"), v("V")])
        ]),
        rule(s("scanlist", [v("P"), v("Xs"), v("Ys"), v("Zs"), v("V0"), v("V")]), [
          s("foldl", [v("P"), v("Xs"), v("Ys"), v("Zs"), v("V0"), v("V")])
        ]),
        rule(s("cumlist", [v("P"), v("Xs"), v("V0"), v("Vs")]), [
          s("$cumlist", [v("Xs"), v("P"), v("V0"), v("Vs")])
        ]),
        fact(s("$cumlist", [[], v("_"), v("_"), []])),
        rule(s("$cumlist", [[v("X") | v("Xs")], v("P"), v("V0"), [v("V") | v("Vs")]]), [
          s("call", [v("P"), v("X"), v("V0"), v("V")]),
          s("$cumlist", [v("Xs"), v("P"), v("V"), v("Vs")])
        ]),
        rule(s("cumlist", [v("P"), v("Xs"), v("Ys"), v("V0"), v("Vs")]), [
          s("$cumlist", [v("Xs"), v("Ys"), v("P"), v("V0"), v("Vs")])
        ]),
        fact(s("$cumlist", [[], [], v("_"), v("_"), []])),
        rule(
          s("$cumlist", [
            [v("X") | v("Xs")],
            [v("Y") | v("Ys")],
            v("P"),
            v("V0"),
            [v("V") | v("Vs")]
          ]),
          [
            s("call", [v("P"), v("X"), v("Y"), v("V0"), v("V")]),
            s("$cumlist", [v("Xs"), v("Ys"), v("P"), v("V"), v("Vs")])
          ]
        ),
        rule(s("cumlist", [v("P"), v("Xs"), v("Ys"), v("Zs"), v("V0"), v("Vs")]), [
          s("$cumlist", [v("Xs"), v("Ys"), v("Zs"), v("P"), v("V0"), v("Vs")])
        ]),
        fact(s("$cumlist", [[], [], [], v("_"), v("_"), []])),
        rule(
          s("$cumlist", [
            [v("X") | v("Xs")],
            [v("Y") | v("Ys")],
            [v("Z") | v("Zs")],
            v("P"),
            v("V0"),
            [v("V") | v("Vs")]
          ]),
          [
            s("call", [v("P"), v("X"), v("Y"), v("Z"), v("V0"), v("V")]),
            s("$cumlist", [v("Xs"), v("Ys"), v("Zs"), v("P"), v("V"), v("Vs")])
          ]
        ),
        rule(s("map_product", [v("P"), v("Xs"), v("Ys"), v("Zs")]), [
          s("$map_product", [v("Xs"), v("Ys"), v("P"), v("Zs"), []])
        ]),
        fact(s("$map_product", [[], v("_"), v("_"), v("Zs"), v("Zs")])),
        rule(s("$map_product", [[v("X") | v("Xs")], v("Ys"), v("P"), v("Zs0"), v("Zs")]), [
          s("$map_product_row", [v("Ys"), v("X"), v("P"), v("Zs0"), v("Zs1")]),
          s("$map_product", [v("Xs"), v("Ys"), v("P"), v("Zs1"), v("Zs")])
        ]),
        fact(s("$map_product_row", [[], v("_"), v("_"), v("Zs"), v("Zs")])),
        rule(
          s("$map_product_row", [[v("Y") | v("Ys")], v("X"), v("P"), [v("Z") | v("Zs0")], v("Zs")]),
          [
            s("call", [v("P"), v("X"), v("Y"), v("Z")]),
            s("$map_product_row", [v("Ys"), v("X"), v("P"), v("Zs0"), v("Zs")])
          ]
        ),
        rule(s("some", [v("P"), [v("X") | v("_")]]), [s("call", [v("P"), v("X")])]),
        rule(s("some", [v("P"), [v("_") | v("Xs")]]), [s("some", [v("P"), v("Xs")])]),
        rule(s("some", [v("P"), [v("X") | v("_")], [v("Y") | v("_")]]), [
          s("call", [v("P"), v("X"), v("Y")])
        ]),
        rule(s("some", [v("P"), [v("_") | v("Xs")], [v("_") | v("Ys")]]), [
          s("some", [v("P"), v("Xs"), v("Ys")])
        ]),
        rule(s("some", [v("P"), [v("X") | v("_")], [v("Y") | v("_")], [v("Z") | v("_")]]), [
          s("call", [v("P"), v("X"), v("Y"), v("Z")])
        ]),
        rule(s("some", [v("P"), [v("_") | v("Xs")], [v("_") | v("Ys")], [v("_") | v("Zs")]]), [
          s("some", [v("P"), v("Xs"), v("Ys"), v("Zs")])
        ]),
        rule(s("somechk", [v("P"), [v("X") | v("_")]]), [s("call", [v("P"), v("X")]), a("!")]),
        rule(s("somechk", [v("P"), [v("_") | v("Xs")]]), [s("somechk", [v("P"), v("Xs")])]),
        rule(s("somechk", [v("P"), [v("X") | v("_")], [v("Y") | v("_")]]), [
          s("call", [v("P"), v("X"), v("Y")]),
          a("!")
        ]),
        rule(s("somechk", [v("P"), [v("_") | v("Xs")], [v("_") | v("Ys")]]), [
          s("somechk", [v("P"), v("Xs"), v("Ys")])
        ]),
        rule(s("somechk", [v("P"), [v("X") | v("_")], [v("Y") | v("_")], [v("Z") | v("_")]]), [
          s("call", [v("P"), v("X"), v("Y"), v("Z")]),
          a("!")
        ]),
        rule(s("somechk", [v("P"), [v("_") | v("Xs")], [v("_") | v("Ys")], [v("_") | v("Zs")]]), [
          s("somechk", [v("P"), v("Xs"), v("Ys"), v("Zs")])
        ]),
        rule(s("include", [v("P"), v("Xs"), v("Ys"), v("S")]), [
          s("$include", [v("Xs"), v("Ys"), v("P"), v("S")])
        ]),
        fact(s("$include", [[], [], v("_"), []])),
        rule(s("$include", [[v("X") | v("Xs")], [v("Y") | v("Ys")], v("P"), v("S")]), [
          s(";", [
            s("->", [s("call", [v("P"), v("X"), v("Y")]), s("=", [v("S"), [v("X") | v("S1")]])]),
            s("=", [v("S"), v("S1")])
          ]),
          s("$include", [v("Xs"), v("Ys"), v("P"), v("S1")])
        ]),
        rule(s("include", [v("P"), v("Xs"), v("Ys"), v("Zs"), v("S")]), [
          s("$include", [v("Xs"), v("Ys"), v("Zs"), v("P"), v("S")])
        ]),
        fact(s("$include", [[], [], [], v("_"), []])),
        rule(
          s("$include", [
            [v("X") | v("Xs")],
            [v("Y") | v("Ys")],
            [v("Z") | v("Zs")],
            v("P"),
            v("S")
          ]),
          [
            s(";", [
              s("->", [
                s("call", [v("P"), v("X"), v("Y"), v("Z")]),
                s("=", [v("S"), [v("X") | v("S1")]])
              ]),
              s("=", [v("S"), v("S1")])
            ]),
            s("$include", [v("Xs"), v("Ys"), v("Zs"), v("P"), v("S1")])
          ]
        ),
        rule(s("exclude", [v("P"), v("Xs"), v("Ys"), v("S")]), [
          s("$exclude", [v("Xs"), v("Ys"), v("P"), v("S")])
        ]),
        fact(s("$exclude", [[], [], v("_"), []])),
        rule(s("$exclude", [[v("X") | v("Xs")], [v("Y") | v("Ys")], v("P"), v("S")]), [
          s(";", [
            s("->", [s("call", [v("P"), v("X"), v("Y")]), s("=", [v("S"), v("S1")])]),
            s("=", [v("S"), [v("X") | v("S1")]])
          ]),
          s("$exclude", [v("Xs"), v("Ys"), v("P"), v("S1")])
        ]),
        rule(s("exclude", [v("P"), v("Xs"), v("Ys"), v("Zs"), v("S")]), [
          s("$exclude", [v("Xs"), v("Ys"), v("Zs"), v("P"), v("S")])
        ]),
        fact(s("$exclude", [[], [], [], v("_"), []])),
        rule(
          s("$exclude", [
            [v("X") | v("Xs")],
            [v("Y") | v("Ys")],
            [v("Z") | v("Zs")],
            v("P"),
            v("S")
          ]),
          [
            s(";", [
              s("->", [s("call", [v("P"), v("X"), v("Y"), v("Z")]), s("=", [v("S"), v("S1")])]),
              s("=", [v("S"), [v("X") | v("S1")]])
            ]),
            s("$exclude", [v("Xs"), v("Ys"), v("Zs"), v("P"), v("S1")])
          ]
        ),
        rule(s("group", [v("P"), v("List"), v("Groups")]), [
          s("$group", [v("List"), v("P"), v("Groups")])
        ]),
        fact(s("$group", [[], v("_"), []])),
        rule(s("$group", [[v("H") | v("T")], v("P"), [[v("H") | v("G")] | v("Gs")]]), [
          s("group", [v("P"), v("H"), v("T"), v("G"), v("Rest")]),
          s("$group", [v("Rest"), v("P"), v("Gs")])
        ]),
        rule(s("group", [v("P"), v("List"), v("Front"), v("Back")]), [
          s("$group", [v("List"), v("P"), v("Front"), v("Back")])
        ]),
        fact(s("$group", [[], v("_"), [], []])),
        rule(s("$group", [[v("X") | v("Xs")], v("P"), v("Front"), v("Back")]), [
          s(";", [
            s("->", [
              s("call", [v("P"), v("X")]),
              s(",", [
                s("=", [v("Front"), [v("X") | v("F")]]),
                s("$group", [v("Xs"), v("P"), v("F"), v("Back")])
              ])
            ]),
            s(",", [s("=", [v("Front"), []]), s("=", [v("Back"), [v("X") | v("Xs")]])])
          ])
        ]),
        rule(s("group", [v("P"), v("Key"), v("List"), v("Front"), v("Back")]), [
          s("$group", [v("List"), v("P"), v("Key"), v("Front"), v("Back")])
        ]),
        fact(s("$group", [[], v("_"), v("_"), [], []])),
        rule(s("$group", [[v("X") | v("Xs")], v("P"), v("K"), v("Front"), v("Back")]), [
          s(";", [
            s("->", [
              s("call", [v("P"), v("K"), v("X")]),
              s(",", [
                s("=", [v("Front"), [v("X") | v("F")]]),
                s("$group", [v("Xs"), v("P"), v("K"), v("F"), v("Back")])
              ])
            ]),
            s(",", [s("=", [v("Front"), []]), s("=", [v("Back"), [v("X") | v("Xs")]])])
          ])
        ]),
        rule(s("increasing_prefix", [v("Seq"), v("Prefix"), v("Suffix")]), [
          s("$monotone", [v("Seq"), v("Prefix"), v("Suffix"), a("@=<"), a("up")])
        ]),
        rule(s("increasing_prefix", [v("Order"), v("Seq"), v("Prefix"), v("Suffix")]), [
          s("$monotone", [v("Seq"), v("Prefix"), v("Suffix"), v("Order"), a("up")])
        ]),
        rule(s("decreasing_prefix", [v("Seq"), v("Prefix"), v("Suffix")]), [
          s("$monotone", [v("Seq"), v("Prefix"), v("Suffix"), a("@=<"), a("down")])
        ]),
        rule(s("decreasing_prefix", [v("Order"), v("Seq"), v("Prefix"), v("Suffix")]), [
          s("$monotone", [v("Seq"), v("Prefix"), v("Suffix"), v("Order"), a("down")])
        ]),
        rule(s("$monotone", [v("Seq"), v("Prefix"), v("Suffix"), v("O"), v("D")]), [
          s(";", [
            s("->", [s("var", [v("Seq")]), s("append", [v("Prefix"), v("Suffix"), v("Seq")])]),
            a("true")
          ]),
          s("$monotone_start", [v("Seq"), v("O"), v("D"), v("Prefix"), v("Suffix")])
        ]),
        fact(s("$monotone_start", [[], v("_"), v("_"), [], []])),
        rule(
          s("$monotone_start", [[v("X") | v("Xs")], v("O"), v("D"), v("Prefix"), v("Suffix")]),
          [s("$monotone_run", [v("Xs"), v("X"), v("O"), v("D"), v("Prefix"), v("Suffix")])]
        ),
        fact(s("$monotone_run", [[], v("X"), v("_"), v("_"), [], [v("X")]])),
        rule(
          s("$monotone_run", [
            [v("Y") | v("Ys")],
            v("X"),
            v("O"),
            v("D"),
            v("Prefix"),
            v("Suffix")
          ]),
          [
            s(";", [
              s("->", [
                s("$in_order", [v("D"), v("O"), v("X"), v("Y")]),
                s(",", [
                  s("=", [v("Prefix"), [v("X") | v("P")]]),
                  s("$monotone_run", [v("Ys"), v("Y"), v("O"), v("D"), v("P"), v("Suffix")])
                ])
              ]),
              s(",", [
                s("=", [v("Prefix"), []]),
                s("=", [v("Suffix"), [v("X"), v("Y") | v("Ys")]])
              ])
            ])
          ]
        ),
        rule(s("$in_order", [a("up"), v("O"), v("X"), v("Y")]), [
          s("call", [v("O"), v("X"), v("Y")])
        ]),
        rule(s("$in_order", [a("down"), v("O"), v("X"), v("Y")]), [
          s("call", [v("O"), v("Y"), v("X")])
        ]),
        fact(s("clumps", [[], []])),
        rule(s("clumps", [[v("X") | v("Xs")], [[v("X") | v("C")] | v("Cs")]]), [
          s("$clump", [v("Xs"), v("X"), v("C"), v("Rest")]),
          s("clumps", [v("Rest"), v("Cs")])
        ]),
        rule(s("$clump", [[v("Y") | v("Ys")], v("X"), [v("Y") | v("C")], v("Rest")]), [
          s("==", [v("Y"), v("X")]),
          a("!"),
          s("$clump", [v("Ys"), v("X"), v("C"), v("Rest")])
        ]),
        fact(s("$clump", [v("Rest"), v("_"), [], v("Rest")])),
        fact(s("clumped", [[], []])),
        rule(s("clumped", [[v("X") | v("Xs")], [s("-", [v("X"), v("N")]) | v("Ns")]]), [
          s("$clump", [v("Xs"), v("X"), v("C"), v("Rest")]),
          s("length", [[v("X") | v("C")], v("N")]),
          s("clumped", [v("Rest"), v("Ns")])
        ]),
        fact(s("keyclumps", [[], []])),
        rule(
          s("keyclumps", [
            [s("-", [v("K"), v("V")]) | v("Ps")],
            [[s("-", [v("K"), v("V")]) | v("C")] | v("Cs")]
          ]),
          [
            s("$keyclump", [v("Ps"), v("K"), v("C"), v("Rest")]),
            s("keyclumps", [v("Rest"), v("Cs")])
          ]
        ),
        rule(
          s("$keyclump", [
            [s("-", [v("K1"), v("V")]) | v("Ps")],
            v("K"),
            [s("-", [v("K1"), v("V")]) | v("C")],
            v("Rest")
          ]),
          [
            s("==", [v("K1"), v("K")]),
            a("!"),
            s("$keyclump", [v("Ps"), v("K"), v("C"), v("Rest")])
          ]
        ),
        fact(s("$keyclump", [v("Rest"), v("_"), [], v("Rest")])),
        fact(s("keyclumped", [[], []])),
        rule(
          s("keyclumped", [
            [s("-", [v("K"), v("V")]) | v("Ps")],
            [s("-", [v("K"), [v("V") | v("Vs")]]) | v("Gs")]
          ]),
          [
            s("$keyclumped", [v("Ps"), v("K"), v("Vs"), v("Rest")]),
            s("keyclumped", [v("Rest"), v("Gs")])
          ]
        ),
        rule(
          s("$keyclumped", [
            [s("-", [v("K1"), v("V")]) | v("Ps")],
            v("K"),
            [v("V") | v("Vs")],
            v("Rest")
          ]),
          [
            s("==", [v("K1"), v("K")]),
            a("!"),
            s("$keyclumped", [v("Ps"), v("K"), v("Vs"), v("Rest")])
          ]
        ),
        fact(s("$keyclumped", [v("Rest"), v("_"), [], v("Rest")])),
        rule(s("max_member", [v("P"), v("Max"), [v("H") | v("T")]]), [
          s("$max_member", [v("T"), v("P"), v("H"), v("Max")])
        ]),
        fact(s("$max_member", [[], v("_"), v("M"), v("M")])),
        rule(s("$max_member", [[v("H") | v("T")], v("P"), v("M0"), v("M")]), [
          s(";", [
            s("->", [s("call", [v("P"), v("H"), v("M0")]), s("=", [v("M1"), v("M0")])]),
            s("=", [v("M1"), v("H")])
          ]),
          s("$max_member", [v("T"), v("P"), v("M1"), v("M")])
        ]),
        rule(s("min_member", [v("P"), v("Min"), [v("H") | v("T")]]), [
          s("$min_member", [v("T"), v("P"), v("H"), v("Min")])
        ]),
        fact(s("$min_member", [[], v("_"), v("M"), v("M")])),
        rule(s("$min_member", [[v("H") | v("T")], v("P"), v("M0"), v("M")]), [
          s(";", [
            s("->", [s("call", [v("P"), v("M0"), v("H")]), s("=", [v("M1"), v("M0")])]),
            s("=", [v("M1"), v("H")])
          ]),
          s("$min_member", [v("T"), v("P"), v("M1"), v("M")])
        ]),
        rule(s("select_max", [v("E"), v("Set"), v("Residue")]), [
          s("select_max", [a("@=<"), v("E"), v("Set"), v("Residue")])
        ]),
        rule(s("select_max", [v("P"), v("E"), [v("H") | v("T")], v("Residue")]), [
          s("$select_best", [v("T"), v("P"), a("max"), v("H"), 0, 1, v("M"), v("K")]),
          s("$delete_nth0", [v("K"), [v("H") | v("T")], v("R")]),
          s("=", [v("E"), v("M")]),
          s("=", [v("Residue"), v("R")])
        ]),
        rule(s("select_min", [v("E"), v("Set"), v("Residue")]), [
          s("select_min", [a("@=<"), v("E"), v("Set"), v("Residue")])
        ]),
        rule(s("select_min", [v("P"), v("E"), [v("H") | v("T")], v("Residue")]), [
          s("$select_best", [v("T"), v("P"), a("min"), v("H"), 0, 1, v("M"), v("K")]),
          s("$delete_nth0", [v("K"), [v("H") | v("T")], v("R")]),
          s("=", [v("E"), v("M")]),
          s("=", [v("Residue"), v("R")])
        ]),
        fact(s("$select_best", [[], v("_"), v("_"), v("M"), v("K"), v("_"), v("M"), v("K")])),
        rule(
          s("$select_best", [
            [v("H") | v("T")],
            v("P"),
            v("D"),
            v("M0"),
            v("K0"),
            v("I"),
            v("M"),
            v("K")
          ]),
          [
            s("is", [v("I1"), s("+", [v("I"), 1])]),
            s(";", [
              s("->", [
                s("$keeps", [v("D"), v("P"), v("M0"), v("H")]),
                s("$select_best", [
                  v("T"),
                  v("P"),
                  v("D"),
                  v("M0"),
                  v("K0"),
                  v("I1"),
                  v("M"),
                  v("K")
                ])
              ]),
              s("$select_best", [v("T"), v("P"), v("D"), v("H"), v("I"), v("I1"), v("M"), v("K")])
            ])
          ]
        ),
        rule(s("$keeps", [a("max"), v("P"), v("M0"), v("H")]), [
          s("call", [v("P"), v("H"), v("M0")])
        ]),
        rule(s("$keeps", [a("min"), v("P"), v("M0"), v("H")]), [
          s("call", [v("P"), v("M0"), v("H")])
        ]),
        rule(s("$delete_nth0", [0, [v("_") | v("T")], v("R")]), [a("!"), s("=", [v("R"), v("T")])]),
        rule(s("$delete_nth0", [v("K"), [v("H") | v("T")], [v("H") | v("R")]]), [
          s("is", [v("K1"), s("-", [v("K"), 1])]),
          s("$delete_nth0", [v("K1"), v("T"), v("R")])
        ]),
        rule(s("convlist", [v("P"), v("Xs"), v("Ys")]), [
          s("$convlist", [v("Xs"), v("P"), v("Ys")])
        ]),
        fact(s("$convlist", [[], v("_"), []])),
        rule(s("$convlist", [[v("X") | v("Xs")], v("P"), v("Ys")]), [
          s(";", [
            s("->", [s("call", [v("P"), v("X"), v("Y")]), s("=", [v("Ys"), [v("Y") | v("Ys1")]])]),
            s("=", [v("Ys"), v("Ys1")])
          ]),
          s("$convlist", [v("Xs"), v("P"), v("Ys1")])
        ])
      ]
    }
  end
end
