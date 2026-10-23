# Integrationstests mit gprolog nur, wenn der Reader übersetzt ist
# (mix prolog.build_reader).
if PrologEx.Reader.available?() do
  ExUnit.start()
else
  IO.puts("Hinweis: gprolog-Reader fehlt, Integrationstests (:gprolog) werden übersprungen")
  ExUnit.start(exclude: [:gprolog])
end
