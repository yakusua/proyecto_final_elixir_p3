defmodule Emergencias.Shelters.Server do
  @moduledoc """
  Proceso (GenServer) de **un** albergue; hay uno por albergue, creado bajo
  `Emergencias.Shelters.Pool` (un `DynamicSupervisor`).

  Los ingresos a albergues distintos se atienden en paralelo y los ingresos al mismo
  albergue se serializan, así la ocupación nunca supera la capacidad. Cada cambio se
  guarda en `data/shelters/<CODIGO>.txt`; si el proceso se cae, el supervisor lo
  reinicia y recupera su último estado desde ese archivo.
  """

  use GenServer

  alias Emergencias.Storage
  alias Emergencias.Shelters.Shelter

  def start_link(%Shelter{} = shelter),
    do: GenServer.start_link(__MODULE__, shelter, name: via(shelter.code))

  def via(code), do: {:via, Registry, {Emergencias.Shelters.Registry, code}}

  defp file(code), do: "shelters/" <> code

  @impl true
  def init(%Shelter{code: code} = initial) do
    shelter =
      case Storage.load_or(file(code), nil) do
        nil -> initial
        record -> Shelter.from_record(record)
      end

    _ = Storage.save(file(code), Shelter.to_record(shelter))
    {:ok, shelter}
  end

  @impl true
  def handle_call({:enter, document}, _from, shelter),
    do: transition(shelter, Shelter.enter(shelter, document))

  def handle_call({:leave, document}, _from, shelter),
    do: transition(shelter, Shelter.leave(shelter, document))

  def handle_call(:get, _from, shelter), do: {:reply, {:ok, shelter}, shelter}

  defp transition(old, {:ok, new}),
    do: Storage.commit(file(old.code), old, new, {:ok, new}, &Shelter.to_record/1)

  defp transition(old, {:error, _} = error), do: {:reply, error, old}
end
