defmodule Emergencias.CLI.Parser do
  @moduledoc """
  Interpreta una línea de texto como comando `%{name:, args:, opts:, raw:}`.

    * Las palabras se separan por espacios; las comillas (simples o dobles) agrupan
      texto con espacios: `send_family_message 1001 "Estoy bien"`.
    * `clave=valor` (o `clave="valor con espacios"`) es una opción:
      `list_needs zona=centro prioridad=critica`.
    * El primer token es el nombre del comando, que se busca en una tabla cerrada
      (`Emergencias.CLI.Spec`): nunca se crean átomos desde la entrada.

  `tokenize/1` es recursiva sobre el binario (coincidencia de patrones carácter a carácter).
  """

  alias Emergencias.CLI.Spec

  @type token :: {:arg, String.t()} | {:opt, String.t(), String.t()}

  @spec parse(String.t()) :: {:ok, map()} | {:error, term()}
  def parse(line) when is_binary(line) do
    with {:ok, tokens} <- tokenize(line),
         {:ok, name, rest} <- split_name(tokens) do
      {:ok,
       %{
         name: name,
         args: for({:arg, value} <- rest, do: value),
         opts: for({:opt, key, value} <- rest, into: %{}, do: {key, value}),
         raw: String.trim(line)
       }}
    end
  end

  @doc "Divide la línea en tokens respetando comillas y opciones `clave=valor`."
  @spec tokenize(String.t()) :: {:ok, [token()]} | {:error, :unclosed_quote}
  def tokenize(line), do: scan(line, new_token(), [], nil)

  defp split_name([]), do: {:error, :empty}

  defp split_name([{:arg, word} | rest]) do
    case Spec.lookup(word) do
      {:ok, name} -> {:ok, name, rest}
      :error -> {:error, {:unknown_command, word}}
    end
  end

  defp split_name([{:opt, key, _} | _]), do: {:error, {:unknown_command, key}}

  # Analizador léxico recursivo. Estado: texto restante, token en construcción,
  # tokens completos (en orden inverso) y comilla abierta (nil si no hay).
  defp new_token, do: %{key: nil, value: "", present?: false, quoted?: false}

  defp scan(<<>>, _token, _acc, quote) when quote != nil, do: {:error, :unclosed_quote}
  defp scan(<<>>, token, acc, nil), do: {:ok, Enum.reverse(push(token, acc))}

  # Cierre de comillas.
  defp scan(<<q, rest::binary>>, token, acc, q), do: scan(rest, token, acc, nil)

  # Apertura de comillas.
  defp scan(<<q, rest::binary>>, token, acc, nil) when q in [?", ?'],
    do: scan(rest, %{token | present?: true, quoted?: true}, acc, q)

  # Dentro de comillas todo es literal.
  defp scan(<<c::utf8, rest::binary>>, token, acc, quote) when quote != nil,
    do: scan(rest, append(token, c), acc, quote)

  # Espacio fuera de comillas: termina el token.
  defp scan(<<c, rest::binary>>, token, acc, nil) when c in [?\s, ?\t, ?\n, ?\r],
    do: scan(rest, new_token(), push(token, acc), nil)

  # "=" fuera de comillas: si lo anterior parece una clave, el token es una opción.
  defp scan(<<?=, rest::binary>>, %{key: nil, quoted?: false, value: value} = token, acc, nil) do
    if Regex.match?(~r/^[a-z_]+$/, value),
      do: scan(rest, %{token | key: value, value: "", present?: true}, acc, nil),
      else: scan(rest, append(token, ?=), acc, nil)
  end

  defp scan(<<c::utf8, rest::binary>>, token, acc, nil),
    do: scan(rest, append(token, c), acc, nil)

  defp append(token, codepoint),
    do: %{token | value: token.value <> <<codepoint::utf8>>, present?: true}

  defp push(%{present?: false}, acc), do: acc
  defp push(%{key: nil, value: value}, acc), do: [{:arg, value} | acc]
  defp push(%{key: key, value: value}, acc), do: [{:opt, key, value} | acc]
end
