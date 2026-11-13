:- use_module(library(iso_ext)).
:- use_module(library(swi)).
:- use_module(library(csv)).
:- use_module(library(lists)).
t(Rows, O) :- catch((with_output_to(codes(Cs), csv_write_stream(current_output, Rows, O)), R = ok(Cs)), error(E, _), R = err(E)), write(R), nl,
  ( phrase(csv(Rows, O), Cs2) -> write(Cs2) ; write(fail) ), nl.
go :- forall(c(Rows, O), t(Rows, O)).
c([row('é',x,'')], [separator(0'\t)]).
c([r(42,'q"q',42,12345678901234567890),r('b,c',12345678901234567890,'tab\tx',-3)], [separator(0'\t)]).
c([row(-3)], [separator(0';)]).
c([row('line\nbreak',-3,'semi;colon')], [separator(0'\t)]).
c([r(1.5),r(1.0e10,'','line\nbreak','b,c')], [separator(0';)]).
c([], []).
c([row(-3)], []).
c([], [separator(0';)]).
c([r(' sp ',1.0e10),r(1.5,[],42,'é')], []).
c([], [separator(0';)]).
c([r('line\nbreak','semi;colon',a),r('','é','é'),row(42)], [separator(0';)]).
c([r('tab\tx','é','é',1.0e10),row(-3,-3,'','line\nbreak')], []).
c([r(1.5,12345678901234567890),r(1.5,x,'b,c')], [separator(0'\t)]).
c([], []).
c([row('q"q','line\nbreak',' sp '),row('q"q','q"q'),row(x,1.5,a,'cr\rx')], [separator(0';)]).
c([], []).
c([r(a)], [separator(0'\t)]).
c([row(-3)], [separator(0';)]).
c([], [separator(0'\t)]).
c([r(a),row(42,-3,-3,x),row('line\nbreak',-3,1.0e10)], [separator(0';)]).
c([r('q"q',x),row('tab\tx','line\nbreak'),row(x,'cr\rx','cr\rx','é')], [separator(0'\t)]).
c([r('semi;colon',a,a),row('cr\rx'),r(1.5,'tab\tx')], []).
c([row([],1.0e10,42,'tab\tx'),row(42)], []).
c([row('q"q','line\nbreak',' sp '),r('semi;colon',1.0e10,'b,c'),row(x,'')], [separator(0';)]).
c([], [separator(0'\t)]).
c([row(12345678901234567890,42),r(42,12345678901234567890,'semi;colon',1.0e10),r(1.0e10,'line\nbreak',1.5,[])], []).
c([row('line\nbreak'),row(1.0e10,-3)], [separator(0';)]).
c([r('semi;colon','line\nbreak')], []).
c([row(1.0e10),row(1.0e10,a,'line\nbreak',[]),r(x,42)], []).
c([r('semi;colon',12345678901234567890,'tab\tx',a),r('é',42),row(42,' sp ',42)], [separator(0';)]).
c([], []).
c([r(1.5,'line\nbreak',' sp '),row(-3,'semi;colon','tab\tx',-3)], [separator(0'\t)]).
c([r(42),row(x,' sp ')], []).
c([row(x,-3,-3,'line\nbreak'),r('tab\tx',1.5,'semi;colon')], []).
c([], [separator(0'\t)]).
c([row([],42,'q"q'),r(-3,'',1.0e10,'cr\rx'),r('',[])], [separator(0';)]).
c([r(42,-3,a),r('q"q',12345678901234567890)], [separator(0'\t)]).
c([row('é','cr\rx'),r('',42)], [separator(0'\t)]).
c([r('é','line\nbreak')], []).
c([row('tab\tx',-3,'é')], [separator(0'\t)]).
c([row('','q"q','line\nbreak'),row('')], []).
c([row(' sp ',a,12345678901234567890,1.0e10),row(a,[],'q"q'),row('cr\rx','é')], [separator(0'\t)]).
c([r(' sp ',x,'cr\rx'),row(' sp ','line\nbreak')], [separator(0';)]).
c([row('line\nbreak')], []).
c([r('é','q"q',1.5,'tab\tx')], [separator(0';)]).
c([row(' sp '),r('tab\tx',' sp ')], []).
c([], []).
c([r('b,c','line\nbreak'),row(1.0e10,-3,'tab\tx',1.5)], [separator(0';)]).
c([row(x),r('','line\nbreak',a,42)], [separator(0'\t)]).
c([row('é',12345678901234567890),r('tab\tx','é','q"q',' sp ')], [separator(0';)]).
c([r(1.5,'b,c'),row(-3,1.0e10,-3),r(42)], [separator(0';)]).
c([r('',42),row(x,'semi;colon','semi;colon',x)], [separator(0'\t)]).
c([], []).
c([r('semi;colon','',a)], [separator(0'\t)]).
c([r('',12345678901234567890,1.5,a),row('cr\rx',1.5,'q"q',1.5),row([],-3)], []).
c([], [separator(0';)]).
c([r('tab\tx',1.5),row(12345678901234567890,'','b,c','é')], [separator(0'\t)]).
c([], [separator(0';)]).
c([r('é')], []).
c([], []).
c([], [separator(0'\t)]).
c([row('é')], [separator(0'\t)]).
c([], [separator(0'\t)]).
c([row('b,c',[],'cr\rx'),r(a)], []).
c([r('q"q',42)], [separator(0'\t)]).
c([row([],12345678901234567890,1.5,'é'),r([]),row(12345678901234567890,1.5)], [separator(0';)]).
c([row(1.5,-3),row(1.5,a,a,'q"q'),r('tab\tx')], []).
c([r('tab\tx',1.5,' sp ','b,c'),r(1.5),row(1.0e10,-3)], [separator(0';)]).
c([], [separator(0';)]).
c([], [separator(0';)]).
c([row(1.0e10,'',a),r(42)], []).
c([r(x,'b,c','cr\rx','é')], [separator(0'\t)]).
c([row('cr\rx',1.5,'tab\tx',12345678901234567890)], []).
c([row(12345678901234567890),row('é',1.5,' sp ')], []).
c([r('tab\tx','tab\tx','tab\tx')], [separator(0';)]).
c([row('semi;colon','b,c','semi;colon','semi;colon'),r([]),row('line\nbreak','','é')], []).
c([row('q"q','semi;colon',a)], [separator(0';)]).
c([r(1.0e10),r('q"q')], []).
c([], [separator(0'\t)]).
c([row('tab\tx','line\nbreak','line\nbreak',[])], [separator(0';)]).
c([], []).
c([row(a,'',[],1.0e10),r([],'line\nbreak','semi;colon'),r('b,c','','b,c')], [separator(0'\t)]).
c([row('semi;colon','q"q'),row(a,'',1.0e10,'semi;colon')], [separator(0'\t)]).
c([row('cr\rx',12345678901234567890,'cr\rx','é')], [separator(0';)]).
c([], []).
c([row(' sp ','',42,-3),row(-3,-3,42),r('cr\rx')], [separator(0'\t)]).
c([row('line\nbreak'),r(12345678901234567890,a,' sp ','line\nbreak')], []).
c([r('b,c','cr\rx')], [separator(0'\t)]).
c([r('line\nbreak',12345678901234567890),r('line\nbreak')], [separator(0';)]).
c([r(-3,[],1.5)], [separator(0'\t)]).
c([r(1.0e10),r(12345678901234567890,'é'),r('q"q','semi;colon',x,1.5)], []).
c([r('tab\tx'),r(1.5)], []).
c([r(42,'é','cr\rx','')], []).
c([r([],-3,42,'q"q'),row('é','',a,-3)], [separator(0'\t)]).
c([row(1.5,'cr\rx',42)], [separator(0';)]).
c([], []).
c([row(a,1.5,12345678901234567890)], [separator(0'\t)]).
c([row('é',x),r('semi;colon','tab\tx','tab\tx',' sp '),r([],'cr\rx')], [separator(0'\t)]).
c([row(1.5,1.0e10),r('tab\tx')], []).
c([row('')], [separator(0'\t)]).
c([r('é',-3,42)], [separator(0'\t)]).
c([r('semi;colon',' sp ',a),row(42,'b,c',x,[])], [separator(0'\t)]).
c([row(1.0e10,a,x),r('b,c',x,'line\nbreak','semi;colon')], []).
c([row([],'semi;colon'),r('tab\tx','semi;colon',1.5)], [separator(0'\t)]).
c([row(1.5,42,'semi;colon')], []).
c([r(-3,1.0e10,'line\nbreak'),r(x,'cr\rx'),r(' sp ','semi;colon',-3)], [separator(0'\t)]).
c([r(12345678901234567890,12345678901234567890,'line\nbreak','semi;colon'),r('b,c','tab\tx')], []).
c([], [separator(0'\t)]).
c([r(' sp ')], []).
c([row('q"q',a,'semi;colon'),row('line\nbreak','',[]),row('',a,x)], [separator(0'\t)]).
c([row('line\nbreak'),r('q"q','line\nbreak',1.0e10),row(42)], [separator(0'\t)]).
c([r('cr\rx'),row(x,'line\nbreak','q"q',a)], []).
c([row(1.5,' sp ')], [separator(0';)]).
c([r(x,'b,c',42),row('line\nbreak','tab\tx','é',x),row('semi;colon')], []).
c([r('semi;colon')], []).
c([r('line\nbreak','é',a,'cr\rx'),r('b,c',a,1.5,'q"q'),row([])], [separator(0'\t)]).
c([r([],'',-3,-3),r('')], []).
c([r(' sp ')], []).
c([], [separator(0';)]).
c([row('q"q'),r(x,'é','cr\rx'),row('line\nbreak',' sp ')], []).
c([row('q"q','line\nbreak'),r(42)], []).
c([row('',x,'','tab\tx')], [separator(0';)]).
c([r(-3,1.0e10,'q"q',42),r(1.0e10,12345678901234567890,1.0e10),r(-3,x)], [separator(0'\t)]).
c([], [separator(0';)]).
c([r('tab\tx',[],'b,c',1.5)], [separator(0';)]).
c([], [separator(0'\t)]).
c([row([],'b,c','semi;colon','q"q'),r('','b,c',1.0e10)], [separator(0'\t)]).
c([], []).
c([r(1.0e10,'',[],x),r(12345678901234567890,-3,a),r(-3,1.5)], [separator(0'\t)]).
c([row('cr\rx',' sp ','b,c'),row(12345678901234567890,42,12345678901234567890,42),r('b,c','é')], [separator(0';)]).
c([r('cr\rx','é',[]),row(-3,42,'semi;colon'),r([],'semi;colon')], []).
c([r(42,12345678901234567890,42,1.5),r(1.0e10,' sp ','q"q',42),row('cr\rx',a,'é')], [separator(0';)]).
c([row(' sp ','cr\rx','line\nbreak',a),r(' sp ','b,c','cr\rx','tab\tx')], [separator(0';)]).
c([row([],1.5),r('','',' sp ','q"q'),row('é',1.5,'é',' sp ')], [separator(0';)]).
c([r(12345678901234567890,[],'é')], [separator(0';)]).
c([r('cr\rx',42,x,1.0e10),r(1.5,1.5),row('line\nbreak','semi;colon')], [separator(0';)]).
c([row(-3),row([])], []).
c([row('b,c','cr\rx'),r('','q"q','line\nbreak',-3)], [separator(0';)]).
c([r(' sp '),r('semi;colon',x)], []).
c([r(x,-3,x),row('line\nbreak',1.0e10,1.0e10)], []).
c([row('semi;colon','cr\rx'),row(-3,[],1.0e10),r(x)], [separator(0'\t)]).
c([r('b,c'),row('cr\rx','line\nbreak','line\nbreak'),r('tab\tx',1.5,'cr\rx','b,c')], [separator(0'\t)]).
c([r('tab\tx',[],12345678901234567890,'line\nbreak'),row(12345678901234567890,'b,c',' sp ','b,c'),r('b,c',' sp ')], []).
c([row('line\nbreak','semi;colon','é')], [separator(0';)]).
c([r(-3),r(1.5,a,42,'line\nbreak'),row([])], []).
c([], [separator(0'\t)]).
c([row('tab\tx',a),r('q"q')], []).
c([row('q"q',1.5),row('semi;colon'),r(1.0e10,'tab\tx')], [separator(0';)]).
c([], []).
c([row(' sp ',1.0e10),row('b,c',-3,'line\nbreak')], [separator(0';)]).
