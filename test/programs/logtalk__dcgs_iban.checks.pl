% dcgs_20 (grosse Ganzzahlen); dazu eine falsche Pruefziffer
expect_count(valid("GB82 WEST 1234 5698 7654 32"), 1).
expect_count(valid("GB83 WEST 1234 5698 7654 32"), 0).
