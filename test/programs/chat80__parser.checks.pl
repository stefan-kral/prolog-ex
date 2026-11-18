% chat_parser: der Parsebaum jeder der 16 Fragen (genau einer; Variablen
% als '$VAR'(N)). Erwartet: die Bäume aus SWI-Prolog 9 (Scryer gibt
% dieselben, siehe cross.sh)
% Parsebaum des I-ten Satzes (my_string/1), Variablen als '$VAR'(N):
% vergleichbar mit ==, portabel (nur term_variables/2)
tree(I, T) :-
    findall(X, my_string(X), Xs),
    nth_(I, Xs, X),
    determinate_say(X, T),
    term_variables(T, Vs),
    number_vars(Vs, 0).
nth_(1, [X|_], X) :- !.
nth_(I, [_|Xs], X) :- I > 1, J is I - 1, nth_(J, Xs, X).
number_vars([], _).
number_vars(['$VAR'(N)|Vs], N) :- M is N + 1, number_vars(Vs, M).

expect(chat_parser, x, [x]).
expect(tree(1, T), T, [whq('$VAR'(0),s(np(+(3,plu),np_head(int_det('$VAR'(0)),[],river),[]),verb(be,active,+(pres,fin),[],pos),[void],[]))]).
expect(tree(2, T), T, [q(s(np(+(3,sin),name(afghanistan),[]),verb(border,active,+(pres,fin),[],pos),[arg(dir,np(+(3,sin),name(china),[]))],[]))]).
expect(tree(3, T), T, [whq('$VAR'(0),s(np(+(3,sin),wh('$VAR'(0)),[]),verb(be,active,+(pres,fin),[],pos),[arg(dir,np(+(3,sin),name(capital),[]))],[pp(prep(of),np(+(3,sin),name(upper_volta),[]))]))]).
expect(tree(4, T), T, [whq('$VAR'(0),s(np(+(3,sin),name(largest),[]),verb(be,active,+(pres,fin),[],pos),[arg(dir,np(+(3,sin),name(country),[]))],[pp(prep(in),np('$VAR'(1),np_head(int_det('$VAR'(0)),[],place),[]))]))]).
expect(tree(5, T), T, [whq('$VAR'(0),s(np(+(3,sin),name(capital),[pp(poss,np(+(3,sin),np_head(int_det('$VAR'(0)),[],country),[]))]),verb(be,active,+(pres,fin),[],pos),[arg(dir,np(+(3,sin),name(london),[]))],[]))]).
expect(tree(6, T), T, [whq('$VAR'(0),s(np(+(3,plu),np_head(int_det('$VAR'(0)),[],country),[]),verb(be,active,+(pres,fin),[],pos),[arg(predicate,adj(european))],[]))]).
expect(tree(7, T), T, [whq('$VAR'(0),s(np(+(3,sin),np_head(det(the(sin)),[sup(most,adj(small)),adj(american)],country),[]),verb(be,active,+(pres,fin),[],pos),[arg(predicate,value(adj(large),wh('$VAR'(0))))],[]))]).
expect(tree(8, T), T, [whq('$VAR'(0),s(np(+(3,sin),wh('$VAR'(0)),[]),verb(be,active,+(pres,fin),[],pos),[arg(dir,np(+(3,sin),np_head(det(the(sin)),[],ocean),[conj(and,rel('$VAR'(1),s(np(+(3,sin),wh('$VAR'(1)),[]),verb(border,active,+(pres,fin),[],pos),[arg(dir,np(+(3,plu),np_head(generic,[adj(african)],country),[]))],[])),rel('$VAR'(2),s(np(+(3,sin),wh('$VAR'(2)),[]),verb(border,active,+(pres,fin),[],pos),[arg(dir,np(+(3,plu),np_head(generic,[adj(asian)],country),[]))],[])))]))],[]))]).
expect(tree(9, T), T, [whq('$VAR'(0),s(np(+(3,plu),wh('$VAR'(0)),[]),verb(be,active,+(pres,fin),[],pos),[arg(dir,np(+(3,sin),name(capitals),[]))],[pp(prep(of),np(+(3,plu),np_head(det(the(plu)),[],country),[reduced_rel('$VAR'(1),s(np(+(3,plu),wh('$VAR'(1)),[]),verb(border,active,inf,[prog],pos),[arg(dir,np(+(3,sin),name(baltic),[]))],[]))]))]))]).
expect(tree(10, T), T, [whq('$VAR'(0),s(np(+(3,plu),np_head(int_det('$VAR'(0)),[],country),[]),verb(border,passive,+(pres,fin),[],pos),[],[pp(prep(by),np(+(3,plu),np_head(quant(same,nb(2)),[],sea),[]))]))]).
expect(tree(11, T), T, [whq('$VAR'(0),s(np(+(3,sin),name(the),[]),verb(do,active,+(pres,fin),[],pos),[arg(ind,np(+(3,sin),name(danube),[])),arg(dir,np(+(3,sin),name(flow),[]))],[pp(prep(through),np(+(3,plu),np_head(quant(same,wh('$VAR'(0))),[],country),[]))]))]).
expect(tree(12, T), T, [whq('$VAR'(0),s(np(+(3,sin),wh('$VAR'(0)),[]),verb(be,active,+(pres,fin),[],pos),[arg(dir,np(+(3,sin),np_head(det(the(sin)),[adj(total)],area),[pp(prep(of),np(+(3,sin),name(countries),[])),conj(and,reduced_rel('$VAR'(1),s(np(+(3,sin),wh('$VAR'(1)),[]),verb(be,active,+(pres,fin),[],pos),[arg(predicate,pp(prep(southof),np(+(3,sin),name(equator),[])))],[])),reduced_rel('$VAR'(2),s(np(+(3,sin),wh('$VAR'(2)),[]),verb(be,active,+(pres,fin),[],neg),[arg(predicate,pp(prep(in),np(+(3,sin),name(australasia),[])))],[])))]))],[]))]).
expect(tree(13, T), T, [whq('$VAR'(0),s(np(+(3,sin),wh('$VAR'(0)),[]),verb(be,active,+(pres,fin),[],pos),[arg(dir,np(+(3,sin),np_head(det(the(sin)),[adj(average)],area),[pp(prep(of),np(+(3,sin),name(countries),[])),pp(prep(in),np(+(3,sin),np_head(det(each),[],continent),[]))]))],[]))]).
expect(tree(14, T), T, [q(s(there,verb(be,active,+(pres,fin),[],pos),[arg(dir,np(+(3,sin),np_head(quant(more,nb(1)),[],country),[pp(prep(in),np(+(3,sin),np_head(det(each),[],continent),[]))]))],[]))]).
expect(tree(15, T), T, [q(s(there,verb(be,active,+(pres,fin),[],pos),[arg(dir,np(+(3,sin),np_head(det(some),[],ocean),[rel('$VAR'(0),s(np(+(3,sin),wh('$VAR'(0)),[]),verb(border,active,+(pres,fin),[],neg),[arg(dir,np(+(3,sin),np_head(det(any),[],country),[]))],[]))]))],[]))]).
expect(tree(16, T), T, [whq('$VAR'(0),s(np(+(3,plu),wh('$VAR'(0)),[]),verb(be,active,+(pres,fin),[],pos),[arg(dir,np(+(3,plu),np_head(det(the(plu)),[],country),[rel('$VAR'(1),s(np(+(3,sin),np_head(det(a),[],river),[]),verb(flow,active,+(pres,fin),[],pos),[],[pp(prep(from),np(+(3,plu),wh('$VAR'(1)),[])),pp(prep(into),np(+(3,sin),name(black_sea),[]))]))]))],[]))]).
