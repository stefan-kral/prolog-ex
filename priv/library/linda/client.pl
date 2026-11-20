/* library(linda/client): der Client-Teil von library(linda), unter dem
   Namen von SICStus (use_module(library('linda/client'))) (PrologEx) */

:- module(linda_client, [linda_client/1, close_client/0, shutdown_server/0,
                         linda_timeout/2, out/1, in/1, in/2, in_noblock/1,
                         rd/1, rd/2, rd_noblock/1, bagof_rd_noblock/3]).

:- use_module(library(linda), []).

:- meta_predicate(bagof_rd_noblock(?, ^, -)).

linda_client(Address) :- linda:linda_client(Address).
close_client :- linda:close_client.
shutdown_server :- linda:shutdown_server.
linda_timeout(Old, New) :- linda:linda_timeout(Old, New).
out(Tuple) :- linda:out(Tuple).
in(Tuple) :- linda:in(Tuple).
in(TupleList, Tuple) :- linda:in(TupleList, Tuple).
in_noblock(Tuple) :- linda:in_noblock(Tuple).
rd(Tuple) :- linda:rd(Tuple).
rd(TupleList, Tuple) :- linda:rd(TupleList, Tuple).
rd_noblock(Tuple) :- linda:rd_noblock(Tuple).
bagof_rd_noblock(Template, Tuple, Bag) :- linda:bagof_rd_noblock(Template, Tuple, Bag).
