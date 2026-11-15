defmodule Emergencias.Needs do
  @moduledoc """
  Contexto de necesidades puntuales: valida entradas, comprueba referencias a otras
  partes del sistema (zona, albergue) y delega el estado a `Emergencias.Needs.Server`.
  """

  alias Emergencias.{Resources, Shelters, Types, Validation, Zones}
  alias Emergencias.Needs.{Need, Server}

  @doc "Registra una necesidad. Claves: `:type`, `:quantity`, `:priority`, `:zone`, `:description`, `:shelter`, `:person`."
  @spec register(map(), String.t()) :: {:ok, Need.t()} | {:error, term()}
  def register(attrs, actor) do
    with {:ok, valid} <- Need.validate(attrs),
         :ok <- Zones.ensure_exists(valid.zone),
         :ok <- if(valid.shelter, do: Shelters.ensure_exists(valid.shelter), else: :ok) do
      Server.register(valid, actor)
    end
  end

  @doc "Asigna `quantity` unidades de la categoría de inventario a la necesidad."
  @spec assign_resource(String.t(), String.t(), term(), String.t()) ::
          {:ok, Need.t()} | {:error, term()}
  def assign_resource(id, category, quantity, actor) do
    with {:ok, id} <- Validation.code(id, :need_id, :up),
         {:ok, category} <- Resources.category(category),
         {:ok, quantity} <- Validation.positive_integer(quantity, :quantity) do
      Server.assign(id, category, quantity, actor)
    end
  end

  @doc "Cambia el estado respetando las transiciones válidas (cerrar dos veces es un error)."
  @spec update_status(String.t(), String.t() | atom(), String.t()) ::
          {:ok, Need.t()} | {:error, term()}
  def update_status(id, status, actor) do
    with {:ok, id} <- Validation.code(id, :need_id, :up),
         {:ok, status} <- Types.parse(:need_status, status) do
      Server.transition(id, status, actor)
    end
  end

  @doc "Consulta por `:zone`, `:type`, `:priority`, `:status` y `:shelter`; el resultado viene ordenado por prioridad."
  @spec list(keyword()) :: {:ok, [Need.t()]} | {:error, term()}
  def list(filters \\ []) do
    with {:ok, zone} <- Validation.optional(filters[:zone], &Validation.code(&1, :zone)),
         {:ok, shelter} <-
           Validation.optional(filters[:shelter], &Validation.code(&1, :shelter, :up)),
         {:ok, type} <- Types.parse_optional(:need_type, filters[:type]),
         {:ok, priority} <- Types.parse_optional(:priority, filters[:priority]),
         {:ok, status} <- Types.parse_optional(:need_status, filters[:status]) do
      {:ok,
       Server.list(zone: zone, shelter: shelter, type: type, priority: priority, status: status)}
    end
  end

  @doc "Necesidades pendientes, en orden de atención."
  @spec pending(keyword()) :: {:ok, [Need.t()]} | {:error, term()}
  def pending(filters \\ []), do: list(Keyword.put(filters, :status, :pendiente))
end
