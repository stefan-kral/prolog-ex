% dcgs_05, dcgs_06 (die erste Loesung, wie lgtunit)
expect_first(parse([the, girl, likes, the, boy], R), R, true).
expect_first(parse([the, girl, scares, the, boy], R), R, false).
