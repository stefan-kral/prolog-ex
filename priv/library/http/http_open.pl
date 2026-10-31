/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Written 2022 by Adrián Arroyo Calle (adrian.arroyocalle@gmail.com)
   Part of Scryer Prolog (Lizenz: priv/library/SCRYER-LICENSE).

   Angepasst für PrologEx: '$http_open'/7 ist in Elixir (OTP :httpc statt
   reqwest). Abweichung: size(-Size) liefert die Länge aus Content-Length
   als Ganzzahl und funktioniert auch ohne headers/1 (bei Scryer wurde
   member/2 auf der noch ungebundenen Header-Liste aufgerufen).
*/

/** Make HTTP requests.

This library contains the predicate `http_open/3` which allows you to perform HTTP(S) calls.
Useful for making API calls, or parsing websites.
*/

:- module(http_open, [http_open/3]).

:- use_module(library(lists)).

%% http_open(+Address, -Stream, +Options).
%
% Yields Stream to read the body of an HTTP reply from Address.
% Address is a list of characters, and includes the method. Both HTTP
% and HTTPS are supported. Redirects are followed. Fails if no reply
% is received (unknown host, refused connection, TLS error).
%
% Options supported:
%
%   * `method(+Method)`: Sets the HTTP method of the call. Method can be `get` (default), `head`, `delete`, `post`, `put` or `patch`.
%   * `data(+Data)`: Data to be sent in the request. Useful for POST, PUT and PATCH operations.
%   * `size(-Size)`: Unifies with the value of the Content-Length header (an integer)
%   * `request_headers(+RequestHeaders)`: Headers to be used in the request
%   * `headers(-ListHeaders)`: Unifies with a list with all headers returned in the response
%   * `status_code(-Code)`: Unifies with the status code of the request (200, 201, 404, ...)
%
% Example:
%
% ```
% ?- http_open("https://www.example.com", S, []), get_n_chars(S, N, HTML).
%    S = '$stream'(5), N = 1256, HTML = "<!doctype html>\n<ht ...".
% ```
http_open(Address, Response, Options) :-
    parse_http_options(Options, OptionValues),
    ( member(method(Method), OptionValues) -> true; Method = get),
    ( member(data(Data), OptionValues) -> true; Data = []),
    ( member(request_headers(RequestHeaders), OptionValues) -> true; RequestHeaders = ['user-agent'("Scryer Prolog")]),
    ( member(status_code(Code), OptionValues) -> true; true),
    ( member(headers(Headers), OptionValues) -> true; true),
    '$http_open'(Address, Response, Method, Code, Data, Headers, RequestHeaders),
    (   member(size(Size), OptionValues),
        member('content-length'(Cs), Headers) ->
        number_chars(Size, Cs)
    ;   true
    ).

parse_http_options(Options, OptionValues) :-
    maplist(parse_http_options_, Options, OptionValues).

parse_http_options_(method(Method), method(Method)) :-
    (  var(Method) ->
       throw(error(instantiation_error, http_open/3))
    ;
       member(Method, [get, post, put, delete, patch, head]) -> true
    ;
       throw(error(domain_error(http_option, method(Method)), _))
    ).

parse_http_options_(data(Data), data(Data)) :-
    (  var(Data) ->
       throw(error(instantiation_error, http_open/3))
    ;  true
    ).

parse_http_options_(request_headers(Headers), request_headers(Headers)) :-
    (  var(Headers) ->
       throw(error(instantiation_error, http_open/3))
    ;  true
    ).

parse_http_options_(size(Size), size(Size)).
parse_http_options_(status_code(Code), status_code(Code)).
parse_http_options_(headers(Headers), headers(Headers)).
