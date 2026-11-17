% dcgs_02; dazu eine ungueltige Adresse
expect_count(valid("00:1e:4a:ef:72:8b"), 1).
expect_count(valid("00:1e:4a:ef:72:8g"), 0).
