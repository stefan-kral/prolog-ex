queens(N, Qs) :- length(Qs,N), place_queens(N,Qs,_Ups,_Downs).

place_queens(0,_Qs ,_Ups,_Downs).
place_queens(I,Qs,Ups, [_D|Downs]) :- I > 0, I1 is I-1, place_queens(I1,Qs, [_U|Ups] ,Downs), place_queen(I ,Qs,Ups,Downs).

place_queen(Q, [Q|_Qs] , [Q|_Ups] , [Q|_Downs]).
place_queen(Q, [_Q1|Qs], [_U|Ups] , [_D|Downs]) :- place_queen(Q,Qs,Ups,Downs).
