% dcgs_13, dcgs_14
expect(convert(word(child, children), word(singular, plural), X), X,
       ['<word><singular>child</singular><plural>children</plural></word>']).
expect(convert(T, I, '<word><singular>child</singular><plural>children</plural></word>'), T-I,
       [word(child, children)-word(singular, plural)]).
