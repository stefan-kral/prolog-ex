% Anzahlen: OEIS A001006 (Motzkin), n = 0..12.
expect_count(motzkin(0, _), 1).
expect_count(motzkin(1, _), 1).
expect_count(motzkin(2, _), 2).
expect_count(motzkin(3, _), 4).
expect_count(motzkin(4, _), 9).
expect_count(motzkin(5, _), 21).
expect_count(motzkin(6, _), 51).
expect_count(motzkin(7, _), 127).
expect_count(motzkin(8, _), 323).
expect_count(motzkin(9, _), 835).
expect_count(motzkin(10, _), 2188).
expect_count(motzkin(11, _), 5798).
expect_count(motzkin(12, _), 15511).
