% Anzahlen: OEIS A000110 (Bell), n = 0..9.
expect_count(set_partition(0, _), 1).
expect_count(set_partition(1, _), 1).
expect_count(set_partition(2, _), 2).
expect_count(set_partition(3, _), 5).
expect_count(set_partition(4, _), 15).
expect_count(set_partition(5, _), 52).
expect_count(set_partition(6, _), 203).
expect_count(set_partition(7, _), 877).
expect_count(set_partition(8, _), 4140).
expect_count(set_partition(9, _), 21147).
