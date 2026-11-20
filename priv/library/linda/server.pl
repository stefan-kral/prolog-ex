/* library(linda/server): der Server-Teil von library(linda), unter dem
   Namen von SICStus (use_module(library('linda/server'))) (PrologEx) */

:- module(linda_server, [linda/0, linda/1]).

:- use_module(library(linda), []).

:- meta_predicate(linda(:)).

linda :- linda:linda.
linda(Options) :- linda:linda(Options).
