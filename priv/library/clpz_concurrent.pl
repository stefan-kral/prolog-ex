/* library(clpz_concurrent): labeling/2 von clpz parallel, mit
   library(concurrent) (PrologEx)

     concurrent_labeling(+Options, +Vars)
     concurrent_labeling(+Options, +Vars, +COptions)
         wie once(labeling(Options, Vars)): dieselbe Lösung – die erste in
         der Reihenfolge der Suche –, die Suche parallel (siehe unten);
         scheitert, wenn es keine gibt
     concurrent_labelings(+Options, +Vars, -Solutions)
     concurrent_labelings(+Options, +Vars, -Solutions, +COptions)
         alle Lösungen als Liste von Wertelisten (wie findall(Vars,
         labeling(Options, Vars), Solutions)), in derselben Reihenfolge;
         die Teile laufen parallel (concurrent_maplist/3)

   COptions: serial(S) – concurrent_labeling: so viele Sekunden erst
   nacheinander (die Suche bzw. ein Schritt des Branch and Bound), bevor
   parallel gerechnet wird (Vorgabe 0.1; 0: gleich parallel); kleine
   Aufgaben sparen so das Aufsetzen der Kinder. parts(N) – in etwa so
   viele Teile: Vorgabe 16 für concurrent_labelings (concurrent_maplist/3
   verteilt sie auf die Kerne); für concurrent_labeling die Zahl der
   Arbeiter, Vorgabe so viele wie Kerne (Flag cpu_count). concurrent_labelings: serial(S) ebenso (alle Lösungen
   nacheinander); weniger als 4 feste Teile je Kern: Work Stealing dazu
   (siehe optimise_all/6). solution(first) (Vorgabe) oder solution(any) –
   concurrent_labeling ohne min/max: any lässt feste Teile gegeneinander
   laufen, die erste gefundene Lösung gilt (welche, hängt von der Zeit ab,
   wie first_solution/3). steal(S) – siehe unten (Vorgabe 0.02).

   Variablen mit Constraints dürfen nicht in die Kinder von
   library(concurrent) (representation_error(concurrent_attributed_variable)).
   Darum: copy_term/3 macht aus Vars frische Variablen und Ziele, die die
   Constraints wieder aufsetzen (X in 1..9, X #\= Y, ...); jedes Kind setzt
   sie auf, nimmt seinen Teil und sucht dort mit labeling/2. Ergebnisse
   sind Zahlen.

   Die Teile entstehen im Aufrufer aus den ersten Entscheidungen, die
   labeling/2 selbst träfe (dieselbe Variablenwahl, dieselben Werte, mit
   Propagation): bei step X = V oder X #\= V, bei enum X = V je Wert (bei
   großen Bereichen Abschnitte), bei bisect X #=< M oder X #> M. Ein Kind
   setzt die Entscheidungen seines Teils und ruft labeling(Options, Vs);
   die Teile hintereinander sind genau die Suche von labeling/2, die
   Lösungen kommen also in derselben Reihenfolge. Gescheiterte Teile fallen
   schon beim Aufteilen weg.

   Eine Lösung (concurrent_labeling ohne min/max): Work Stealing in der
   Reihenfolge der Suche. Ein Kind beginnt mit dem ganzen Raum; es sucht
   Entscheidung für Entscheidung wie labeling/2 (part_steal/5). Ist ein
   Arbeiter frei, bittet library(concurrent) das am weitesten links
   laufende Kind um Arbeit, und es gibt den rechten Zweig seines tiefsten
   offenen Knotens ab, der schon S Sekunden läuft (steal(S)): je tiefer,
   desto eher käme die Suche nacheinander dorthin; je älter, desto mehr
   Arbeit verspricht er. Die Teile bleiben in der Reihenfolge der Suche
   geordnet; hat ein Teil eine Lösung, fällt alles rechts davon weg, und
   sie gilt, sobald alles links davon gescheitert ist – also genau die
   Lösung von once(labeling/2). Gewinn: was links der Lösung liegt (die
   gescheiterten Teilbäume), rechnen die Kerne gemeinsam; Arbeit rechts
   davon ist vergeblich. Darum zwischen nichts und der Zahl der Kerne.

   Optimierung (min(Expr), max(Expr), auch mehrere: lexikographisch wie
   labeling/2):
     concurrent_labeling – genau die Lösung von once(labeling(Options,
         Vars)): je Kriterium der beste Wert durch Branch and Bound –
         nacheinander, solange ein Schritt billig ist (0,1 s), dann
         parallel mit Work Stealing und gemeinsamer Schranke: jede bessere
         Lösung schränkt sofort alle Teile ein (optimum/5). Die Lösung ist
         die erste mit dem besten Wert in der Reihenfolge der Suche, wie
         bei labeling/2
     concurrent_labelings – alle Lösungen in der Reihenfolge von labeling/2:
         nach dem Wert gruppiert (min aufsteigend, max absteigend), je Gruppe
         unter E #= Wert mit den übrigen Kriterien; kostet etwa zwei
         Durchgänge (erst die vorkommenden Werte, dann je Wert)

   Noch nicht: upto_in (domain_error(concurrent_labeling_option, upto_in)).

   Lohnend, wenn die Suche deutlich länger dauert als das Aufsetzen des
   Modells (jedes Kind setzt es neu auf).
*/

