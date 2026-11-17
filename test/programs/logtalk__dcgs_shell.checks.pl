% dcgs_10
expect(parse("pwd; cd ..; ls -a", L), L, [[pwd, 'cd ..', 'ls -a']]).
