% alle Faelle wie in Logtalk erwartet (Ausnahme dcgs_bypass_02, siehe dort).
% Gegenprobe: SWI uebersetzt auch Pushback, das keine Liste ist
% (push_back_list_09, _10), Scryer auch [abc|xyz], p --> 3 und Pushback vor
% dem Kopf; der Entwurf fuer DCGs verlangt dort Fehler.
expect(wrong(Bad), Bad, [[]]).
% Logtalk examples/dcgs, dcgs_28/29
expect(cut_local2(Xs), Xs, [[1, 2, 3]]).
expect(cut_local3(Xs), Xs, [[1, 2, 3]]).