:- module(clpz_concurrent, [concurrent_labeling/2, concurrent_labeling/3,
                            concurrent_labelings/3, concurrent_labelings/4]).

:- use_module(library(clpz)).
:- use_module(library(concurrent)).
:- use_module(library(lists)).
:- use_module(library(error)).
:- use_module(library(time)).

concurrent_labeling(Options, Vars) :-
    concurrent_labeling(Options, Vars, []).

concurrent_labeling(Options, Vars, COptions) :-
    check(Options, Vars, COptions, Spec, Whats, Parts0),
    (   Whats == []
    ->  current_prolog_flag(cpu_count, Cores),
        parts(Parts0, Cores, N),
        solution_mode(COptions, Mode),
        (   Mode == any
        ->  race_first(Spec, Vars, N)
        ;   serial_limit(COptions, Limit),
            steal_age(COptions, Age),
            ordered_first(Spec, Vars, N, Limit, Age)
        )
    ;   current_prolog_flag(cpu_count, Cores),
        parts(Parts0, Cores, N),
        serial_limit(COptions, Limit),
        steal_age(COptions, Age),
        optimise_first(Whats, Spec, Vars, opt(N, Limit, Age))
    ).

% serial(Sekunden): wie lange die Suche (ein Schritt des Branch and Bound)
% nacheinander laufen darf, bevor parallel gerechnet wird (0: gleich
% parallel)
serial_limit(COptions, Limit) :-
    seconds(serial, COptions, 0.1, Limit).

% steal(Sekunden): so alt muss ein Knoten sein, dessen rechter Zweig ein
% Kind abgibt; in µs
steal_age(COptions, Age) :-
    seconds(steal, COptions, 0.02, S),
    (   integer(S) -> Age is S * 1000000 ; Age is round(S * 1000000) ).

seconds(Name, COptions, Default, S) :-
    functor(O, Name, 1),
    (   memberchk(O, COptions)
    ->  arg(1, O, S),
        (   var(S) -> instantiation_error(S)
        ;   \+ number(S) -> type_error(number, S)
        ;   S < 0 -> domain_error(not_less_than_zero, S)
        ;   true
        )
    ;   S = Default
    ).

% solution(first | any)
solution_mode(COptions, Mode) :-
    (   memberchk(solution(Mode), COptions)
    ->  (   var(Mode) -> instantiation_error(Mode)
        ;   Mode == first -> true
        ;   Mode == any -> true
        ;   domain_error(solution, Mode)
        )
    ;   Mode = first
    ).

concurrent_labelings(Options, Vars, Solutions) :-
    concurrent_labelings(Options, Vars, Solutions, []).

concurrent_labelings(Options, Vars, Solutions, COptions) :-
    check(Options, Vars, COptions, Spec, Whats, Parts0),
    parts(Parts0, 16, N),
    current_prolog_flag(cpu_count, W),
    serial_limit(COptions, Limit),
    steal_age(COptions, Age),
    optimise_all(Whats, Spec, Vars, N, all(W, Limit, Age), Solutions).

parts(none, Default, Default) :- !.
parts(N, _, N).

% --- eine Lösung ---------------------------------------------------------------

% ohne Optimierung: die Teile gegeneinander, die erste gefundene gilt
race_first(Spec, Vars, N) :-
    pieces(Spec, Vars, N, Parts, Vs, Gs),
    Parts \== [],
    base(Spec, Base),
    first_goals(Parts, Gs, Vs, Base, Sol, Goals),
    first_solution(Sol, Goals, [on_fail(continue)]),
    Vars = Sol.

% die erste Lösung in der Reihenfolge der Suche: erst nacheinander (bis
% Limit), dann parallel – ein Teil am Anfang, die Kinder geben auf Bitte
% Teile ab (part_steal/5, '$conc_run'/7 mit split)
ordered_first(Spec, Vars, W, Limit, Age) :-
    base(Spec, Base),
    (   serial_try(Limit, Vars, once(labeling(Base, Vars)), Sols)
    ->  Sols = [Vars]
    ;   split_first(Base, Vars, W, Age)
    ).

split_first(Base, Vars, W, Age) :-
    copy_term(Vars, Vs, Gs0),
    goal_conj(Gs0, Gs),
    '$conc_limits'(D, B, M),
    '$conc_run'([Vs-(clpz_concurrent:part_steal(Gs, Vs, Base, Age))], split, W, D, B, M, R),
    R = ok([Vars]).

% je Teil ein Ziel; alle mit demselben Sol (findall/3 kopierte es)
first_goals([], _, _, _, _, []).
first_goals([Ds|Dss], Gs, Vs, Base, Sol, [part_first(Gs, Vs, Base, Ds, Sol)|Goals]) :-
    first_goals(Dss, Gs, Vs, Base, Sol, Goals).

