# Herkunft der Testdaten

* `utf8_kuhn.pl`: aus Markus Kuhn, „UTF-8 decoder capability and stress
  test“ (UTF-8-test.txt, Fassung 2015-08-24),
  https://www.cl.cam.ac.uk/~mgk25/ucs/examples/UTF-8-test.txt –
  Creative Commons Attribution 4.0 (CC BY 4.0). Je Zeile die Bytes, dazu
  die erwarteten Codes nach Python (streng; mit U+FFFD je größtem
  ungültigem Teilstück). Erzeugt von `conformance/small/kuhn.py`.
* `csv/*.csv`, `csv_spectrum.pl`: aus csv-spectrum von Max Ogden,
  https://github.com/max-mapper/csv-spectrum (Stand d30e80f),
  BSD-2-Clause (laut package.json). Die erwarteten Zeilen stammen aus den
  JSON-Dateien des Projekts (`conformance/small/csvspec.py`);
  `location_coordinates` fehlt, weil dessen JSON nicht zur CSV-Datei passt.
* `case_ucd17.pl`: aus der Unicode Character Database 17.0
  (UnicodeData.txt, SpecialCasing.txt), © Unicode, Inc., Unicode License
  v3 (https://www.unicode.org/license.txt). Erzeugt von
  `conformance/small/ucd.py`.
* `crypto_vectors.pl`: Auszug (je Datei höchstens 8) aus
  pyca/cryptography_vectors 50.0.2 (https://pypi.org/project/cryptography-vectors/,
  Apache-2.0 oder BSD-3-Clause; darin NIST CAVP, RFC 4231, RFC 5869,
  RFC 7748, RFC 8032, Testdaten von OpenSSL und BoringSSL), dazu
  PBKDF2-HMAC-SHA512 nach Pythons hashlib und Vielfache auf secp256k1 aus
  einer eigenen Python-Rechnung. Erzeugt von
  `conformance/crypto_vectors/gen.py VEKTOREN 8`.
