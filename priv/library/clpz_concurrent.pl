/* library(clpz_concurrent): labeling/2 von clpz parallel, mit
   library(concurrent) (PrologEx)

     concurrent_labeling(+Options, +Vars)
     concurrent_labeling(+Options, +Vars, +COptions)
         wie labeling(Options, Vars), aber eine Lösung (det): die Teile des
         Suchraums laufen gegeneinander, die erste gefundene gilt – welche
         das ist, hängt von der Zeit ab (wie first_solution/3). Scheitert,
         wenn es keine gibt
     concurrent_labelings(+Options, +Vars, -Solutions)
     concurrent_labelings(+Options, +Vars, -Solutions, +COptions)
         alle Lösungen als Liste von Wertelisten (wie findall(Vars,
         labeling(Options, Vars), Solutions)), in derselben Reihenfolge;
         die Teile laufen parallel (concurrent_maplist/3)

   COptions: parts(N) – in etwa so viele Teile. Vorgabe: 16 für
   concurrent_labelings (concurrent_maplist/3 verteilt sie auf die Kerne);
   für concurrent_labeling so viele wie Kerne (Flag cpu_count): die Teile
   laufen dort alle zugleich – mehr Teile als Kerne teilten die Kerne
   auch dem Teil, der die Lösung bald fände, und die Suche würde langsamer
   als nacheinander (24 Damen ohne ff: 8 Teile auf 2 Kernen 138 s statt
   41 s).

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

   Noch nicht: die Optionen min(Expr), max(Expr) und upto_in
   (domain_error(concurrent_labeling_option, O)).

   Lohnend, wenn die Suche deutlich länger dauert als das Aufsetzen des
   Modells (jedes Kind setzt es neu auf).
*/

:- module(clpz_concurrent, [concurrent_labeling/2, concurrent_labeling/3,
                            concurrent_labelings/3, concurrent_labelings/4]).

:- use_module(library(clpz)).
:- use_module(library(concurrent)).
:- use_module(library(lists)).
:- use_module(library(error)).

concurrent_labeling(Options, Vars) :-
    concurrent_labeling(Options, Vars, []).

concurrent_labeling(Options, Vars, COptions) :-
    current_prolog_flag(cpu_count, Cores),
    prepare(Options, Vars, COptions, Cores, Parts, Vs, Gs),
    Parts \== [],
    first_goals(Parts, Gs, Vs, Options, Sol, Goals),
    first_solution(Sol, Goals, [on_fail(continue)]),
    Vars = Sol.

% je Teil ein Ziel; alle mit demselben Sol (findall/3 kopierte es)
first_goals([], _, _, _, _, []).
first_goals([Ds|Dss], Gs, Vs, Options, Sol, [part_first(Gs, Vs, Options, Ds, Sol)|Goals]) :-
    first_goals(Dss, Gs, Vs, Options, Sol, Goals).

concurrent_labelings(Options, Vars, Solutions) :-
    concurrent_labelings(Options, Vars, Solutions, []).

concurrent_labelings(Options, Vars, Solutions, COptions) :-
    prepare(Options, Vars, COptions, 16, Parts, Vs, Gs),
    concurrent_maplist(part_all(Gs, Vs, Options), Parts, Sols),
    append(Sols, Solutions).

% --- in den Kindern --------------------------------------------------------------

part_first(Gs, Vs, Options, Ds, Vs) :-
    call(Gs),
    decide(Ds, Vs, Pre),
    once(( pre_label(Pre), labeling(Options, Vs) )).

part_all(Gs, Vs, Options, Ds, Sols) :-
    call(Gs),
    (   decide(Ds, Vs, Pre)
    ->  findall(Vs, ( pre_label(Pre), labeling(Options, Vs) ), Sols)
    ;   Sols = []
    ).

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

prepare(Options, Vars, COptions, Default, Parts, Vs, Gs) :-
    Goal = labeling(Options, Vars),
    must_be(list, Options),
    must_be(list, COptions),
    clpz:fd_must_be_list(Vars, Goal-2),
    maplist(clpz:finite_domain(Goal, 2), Vars),
    options(Options, Options, default(leftmost), default(up), default(step), Spec),
    (   memberchk(parts(N), COptions)
    ->  must_be(integer, N),
        ( N >= 1 -> true ; type_error(positive_integer, N) )
    ;   N = Default
    ),
    split(Spec, Vars, N, Parts),
    copy_term(Vars, Vs, Gs0),
    goal_conj(Gs0, Gs).

% copy_term/3 gibt die Ziele je nach Import als Liste (iso_ext, wie Scryer)
% oder als Konjunktion
goal_conj([], true) :- !.
goal_conj([G|Gs], (G, C)) :- !, goal_conj(Gs, C).
goal_conj(G, G).

options([], _, S, O, C, spec(S1, O1, C1)) :-
    maplist(arg(1), [S, O, C], [S1, O1, C1]).
options([X|Xs], Options, S, O, C, Spec) :-
    (   var(X) -> instantiation_error(X)
    ;   clpz:override(selection, S, X, Options, S1) -> options(Xs, Options, S1, O, C, Spec)
    ;   clpz:override(order, O, X, Options, O1) -> options(Xs, Options, S, O1, C, Spec)
    ;   clpz:override(choice, C, X, Options, C1) -> options(Xs, Options, S, O, C1, Spec)
    ;   X == upto_ground -> options(Xs, Options, S, O, C, Spec)
    ;   ( clpz:optimisation(X) ; clpz:consistency(X, _) )
    ->  domain_error(concurrent_labeling_option, X)
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
