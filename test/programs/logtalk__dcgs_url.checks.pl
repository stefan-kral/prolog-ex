% dcgs_15 .. dcgs_19
expect(parse("https://logtalk.org", C), C, [[protocol(https), address([logtalk, org]), path([]), file('')]]).
expect(parse("https://logtalk.org/", C), C, [[protocol(https), address([logtalk, org]), path(['']), file('')]]).
expect(parse("https://logtalk.org/cvs", C), C, [[protocol(https), address([logtalk, org]), path([cvs]), file('')]]).
expect(parse("https://logtalk.org/cvs.html", C), C, [[protocol(https), address([logtalk, org]), path([]), file('cvs.html')]]).
expect(parse("https://logtalk.org/files/update", C), C, [[protocol(https), address([logtalk, org]), path([files, update]), file('')]]).
