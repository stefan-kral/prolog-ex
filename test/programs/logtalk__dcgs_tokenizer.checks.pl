% dcgs_11 (Zahlen numerisch verglichen)
expect((tokens(" We owe $1,048,576.24 to Agent 007 for Version 3.14159! ", Ts),
        Ts = [T1, T2, T3, T4, T5, T6, T7, T8, T9, T10, T11],
        T4 =:= 1048576.24, T10 =:= 3.14159),
       [T1, T2, T3, T5, T6, T7, T8, T9, T11],
       [[we, owe, '$', to, agent, 7, for, version, !]]).
