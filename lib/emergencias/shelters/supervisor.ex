defmodule Emergencias.Shelters.Supervisor do
  @moduledoc """
  Supervisor de los albergues:

    1. `Emergencias.Shelters.Registry`: nombres de los procesos de albergue.
    2. `Emergencias.Shelters.Pool`: `DynamicSupervisor` con un proceso por albergue.
    3. Una tarea que, al arrancar, **restaura** los albergues guardados en disco.

  Usa `:rest_for_one`: si el registro o el `DynamicSupervisor` se reinician (y
  pierden a sus hijos), la tarea de restauración se ejecuta de nuevo.
  """

  use Supervisor

  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Emergencias.Shelters.Registry},
      {DynamicSupervisor, name: Emergencias.Shelters.Pool, strategy: :one_for_one},
      Supervisor.child_spec({Task, &Emergencias.Shelters.restore_all/0},
        id: :restorer,
        restart: :transient
      )
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
