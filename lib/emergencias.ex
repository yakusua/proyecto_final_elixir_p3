defmodule Emergencias do
  @moduledoc """
  Sistema distribuido de coordinación y gestión de emergencias posteriores a un
  terremoto. Punto de entrada: conexión de usuarios y ejecución de comandos.

      {:ok, _user, :registered} = Emergencias.connect("laura", "1234", %{role: "coordinador", zone: "centro"})
      Emergencias.execute("laura", ~s(register_zone centro "Centro" critico))

  Capas: `CLI` (parser, comandos, formato) -> contextos (`Accounts`, `Zones`, `Needs`,
  `Resources`, `Family`, `Pets`, `Shelters`, `Reports`) -> `*.Server` (GenServer con
  estado y persistencia) -> núcleo puro (`Zones.Tree`, `Resources.Inventory`,
  `Needs.Need`, `Pets.Matcher`, ...).
  """

  alias Emergencias.Accounts
  alias Emergencias.CLI.Commands

  defdelegate connect(username, password, attrs \\ %{}), to: Accounts
  defdelegate disconnect(username), to: Accounts

  @doc "Ejecuta un comando (texto) con la sesión del usuario conectado."
  @spec execute(String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def execute(username, input) do
    case Accounts.session(username) do
      {:ok, user} -> Commands.execute(user, input)
      :error -> {:error, :not_connected}
    end
  end
end
