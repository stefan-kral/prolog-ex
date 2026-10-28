defmodule PrologEx.Builtins.IsoExt do
  @moduledoc """
  `library(iso_ext)` wie Scryer: Erweiterungen, die nicht zu ISO gehören.
  Die meisten sind eingebaut und werden nur weitergegeben (siehe
  `PrologEx.Builtins`, Heimat und Re-Exporte): `forall/2`, `succ/2`,
  `setup_call_cleanup/3`, `call_cleanup/2`, `call_nth/2`, `countall/2`,
  `call_with_inference_limit/3`, `call_residue_vars/2`, `copy_term/3`,
  `bb_get/2`, `bb_put/2`. Hier dazu `copy_term_nat/2`.
  """
  use PrologEx.Builtin, module: "iso_ext"

  def library do
    import PrologEx, only: [s: 2, v: 1, rule: 2]
    [t, c] = [v("T"), v("C")]
    # copy_term/2 kopiert Attribute ohnehin nicht mit (wie copy_term_nat)
    [rule(s("copy_term_nat", [t, c]), [s("copy_term", [t, c])])]
  end
end
