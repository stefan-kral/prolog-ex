% csv-spectrum (github.com/max-mapper/csv-spectrum, BSD-2-Clause):
% erwartete Zeilen je Datei, aus deren JSON. Erzeugt von
% conformance/small/csvspec.py
spectrum('comma_in_quotes', [['first', 'last', 'address', 'city', 'zip'], ['John', 'Doe', '120 any st.', 'Anytown, WW', '08123']]).
spectrum('empty', [['a', 'b', 'c'], ['1', '', ''], ['2', '3', '4']]).
spectrum('empty_crlf', [['a', 'b', 'c'], ['1', '', ''], ['2', '3', '4']]).
spectrum('escaped_quotes', [['a', 'b'], ['1', 'ha "ha" ha'], ['3', '4']]).
spectrum('json', [['key', 'val'], ['1', '{"type": "Point", "coordinates": [102.0, 0.5]}']]).
spectrum('newlines', [['a', 'b', 'c'], ['1', '2', '3'], ['Once upon \na time', '5', '6'], ['7', '8', '9']]).
spectrum('newlines_crlf', [['a', 'b', 'c'], ['1', '2', '3'], ['Once upon \r\na time', '5', '6'], ['7', '8', '9']]).
spectrum('quotes_and_newlines', [['a', 'b'], ['1', 'ha \n"ha" \nha'], ['3', '4']]).
spectrum('simple', [['a', 'b', 'c'], ['1', '2', '3']]).
spectrum('simple_crlf', [['a', 'b', 'c'], ['1', '2', '3']]).
spectrum('utf8', [['a', 'b', 'c'], ['1', '2', '3'], ['4', '5', 'ʤ']]).
