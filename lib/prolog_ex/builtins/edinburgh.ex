defmodule PrologEx.Builtins.Edinburgh do
  @moduledoc """
  Altlasten aus DEC-10 Prolog (in SICStus und SWI eingebaut), hier erst nach
  dem Import der Heimat-Bibliothek sichtbar – für ältere Programme und
  Lehrbücher (Clocksin/Mellish, Bratko):

  `library(edinburgh_io)`, die Edinburgh-Ein-/Ausgabe:

    * `see(F)`: liest ab jetzt aus F. F ist `user` (Standardeingabe), ein
      Stream oder Alias, sonst ein Dateiname: beim ersten Mal geöffnet,
      danach (solange offen) derselbe Stream wieder – wie SWI.
    * `seen`: schließt die aktuelle Eingabe (außer Standardeingabe), dann
      wieder `user`. `seeing(F)`: der Dateiname, mit dem sie geöffnet wurde,
      `user` für die Standardeingabe, sonst der Stream.
    * `tell(F)`, `append(F)` (anhängen), `told`, `telling(F)` ebenso für die
      Ausgabe.

  Fehler wie `open/3`: Datei fehlt `existence_error(source_sink, F)`, nicht
  erlaubt `permission_error(open, source_sink, F)`.

  `library(edinburgh)` (mit `display/1,2`):

    * `name(AtomOderZahl, Codes)`: wie `atom_codes/2`, aber Text, der eine
      Zahl ist, wird zur Zahl (`name(X, "12")` gibt `X = 12`); statt Codes
      gehen auch Zeichen.
  """
  use PrologEx.Builtin
  alias PrologEx.{Error, Store}
  alias PrologEx.Stream, as: S

  # Datei => Stream, für see/tell auf denselben Namen
  @key :prolog_ex_edinburgh

  defp files, do: Process.get(@key, %{})

  defp remember(dir, path, id), do: Process.put(@key, Map.put(files(), {dir, path}, id))

  defp open?(id), do: id in S.all()

  # das Ziel von see/tell: {:user} | {:stream, id} | {:file, Pfad}
  defp target(f, s) do
    case Store.walk(f, s) do
      {:var, _} ->
        Error.instantiation!()

      {:atom, "user"} ->
        :user

      {tag, "$stream", _} = t when tag in [:struct, :gstruct] ->
        {:stream, S.lookup!(t)}

      {:atom, name} = t ->
        if S.alias_taken?(name), do: {:stream, S.lookup!(t)}, else: {:file, name}

      other ->
        try do
          {:file, PrologEx.Builtins.Modules.file_name(PrologEx.resolve(other, s))}
        rescue
          PrologEx.Error -> Error.domain!("source_sink", PrologEx.resolve(other, s))
        end
    end
  end

  defp redirect(f, s, dir, mode) do
    PrologEx.Effects.external!()

    id =
      case target(f, s) do
        :user ->
          if dir == :in, do: 0, else: 1

        {:stream, id} ->
          id

        {:file, path} ->
          full = Path.expand(path)

          case Map.fetch(files(), {dir, full}) do
            {:ok, id} ->
              if open?(id), do: id, else: open!(f, s, dir, full, mode)

            :error ->
              open!(f, s, dir, full, mode)
          end
      end

    if dir == :in, do: S.set_input(id), else: S.set_output(id)
    :ok
  end

  defp open!(f, s, dir, full, mode) do
    case S.open_file(full, mode, []) do
      {:ok, id} ->
        remember(dir, full, id)
        id

      {:error, :enoent} ->
        Error.existence!("source_sink", PrologEx.resolve(f, s))

      {:error, _} ->
        Error.permission!("open", "source_sink", PrologEx.resolve(f, s))
    end
  end

  defbuiltin "see", [f] do
    redirect(f, subst(), :in, :read)
  end

  defbuiltin "tell", [f] do
    redirect(f, subst(), :out, :write)
  end

  defbuiltin "append", [f] do
    redirect(f, subst(), :out, :append)
  end

  defbuiltin "seen", [] do
    close_current(S.current_input(), 0, :in)
  end

  defbuiltin "told", [] do
    close_current(S.current_output(), 1, :out)
  end

  defp close_current(id, std, dir) do
    PrologEx.Effects.external!()

    if id > 2 do
      S.close(id)
      Process.put(@key, Map.reject(files(), fn {{d, _}, v} -> d == dir and v == id end))
    end

    if dir == :in, do: S.set_input(std), else: S.set_output(std)
    :ok
  end

  defbuiltin "seeing", [f] do
    {:unify, [{f, current_name(S.current_input(), 0, :in)}]}
  end

  defbuiltin "telling", [f] do
    {:unify, [{f, current_name(S.current_output(), 1, :out)}]}
  end

  defp current_name(std, std, _dir), do: a("user")

  defp current_name(id, _std, dir) do
    case Enum.find(files(), fn {{d, _}, v} -> d == dir and v == id end) do
      {{_, path}, _} -> a(path)
      nil -> S.term(id)
    end
  end

  # name/2: Text, der als Zahl lesbar ist, wird zur Zahl
  defbuiltin "name", [x, codes] do
    s = subst()

    case Store.walk(x, s) do
      {:var, _} ->
        text = codes_text!(codes, s)

        case PrologEx.Builtins.Atoms.parse_number(text) do
          {:ok, n} -> {:unify, [{x, n}]}
          _ -> {:unify, [{x, a(text)}]}
        end

      {:atom, name} ->
        {:unify, [{codes, list(String.to_charlist(name))}]}

      n when is_number(n) ->
        {:unify, [{codes, list(String.to_charlist(PrologEx.Builtins.Atoms.number_string(n)))}]}

      {:rat, _, _} = r ->
        {:unify, [{codes, list(String.to_charlist(PrologEx.Builtins.Atoms.number_string(r)))}]}

      other ->
        Error.type!("atomic", PrologEx.resolve(other, s))
    end
  end

  defp codes_text!(t, s) do
    case Store.walk(t, s) do
      {:var, _} ->
        Error.instantiation!()

      [] ->
        ""

      {:glist, l} ->
        codes_text!(l, s)

      [h | tl] ->
        case Store.walk(h, s) do
          c when is_integer(c) and c >= 0 and c <= 0x10FFFF -> <<c::utf8>> <> codes_text!(tl, s)
          # auch Zeichen (double_quotes = chars: name(X, "12"))
          {:atom, <<_::utf8>> = c} -> c <> codes_text!(tl, s)
          {:var, _} -> Error.instantiation!()
          other -> Error.type!("integer", PrologEx.resolve(other, s))
        end

      other ->
        Error.type!("list", PrologEx.resolve(other, s))
    end
  end
end
