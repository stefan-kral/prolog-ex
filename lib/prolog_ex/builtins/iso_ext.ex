defmodule PrologEx.Builtins.IsoExt do
  @moduledoc """
  `library(iso_ext)` wie Scryer: Erweiterungen, die nicht zu ISO gehören.
  Die meisten sind eingebaut und werden nur weitergegeben (siehe
  `PrologEx.Builtins`, Heimat und Re-Exporte): `forall/2`, `succ/2`,
  `setup_call_cleanup/3`, `call_cleanup/2`, `call_nth/2`, `countall/2`,
  `call_with_inference_limit/3`, `call_residue_vars/2`, `bb_get/2`,
  `bb_put/2`. Hier dazu `copy_term_nat/2` und `copy_term/3` wie Scryer:
  die Restziele als Liste (eingebaut ist copy_term/3 wie SICStus, mit
  einer Konjunktion).
  """
  use PrologEx.Builtin, module: "iso_ext"

  def library do
    import PrologEx, only: [s: 2, v: 1, a: 1, rule: 2]
    [t, c, gs, vs, l, r] = [v("T"), v("C"), v("Gs"), v("Vs"), v("L"), v("R")]

    [
      # copy_term/2 kopiert Attribute ohnehin nicht mit (wie copy_term_nat)
      rule(s("copy_term_nat", [t, c]), [s("copy_term", [t, c])]),
      # copy_term(T, Copy, Gs) wie Scryer (und SWI): Gs ist eine Liste von
      # Zielen. Eingebaut ist copy_term/3 wie SICStus (ein Rumpf, eine
      # Konjunktion); wer library(iso_ext) lädt, bekommt diese Fassung.
      # Wie dort in findall/3: Restziele mancher Module bauen dabei
      # Attribute ab – das Original bleibt so unberührt.
      rule(s("copy_term", [t, c, gs]), [
        # wie Scryer: can_be(list, Gs)
        s("$skip_list", [v("_"), gs, r]),
        s(";", [
          s("->", [s(";", [s("var", [r]), s("==", [r, []])]), a("true")]),
          s("throw", [
            s("error", [s("type_error", [a("list"), gs]), s("/", [a("can_be"), 2])])
          ])
        ]),
        s("term_attvars", [t, vs]),
        s("term_variables", [t, v("Qs")]),
        s("findall", [s("-", [t, l]), s("$residuals", [vs, v("Qs"), l]), [s("-", [c, gs])]])
      ])
    ]
  end
end
