defmodule Emergencias.Application do
  @moduledoc """
  Árbol de supervisión:

      Emergencias.Supervisor (one_for_one)
      ├── Accounts.Server      GenServer: usuarios, conexiones y bitácora
      ├── Zones.Server         GenServer: zona -> sectores -> puntos de atención
      ├── Resources.Server     GenServer: inventario (asignación atómica)
      ├── Needs.Server         GenServer: necesidades
      ├── Family.Server        GenServer: personas y mensajes
      ├── Pets.Server          GenServer: mascotas
      └── Shelters.Supervisor  (rest_for_one)
          ├── Registry
          ├── Pool             DynamicSupervisor -> un GenServer por albergue
          └── (tarea)          restaura los albergues guardados en disco

  Cada servidor guarda su estado en disco: si uno se cae, se reinicia solo y
  recupera su último estado sin afectar a los demás.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Emergencias.Accounts.Server,
      Emergencias.Zones.Server,
      Emergencias.Resources.Server,
      Emergencias.Needs.Server,
      Emergencias.Family.Server,
      Emergencias.Pets.Server,
      Emergencias.Shelters.Supervisor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Emergencias.Supervisor)
  end
end