% mit min(E)/max(E), wie once(labeling(Options, Vars)): je Kriterium der
% Reihe nach den besten Wert bestimmen und festhalten (E #= Wert); die
% Lösung ist die, mit der das letzte Kriterium sein Optimum fand – die
% erste mit diesem Wert in der Reihenfolge der Suche (siehe optimum/6)
optimise_first([W|Ws], Spec, Vars, How) :-
    optimum(W, Spec, Vars, How, Val-Sol),
    (   Ws == []
    ->  Vars = Sol
    ;   arg(1, W, E),
        E #= Val,
        optimise_first(Ws, Spec, Vars, How)
    ).

% Branch and Bound wie labeling/2: eine Lösung unter der bisherigen
% Schranke suchen (E #< Best bzw. E #> Best), ihr Wert ist die neue
% Schranke, bis es keine mehr gibt. Erst nacheinander im Aufrufer, solange
% ein Schritt billig ist (Frist Limit, Vorgabe 0,1 s); braucht einer länger
% (gegen Ende: die Lösungen werden selten, zuletzt muss bewiesen werden,
% dass es keine bessere gibt), dann der Rest parallel (steal_best/7): W
% Arbeiter, Work Stealing, eine gemeinsame Schranke – jede bessere Lösung
% eines Teils schränkt sofort alle anderen ein. Jeder Teil sucht ohne
% Neustart weiter (part_steal_best/8); sein Ergebnis ist die erste beste
% Lösung in ihm, und von allen gilt die beste, bei gleichem Wert die erste
% in der Reihenfolge der Suche. (Erst probiert: je Schritt die erste Lösung
% unter der Schranke parallel suchen – das Aufsetzen je Schritt fraß den
% Gewinn: 9 Damen 5,6 statt 3,5 s nacheinander.)
%
% Ergebnis Wert-Lösung. Die Lösung ist die erste mit dem besten Wert in der
% Reihenfolge der Suche, wie bei labeling/2: der letzte Schritt fand die
% erste Lösung, die besser war als die vorige Schranke – jede mit dem
% besten Wert ist besser, also keine davor. Scheitert ohne Lösung.
optimum(W, Spec, Vars, How, Best) :-
    optimum_(W, Spec, Vars, How, none, Best).

optimum_(W, Spec, Vars, How, Best0, Best) :-
    How = opt(N, Limit, Age),
    (   serial_step(W, Spec, Vars, Best0, Limit, Found)
    ->  (   Found == none
        ->  Best0 \== none, Best = Best0
        ;   optimum_(W, Spec, Vars, How, Found, Best)
        )
    ;   steal_best(W, Spec, Vars, Best0, N, Age, Best),
        Best \== none
    ).

% ein Schritt nacheinander: Found ist Wert-Lösung der ersten Lösung unter
% der Schranke oder none; scheitert, wenn die Frist abläuft
serial_step(W, Spec, Vars, Bound, Limit, Found) :-
    W =.. [Dir, E],
    base(Spec, Base),
    bound_value(Bound, B),
    serial_try(Limit, V-Vars, ( bound(Dir, E, B), once(labeling(Base, Vars)), value(E, V) ), Vs),
    ( Vs = [Found] -> true ; Found = none ).

% der Rest parallel: Branch and Bound mit Work Stealing und gemeinsamer
% Schranke (part_steal_best/8); Best: Wert-Lösung oder Bound
steal_best(W, Spec, Vars, Bound, N, Age, Best) :-
    W =.. [Dir, E],
    base(Spec, Base),
    bound_value(Bound, B),
    findall(Sol,
            ( Ev #= E,
              copy_term(Vars-Ev, Vs-EvC, Gs0),
              goal_conj(Gs0, Gs),
              '$conc_limits'(D, Bu, M),
              '$conc_run'([x-(clpz_concurrent:part_steal_best(Gs, Vs-EvC, Base, Age, Dir, B))],
                          split_best(Dir), N, D, Bu, M, R),
              R = ok([Sol]) ),
            Sols),
    (   Sols = [V-S] -> Best = V-S ; Best = Bound ).

bound_value(none, none).
bound_value(V-_, V).

% findall(T, Goal, R) höchstens Limit Sekunden (ohne Bindungen im
% Aufrufer); scheitert, wenn die Frist abläuft
serial_try(Limit, T, Goal, R) :-
    Limit > 0,
    catch(call_with_time_limit(Limit, findall(T, Goal, R)), time_limit_exceeded, fail).

bound(_, _, none) :- !.
bound(min, E, B) :- E #< B.
bound(max, E, B) :- E #> B.

% --- alle Lösungen ---------------------------------------------------------------

% ohne Optimierung: alle Teile, hintereinander. Mit min(E)/max(E) wie
% labeling/2: gruppiert nach dem Wert von E (aufsteigend bzw. absteigend),
% je Gruppe die Lösungen unter E #= Wert mit den übrigen Kriterien – erst
% alle vorkommenden Werte (ein Durchgang), dann je Wert einer
% ohne min/max: erst nacheinander (bis Limit), dann parallel in N festen
% Teilen für W Arbeiter. Sind es mindestens 4 je Arbeiter, gleicht
% concurrent_maplist/3 sie aus (jeder mit labeling/2, part_all/5);
% sonst (viele Kerne) wartete am Ende jeder auf den größten: dann holen
% sich freie Arbeiter, wenn kein fester Teil mehr wartet, Arbeit aus den
% laufenden (Work Stealing, part_steal_all/6). Das kostet die eigene
% Schleife (7–25 % gegenüber labeling/2), darum nicht immer
optimise_all([], Spec, Vars, N, all(W, Limit, Age), Sols) :-
    base(Spec, Base),
    (   serial_try(Limit, Vars, labeling(Base, Vars), Sols0)
    ->  Sols = Sols0
    ;   pieces(Spec, Vars, N, Parts, Vs, Gs),
        length(Parts, NP),
        (   NP >= 4 * W
        ->  concurrent_maplist(part_all(Gs, Vs, Base), Parts, Sols1),
            append(Sols1, Sols)
        ;   '$conc_limits'(D, B, M),
            '$conc_run'([Vs-(clpz_concurrent:part_steal_all(Gs, Vs, Base, Age))|Parts],
                        split_all, W, D, B, M, R),
            R = ok(Sols)
        )
    ).
optimise_all([W|Ws], Spec, Vars, N, How, Sols) :-
    W =.. [Dir, E],
    pieces_t(Spec, Vars-E, Vars, N, Parts, Vs-EV, Gs),
    base(Spec, Base),
    concurrent_maplist(part_values(Gs, Vs, Base, EV), Parts, Vals0),
    append(Vals0, Vals1),
    sort(Vals1, Asc),
    ( Dir == min -> Vals = Asc ; reverse(Asc, Vals) ),
    findall(S, ( member(V, Vals),
                 findall(S0, ( E #= V, optimise_all(Ws, Spec, Vars, N, How, S0) ), [S]) ),
            Groups),
    append(Groups, Sols).

% --- in den Kindern --------------------------------------------------------------

% (Base: die Optionen ohne min/max, [Auswahl, Reihenfolge, Verzweigung])
part_first(Gs, Vs, Base, Ds, Vs) :-
    call(Gs),
    decide(Ds, Vs, Pre),
    once(( pre_label(Pre), labeling(Base, Vs) )).

% part_steal_best(Gs, Vs-Ev, Base, Age, Dir, B0, Ds, Res): Branch and
% Bound in Teil Ds ohne Neustart: die Suche läuft weiter, jede bessere
% Lösung wird die eigene Schranke (echt besser), und an jedem Knoten gilt
% die engste aus ihr, B0 (die Schranke vor dieser Phase, echt) und der
% besten anderer Teile ('$conc_bound', einschließlich: bei gleichem Wert
% entscheidet die Reihenfolge der Teile). Das ergibt dieselbe Lösung wie
% Neustarts: rechts der letzten Lösung sucht auch ein Neustart nur dort.
% Res: none oder best(Wert, Lösung, K) – die erste beste dieses Teils, K
% abgegebene Teile lagen davor (zusammengesetzt von '$conc_run'/7 mit
% split_best)
part_steal_best(Gs, Vs-Ev, Base, Age, Dir, B0, Ds, Res) :-
    call(Gs),
    '$conc_best_init'(Dir, B0),
    (   decide(Ds, Vs, Pre)
    ->  Base = [S, O, C],
        E = env(Vs, Ds, S, O, C, Age, all, best(Ev, Dir)),
        (   steal_pre(Pre, E),
            best_leaf(Ev, Dir, Vs),
            fail
        ;   true
        )
    ;   true
    ),
    '$conc_best_result'(Res).

best_leaf(Ev, Dir, Vs) :-
    (   integer(Ev) -> true ; instantiation_error(Ev) ),
    '$conc_best_limit'(L),
    (   L == none -> true
    ;   Dir == min -> Ev =< L
    ;   Ev >= L
    ),
    '$conc_best_put'(Ev, Vs).

part_all(Gs, Vs, Base, Ds, Sols) :-
    call(Gs),
    (   decide(Ds, Vs, Pre)
    ->  findall(Vs, ( pre_label(Pre), labeling(Base, Vs) ), Sols)
    ;   Sols = []
    ).

% --- im Kind: Labeling, das Teile abgibt ---------------------------------------
%
% part_steal(Gs, Vs, Base, Age, Ds): wie once(labeling(Base, Vs)) im Teil Ds,
% Entscheidung für Entscheidung wie labeling/2 (step mit
% '$clpz_label_step'/4, sonst die Auswahl von label/5 und die Wahl von
% choice_order_variable/7) – jede Wahl ist ein Knoten (links ; rechts).
% An jedem Knoten: bittet der Elternprozess um Arbeit, gibt das Kind den
% obersten noch offenen rechten Zweig ab – als Entscheidungen Ds ++ Pfad
% bis dorthin ++ [rechts] – und überspringt ihn später selbst. Der
% abgegebene Teil liegt in der Reihenfolge der Suche rechts von allem,
% was das Kind noch tut, und links von dem, was es früher abgab.
%
% Pfad P (tiefster vorn): o(Tiefe, Links, Rechts) für einen Knoten, in
% dessen linkem Zweig die Suche ist, sonst die getroffene Entscheidung.
% Entscheidungen mit dem Index der Variablen (gebundene erkennt man nicht
% wieder); ein Rest von enum ist range(I, L, H, O): X erst in Reihenfolge
% O, wie enum (decide/3, pre_label/1)
part_steal(Gs, Vs, Base, Age, Ds) :-
    call(Gs),
    decide(Ds, Vs, Pre),
    Base = [S, O, C],
    E = env(Vs, Ds, S, O, C, Age, first, none),
    catch(once(steal_pre(Pre, E)), '$conc_steal_stop', fail).

% part_steal_all(Gs, Vs, Base, Age, Ds, Sols): alle Lösungen des Teils Ds
% wie findall(Vs, labeling(Base, Vs), _), je als K-Lösung: K abgegebene
% Teile lagen davor ('$conc_steal_skipped'/1; '$conc_run'/7 mit split_all
% fügt sie in der Reihenfolge der Suche zusammen). Abgegeben wird hier der
% oberste offene Zweig (der größte: alle Arbeit zählt, je weniger Teile,
% desto weniger Aufsetzen)
part_steal_all(Gs, Vs, Base, Age, Ds, Sols) :-
    call(Gs),
    (   decide(Ds, Vs, Pre)
    ->  Base = [S, O, C],
        E = env(Vs, Ds, S, O, C, Age, all, none),
        findall(K-Vs, ( steal_pre(Pre, E), '$conc_steal_skipped'(K) ), Sols)
    ;   Sols = []
    ).

steal_pre(none, E) :-
    arg(1, E, Vs),
    slabel(Vs, E, [], 0).
steal_pre(pre(O, X), E) :-
    spre(X, O, E, [], 0).

% wie labeling([O], [X]), dann labeling(Base, Vs)
spre(X, O, E, P, D) :-
    (   integer(X)
    ->  arg(1, E, Vs),
        slabel(Vs, E, P, D)
    ;   clpz:fd_get(X, Dom, _),
        clpz:order_dom_next(O, Dom, V),
        arg(1, E, Vs),
        '$conc_node'(Vs, X, I, T, Req),
        steal_poll(Req, E, P, D, T),
        D1 is D + 1,
        (   X = V,
            spre(X, O, E, [o(D1, eq(I, V), neq(I, V), T)|P], D1)
        ;   '$conc_kept'(D1),
            clpz:neq_num(X, V),
            spre(X, O, E, [neq(I, V)|P], D1)
        )
    ).

slabel(Vars, E, P, D) :-
    arg(5, E, C),
    (   C == step
    ->  sstep(Vars, E, P, D)
    ;   arg(3, E, S),
        spick(Vars, S, X, RVars, Vars0)
    ->  (   C == enum
        ->  senum(X, RVars, E, P, D)
        ;   sbisect(X, Vars0, E, P, D)
        )
    ;   true
    ).

% label/5 mit step (wie label_step/3)
sstep(Vars, E, P, D) :-
    arg(3, E, S),
    arg(4, E, O),
    '$clpz_label_step'(Vars, S, O, Step),
    (   Step == done
    ->  true
    ;   Step = step(X, V, RVars, Vars0),
        arg(1, E, Vs),
        '$conc_node'(Vs, X, I, T, Req),
        steal_poll(Req, E, P, D, T),
        D1 is D + 1,
        (   X = V,
            sstep(RVars, E, [o(D1, eq(I, V), neq(I, V), T)|P], D1)
        ;   '$conc_kept'(D1),
            clpz:neq_num(X, V),
            sstep(Vars0, E, [neq(I, V)|P], D1)
        )
    ).

% die Auswahl von label_ref/5: X, der Rest ohne X und die Liste, aus der
% gewählt wurde; scheitert, wenn alle gebunden sind
spick([V|Vs], S, X, RVars, Vars0) :-
    (   nonvar(V)
    ->  spick(Vs, S, X, RVars, Vars0)
    ;   clpz:select_var(S, [V|Vs], X0, R0),
        (   var(X0)
        ->  X = X0, RVars = R0, Vars0 = [V|Vs]
        ;   spick(R0, S, X, RVars, Vars0)
        )
    ).

% enum: die Werte der Domäne in Reihenfolge O (domain_direction_element/3),
% je Wert ein Knoten; rechts der Rest als range(I, L, H, O)
senum(X, RVars, E, P, D) :-
    arg(4, E, O),
    clpz:fd_get(X, Dom, _),
    clpz:domain_intervals(Dom, Is0),
    Is0 = [Inf-_|_],
    last(Is0, _-Sup),
    (   O == up -> Is = Is0, Lim = Sup ; reverse(Is0, Is), Lim = Inf ),
    arg(1, E, Vs),
    '$conc_var_index'(Vs, X, I),
    D1 is D + 1,
    senum_(Is, O, Lim, X, I, RVars, E, P, D1).

senum_([F-U|Is], O, Lim, X, I, RVars, E, P, D) :-
    integer(F), integer(U),
    (   O == up -> V = F ; V = U ),
    (   F =:= U -> Rest = Is
    ;   O == up -> F1 is F + 1, Rest = [F1-U|Is]
    ;   U1 is U - 1, Rest = [F-U1|Is]
    ),
    (   Rest == []
    ->  X = V,
        slabel(RVars, E, [eq(I, V)|P], D)
    ;   (   O == up -> Rest = [L1-_|_], R = range(I, L1, Lim, up)
        ;   Rest = [_-H1|_], R = range(I, Lim, H1, down)
        ),
        '$conc_steal_node'(T, Req),
        steal_poll(Req, E, P, D, T),
        (   X = V,
            slabel(RVars, E, [o(D, eq(I, V), R, T)|P], D)
        ;   '$conc_kept'(D),
            senum_(Rest, O, Lim, X, I, RVars, E, P, D)
        )
    ).

% bisect wie choice_order_variable/7
sbisect(X, Vars0, E, P, D) :-
    clpz:fd_get(X, Dom, _),
    clpz:domain_infimum(Dom, L), integer(L),
    clpz:domain_supremum(Dom, H), integer(H),
    M0 is (L + H) // 2,
    (   M0 =:= H -> M is M0 - 1 ; M = M0 ),
    arg(1, E, Vs),
    '$conc_node'(Vs, X, I, T, Req),
    arg(4, E, O),
    (   O == up -> A = le(I, M), B = gt(I, M) ; A = gt(I, M), B = le(I, M) ),
    steal_poll(Req, E, P, D, T),
    D1 is D + 1,
    (   bisect_side(A, X),
        slabel(Vars0, E, [o(D1, A, B, T)|P], D1)
    ;   '$conc_kept'(D1),
        bisect_side(B, X),
        slabel(Vars0, E, [B|P], D1)
    ).

bisect_side(le(_, M), X) :- X #=< M.
bisect_side(gt(_, M), X) :- X #> M.

% je Knoten: T die Zeit (µs; außerhalb eines teilenden Kinds 0). Bittet
% der Elternprozess um Arbeit: den tiefsten offenen, noch nicht
% abgegebenen rechten Zweig, dessen Knoten schon Age µs läuft (je
% tiefer, desto eher käme die Suche nacheinander dorthin; je älter der
% Knoten, desto mehr Arbeit verspricht sein rechter Zweig), sonst none
% (Schnellweg: keine Bitte, kein Branch and Bound)
steal_poll(no, E, _, _, _) :-
    arg(8, E, none),
    !.
steal_poll(Req, E, P, Depth, T) :-
    (   best_check(E)
    ->  true
    ;   % der Knoten fällt weg (Schranke): eine Bitte noch beantworten
        ( Req == yes -> '$conc_steal_offer'(none) ; true ),
        fail
    ),
    (   Req == no
    ->  true
    ;   Req == stop
    ->  throw('$conc_steal_stop')
    ;   arg(6, E, A),
        Old is T - A,
        arg(7, E, Pick),
        (   steal_pick(Pick, P, Depth, Old, D, Ds1, R)
        ->  arg(2, E, Ds0),
            append(Ds0, Ds1, Ds2),
            append(Ds2, [R], Ds),
            '$conc_steal_give'(D, Ds)
        ;   '$conc_steal_offer'(none)
        )
    ).

% Branch and Bound (part_steal_best/8): hält E die Schranke nicht mehr ein,
% fällt der Knoten weg; sonst wird sie hier für den Teilbaum gesetzt
% ('$conc_best_limit'/1: die engste der Schranken, einschließlich)
best_check(E) :-
    arg(8, E, Best),
    (   Best == none
    ->  true
    ;   Best = best(Ev, Dir),
        '$conc_best_limit'(L),
        (   L == none
        ->  true
        ;   Dir == min
        ->  fd_inf(Ev, I), I =< L,
            ( fd_sup(Ev, S), S > L -> Ev #=< L ; true )
        ;   fd_sup(Ev, S), S >= L,
            ( fd_inf(Ev, I), I < L -> Ev #>= L ; true )
        )
    ).

% der abzugebende Knoten der Tiefe D: R sein rechter Zweig, Ds1 die
% Entscheidungen darüber (oberste zuerst). first: der tiefste alte aus der
% unteren Hälfte des Pfads; all: der oberste alte
steal_pick(first, P, Depth, Old, D, Ds1, R) :-
    Min is Depth // 2,
    give(P, Old, Min, D, Above, R),
    reverse(Above, Ds1).
steal_pick(all, P, _, Old, D, Ds1, R) :-
    reverse(P, Ps),
    give_top(Ps, Old, D, Ds1, R).

% Ps oberster vorn
give_top([N|Ns], Old, D, Above, R) :-
    (   N = o(D0, L, R0, T0)
    ->  (   T0 =< Old,
            \+ '$conc_steal_marked'(D0)
        ->  D = D0, R = R0, Above = []
        ;   Above = [L|Above1],
            give_top(Ns, Old, D, Above1, R)
        )
    ;   Above = [N|Above1],
        give_top(Ns, Old, D, Above1, R)
    ).

% P tiefster vorn; Above: die Entscheidungen darüber (tiefste vorn)
give([N|Ns], Old, Min, D, Above, R) :-
    (   N = o(D0, _, R0, T0)
    ->  D0 >= Min,
        (   T0 =< Old,
            \+ '$conc_steal_marked'(D0)
        ->  D = D0, R = R0, path_decisions(Ns, Above)
        ;   give(Ns, Old, Min, D, Above, R)
        )
    ;   give(Ns, Old, Min, D, Above, R)
    ).

path_decisions([], []).
path_decisions([N|Ns], [X|Xs]) :-
    (   N = o(_, L, _, _) -> X = L ; X = N ),
    path_decisions(Ns, Xs).

% die Werte von E über alle Lösungen des Teils
part_values(Gs, Vs, Base, EV, Ds, Vals) :-
    call(Gs),
    (   decide(Ds, Vs, Pre)
    ->  findall(V, ( pre_label(Pre), labeling(Base, Vs), value(EV, V) ), Vals)
    ;   Vals = []
    ).

% wie labeling/2: nach dem Labeling muss E feststehen
value(EV, V) :-
    V #= EV,
    (   integer(V) -> true ; instantiation_error(EV) ).

% Entscheidungen setzen; Pre: none oder bei einem Abschnitt von enum
% pre(O, X): erst X in Reihenfolge O, dann der Rest – wie enum
decide(Ds, Vs, Pre) :-
    decide_(Ds, Vs, none, Pre).

pre_label(none).
pre_label(pre(O, X)) :- labeling([O], [X]).

decide_([], _, Pre, Pre).
decide_([D|Ds], Vs, Pre0, Pre) :-
    decision(D, Vs, Pre0, Pre1),
    decide_(Ds, Vs, Pre1, Pre).

decision(eq(I, V), Vs, P, P) :- nth1(I, Vs, X), X = V.
decision(neq(I, V), Vs, P, P) :- nth1(I, Vs, X), clpz:neq_num(X, V).
decision(le(I, M), Vs, P, P) :- nth1(I, Vs, X), X #=< M.
decision(gt(I, M), Vs, P, P) :- nth1(I, Vs, X), X #> M.
decision(range(I, L, H, O), Vs, _, pre(O, X)) :- nth1(I, Vs, X), X in L..H.

% --- im Aufrufer: prüfen und aufteilen ----------------------------------------------

% Prüfen wie labeling/2; Spec: spec(Auswahl, Reihenfolge, Verzweigung),
% Whats: die min/max-Kriterien in ihrer Reihenfolge; Parts: parts(N) oder
% none
check(Options, Vars, COptions, Spec, Whats, Parts) :-
    Goal = labeling(Options, Vars),
    must_be(list, Options),
    must_be(list, COptions),
    clpz:fd_must_be_list(Vars, Goal-2),
    maplist(clpz:finite_domain(Goal, 2), Vars),
    options(Options, Options, default(leftmost), default(up), default(step), Whats, Spec),
    (   memberchk(parts(N), COptions)
    ->  must_be(integer, N),
        ( N >= 1 -> true ; type_error(positive_integer, N) ),
        Parts = N
    ;   Parts = none
    ).

base(spec(S, O, C), [S, O, C]).

% Teile und die Kopie: Term wird kopiert (Vars oder Vars-E), Vars geteilt
pieces(Spec, Vars, N, Parts, Vs, Gs) :-
    pieces_t(Spec, Vars, Vars, N, Parts, Vs, Gs).

pieces_t(Spec, Term, Vars, N, Parts, Copy, Gs) :-
    split(Spec, Vars, N, Parts),
    copy_term(Term, Copy, Gs0),
    goal_conj(Gs0, Gs).

% copy_term/3 gibt die Ziele je nach Import als Liste (iso_ext, wie Scryer)
% oder als Konjunktion
goal_conj([], true) :- !.
goal_conj([G|Gs], (G, C)) :- !, goal_conj(Gs, C).
goal_conj(G, G).

options([], _, S, O, C, [], spec(S1, O1, C1)) :-
    maplist(arg(1), [S, O, C], [S1, O1, C1]).
options([X|Xs], Options, S, O, C, Ws, Spec) :-
    (   var(X) -> instantiation_error(X)
    ;   clpz:override(selection, S, X, Options, S1) -> options(Xs, Options, S1, O, C, Ws, Spec)
    ;   clpz:override(order, O, X, Options, O1) -> options(Xs, Options, S, O1, C, Ws, Spec)
    ;   clpz:override(choice, C, X, Options, C1) -> options(Xs, Options, S, O, C1, Ws, Spec)
    ;   X == upto_ground -> options(Xs, Options, S, O, C, Ws, Spec)
    ;   clpz:optimisation(X) -> Ws = [X|Ws1], options(Xs, Options, S, O, C, Ws1, Spec)
    ;   clpz:consistency(X, _) -> domain_error(concurrent_labeling_option, X)
    ;   domain_error(labeling_option, X)
    ).

% Teile als Listen von Entscheidungen, in der Reihenfolge der Suche: immer
% den größten offenen Teil (Suchraum: Summe der log(fd_size) seiner
% offenen Variablen nach Propagation) an seiner Stelle durch seine Kinder
% ersetzen, bis es genug sind. Bei step ist der Zweig X #\= V oft fast der
% ganze Raum – er wird dann gleich weiter geteilt; so werden die Teile
% ähnlich groß
split(Spec, Vars, N, Parts) :-
    node([], Vars, open, Root),
    MaxSteps is 8 * N,
    grow(Root, Spec, Vars, N, MaxSteps, Nodes),
    findall(Ds, ( member(node(_, _, Ds0), Nodes), reverse(Ds0, Ds) ), Parts).

grow(Root, Spec, Vars, N, Steps, Nodes) :-
    grow_([Root], Spec, Vars, N, Steps, Nodes).

grow_(Ns0, Spec, Vars, N, Steps, Ns) :-
    length(Ns0, K),
    (   K < N, Steps > 0, largest_open(Ns0, Big)
    ->  expand(Big, Spec, Vars, Children),
        replace(Ns0, Big, Children, Ns1),
        Steps1 is Steps - 1,
        grow_(Ns1, Spec, Vars, N, Steps1, Ns)
    ;   Ns = Ns0
    ).

largest_open(Ns, Big) :-
    findall(S-Nd, ( member(Nd, Ns), Nd = node(open, S, _), S > 0 ), Ss),
    Ss = [_|_],
    max_member(_-Big, Ss).

replace([N|Ns], Old, New, Out) :-
    (   N == Old -> append(New, Ns, Out)
    ;   Out = [N|Out1], replace(Ns, Old, New, Out1)
    ).

% Knoten node(open | final, Größe, Entscheidungen umgekehrt); scheitern
% die Entscheidungen schon durch Propagation: kein Knoten
node(Ds, Vars, Kind, node(Kind, S, Ds)) :-
    findall(S0, ( reverse(Ds, Ds1), decide(Ds1, Vars, _), log_size(Vars, 0, S0) ), [S]).

log_size([], S, S).
log_size([V|Vs], S0, S) :-
    (   var(V) -> fd_size(V, N), S1 is S0 + log(N) ; S1 = S0 ),
    log_size(Vs, S1, S).

expand(node(_, _, Ds), Spec, Vars, Children) :-
    findall(B, ( reverse(Ds, Ds1), decide(Ds1, Vars, _), branch(Spec, Vars, B) ), Bs),
    (   Bs = [] -> Children = []
    ;   Bs = [done] -> Children = [node(final, 0, Ds)]
    ;   Bs = [B],
        children(B, Ds, Cs),
        findall(Nd, ( member(Kind-Ds1, Cs), node(Ds1, Vars, Kind, Nd) ), Children)
    ).

children(step(I, V), Ds, [open-[eq(I, V)|Ds], open-[neq(I, V)|Ds]]).
children(enum(I, Vals), Ds, Cs) :-
    findall(open-[eq(I, V)|Ds], member(V, Vals), Cs).
children(ranges(I, Rs, O), Ds, Cs) :-
    findall(final-[range(I, L, H, O)|Ds], member(L-H, Rs), Cs).
children(bisect(I, M, up), Ds, [open-[le(I, M)|Ds], open-[gt(I, M)|Ds]]).
children(bisect(I, M, down), Ds, [open-[gt(I, M)|Ds], open-[le(I, M)|Ds]]).

% die erste Entscheidung, die labeling/2 hier träfe
branch(spec(S, O, C), Vars, B) :-
    (   next_var(S, Vars, X)
    ->  var_index(Vars, X, 1, I),
        branch_(C, O, X, I, B)
    ;   B = done
    ).

branch_(step, O, X, I, step(I, V)) :-
    clpz:fd_get(X, Dom, _),
    clpz:order_dom_next(O, Dom, V).
branch_(enum, O, X, I, B) :-
    fd_size(X, Size),
    (   Size =< 64
    ->  fd_dom(X, Dom),
        findall(V, ( V in Dom, labeling([O], [V]) ), Vals),
        B = enum(I, Vals)
    ;   fd_inf(X, L), fd_sup(X, H),
        chunks(L, H, 16, Rs0),
        ( O == up -> Rs = Rs0 ; reverse(Rs0, Rs) ),
        B = ranges(I, Rs, O)
    ).
branch_(bisect, O, X, I, bisect(I, M, O)) :-
    fd_inf(X, L), fd_sup(X, H),
    M0 is (L + H) // 2,
    ( M0 =:= H -> M is M0 - 1 ; M = M0 ).

% L..H in K etwa gleiche Abschnitte
chunks(L, H, K, Rs) :-
    W is max(1, (H - L + K) // K),
    chunks_(L, H, W, Rs).

chunks_(L, H, _, []) :- L > H, !.
chunks_(L, H, W, [L-E|Rs]) :-
    E is min(H, L + W - 1),
    L1 is E + 1,
    chunks_(L1, H, W, Rs).

% wie labeling/2: gebundene überspringen, dann select_var/4
next_var(S, Vars, X) :-
    Vars = [V|Vs],
    (   nonvar(V) -> next_var(S, Vs, X)
    ;   clpz:select_var(S, Vars, X0, RVars),
        ( var(X0) -> X = X0 ; next_var(S, RVars, X) )
    ).

var_index([V|Vs], X, I0, I) :-
    (   V == X -> I = I0
    ;   I1 is I0 + 1, var_index(Vs, X, I1, I)
    ).
