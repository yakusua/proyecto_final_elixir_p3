defmodule Emergencias.CLI.REPL do
  @moduledoc """
  Consola interactiva. Comandos propios: `connect`, `disconnect` y `quit`; el resto
  se ejecuta con la sesión del usuario conectado. Conectarse con otro usuario cierra
  la sesión anterior (ver `Emergencias.CLI.Spec` para la lista de comandos).
  """

  alias Emergencias.CLI.{Formatter, Parser}

  @usage_connect "connect <usuario> <contraseña> [tipo] [zona] [nombre=...]"

  @spec run() :: :ok
  def run do
    IO.puts("Gestión de emergencias. #{@usage_connect} · disconnect · quit")
    loop(nil)
  end

  # Bucle principal (recursivo): lee una línea, la procesa y continúa con el usuario actual.
  defp loop(user) do
    case IO.gets(prompt(user)) do
      line when is_binary(line) ->
        case handle(String.trim(line), user) do
          {:cont, next_user} -> loop(next_user)
          :halt -> finish(user)
        end

      _eof_or_error ->
        finish(user)
    end
  end

  defp handle("", user), do: {:cont, user}

  defp handle(line, user) do
    case line |> String.split(~r/\s+/, parts: 2) |> hd() |> String.downcase() do
      word when word in ["quit", "exit"] -> :halt
      "connect" -> {:cont, connect(line, user)}
      "disconnect" -> {:cont, disconnect(user)}
      _ -> {:cont, execute(line, user)}
    end
  end

  defp connect(line, user) do
    with {:ok, [{:arg, _} | tokens]} <- Parser.tokenize(line),
         [username, password | extra] <- for({:arg, value} <- tokens, do: value) do
      opts = for {:opt, key, value} <- tokens, into: %{}, do: {key, value}
      attrs = %{role: Enum.at(extra, 0), zone: Enum.at(extra, 1), full_name: opts["nombre"]}

      case Emergencias.connect(username, password, attrs) do
        {:ok, connected, status} ->
          if user && user != connected.username, do: Emergencias.disconnect(user)

          IO.puts(
            "✓ #{connected.username} #{if status == :registered, do: "registrado y conectado", else: "conectado"} como #{connected.role}."
          )

          connected.username

        {:error, reason} ->
          print_error(reason)
          user
      end
    else
      _ ->
        print_error({:usage, @usage_connect})
        user
    end
  end

  defp disconnect(nil), do: print_error(:not_connected)

  defp disconnect(user) do
    Emergencias.disconnect(user)
    IO.puts("✓ #{user} desconectado.")
    nil
  end

  defp execute(_line, nil), do: print_error(:not_connected)

  defp execute(line, user) do
    user |> Emergencias.execute(line) |> Formatter.render() |> IO.puts()
    user
  end

  defp print_error(reason) do
    IO.puts(Formatter.render({:error, reason}))
    nil
  end

  defp prompt(nil), do: "emergencias> "
  defp prompt(user), do: "#{user}> "

  defp finish(user) do
    if user, do: Emergencias.disconnect(user)
    IO.puts("Hasta pronto.")
  end
end
