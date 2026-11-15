defmodule Emergencias.Shelters do
  @moduledoc "Contexto de albergues: cada albergue vive en su propio proceso supervisado."

  alias Emergencias.{Storage, Validation, Zones}
  alias Emergencias.Shelters.{Server, Shelter}

  @pool Emergencias.Shelters.Pool
  @registry Emergencias.Shelters.Registry

  @doc "Registra un albergue. Claves: `:code`, `:name`, `:zone`, `:capacity` (la ocupación inicial es 0)."
  @spec register(map()) :: {:ok, Shelter.t()} | {:error, term()}
  def register(attrs) do
    with {:ok, code} <- Validation.code(attrs[:code], :code, :up),
         {:ok, name} <- Validation.text(attrs[:name], :name),
         {:ok, zone} <- Validation.code(attrs[:zone], :zone),
         :ok <- Zones.ensure_exists(zone),
         {:ok, capacity} <- Validation.positive_integer(attrs[:capacity], :capacity) do
      shelter = %Shelter{code: code, name: name, zone: zone, capacity: capacity}

      case DynamicSupervisor.start_child(@pool, {Server, shelter}) do
        {:ok, _pid} -> {:ok, shelter}
        {:error, {:already_started, _pid}} -> {:error, {:duplicate, :shelter, code}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "Ingreso de una persona (por documento)."
  @spec enter(String.t(), String.t()) :: {:ok, Shelter.t()} | {:error, term()}
  def enter(code, document), do: person_call(code, document, :enter)

  @doc "Salida de una persona (por documento)."
  @spec leave(String.t(), String.t()) :: {:ok, Shelter.t()} | {:error, term()}
  def leave(code, document), do: person_call(code, document, :leave)

  @spec get(String.t()) :: {:ok, Shelter.t()} | {:error, term()}
  def get(code), do: call(code, :get)

  @spec ensure_exists(String.t()) :: :ok | {:error, term()}
  def ensure_exists(code), do: with({:ok, _} <- get(code), do: :ok)

  @doc "Todos los albergues, ordenados por código."
  @spec list() :: [Shelter.t()]
  def list do
    @registry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.flat_map(fn code ->
      case get(code) do
        {:ok, shelter} -> [shelter]
        _ -> []
      end
    end)
    |> Enum.sort_by(& &1.code)
  end

  @doc "Albergues con mayor nivel de ocupación (porcentaje, luego personas)."
  @spec top_occupancy(pos_integer()) :: [Shelter.t()]
  def top_occupancy(limit) do
    list()
    |> Enum.sort_by(&{-Shelter.occupancy_percent(&1), -Shelter.occupancy(&1), &1.code})
    |> Enum.take(limit)
  end

  @doc "Arranca los procesos de los albergues guardados en disco (lo invoca el supervisor)."
  @spec restore_all() :: :ok
  def restore_all do
    for name <- Storage.list("shelters"),
        record = Storage.load_or("shelters/" <> name, nil),
        record != nil do
      DynamicSupervisor.start_child(@pool, {Server, Shelter.from_record(record)})
    end

    :ok
  end

  defp person_call(code, document, operation) do
    with {:ok, document} <- Validation.code(document, :document, :keep),
         do: call(code, {operation, document})
  end

  defp call(code, message) when is_binary(code) do
    code = code |> String.trim() |> String.upcase()

    case Registry.lookup(@registry, code) do
      [{pid, _}] -> Emergencias.Server.safe(fn -> GenServer.call(pid, message, 10_000) end)
      [] -> {:error, {:not_found, :shelter, code}}
    end
  end
end
