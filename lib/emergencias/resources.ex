defmodule Emergencias.Resources do
  @moduledoc "Contexto de recursos y centros de apoyo: validación de entradas y fachada del servidor de inventario."

  alias Emergencias.{Text, Validation, Zones}
  alias Emergencias.Resources.{Inventory, Resource, Server}

  @doc "Registra un recurso. Claves: `:code`, `:category`, `:quantity`, `:unit`, `:location`, `:zone`, opcional `:name`."
  @spec register(map(), String.t()) :: {:ok, Resource.t()} | {:error, term()}
  def register(attrs, actor) do
    with {:ok, code} <- Validation.code(attrs[:code], :code, :up),
         {:ok, category} <- category(attrs[:category]),
         {:ok, name} <- Validation.text(attrs[:name] || attrs[:category], :name),
         {:ok, quantity} <- Validation.non_negative_integer(attrs[:quantity], :quantity),
         {:ok, unit} <- Validation.text(attrs[:unit], :unit),
         {:ok, location} <- Validation.code(attrs[:location], :location),
         {:ok, zone} <- Validation.code(attrs[:zone], :zone),
         :ok <- Zones.ensure_exists(zone) do
      resource = %Resource{
        code: code,
        name: name,
        category: category,
        unit: String.downcase(unit),
        location: location,
        zone: zone,
        quantity: quantity
      }

      Server.register(resource, actor)
    end
  end

  @doc "Entrada de inventario de un recurso ya registrado."
  @spec add_stock(String.t(), String.t(), term(), String.t()) ::
          {:ok, Resource.t()} | {:error, term()}
  def add_stock(code, location, quantity, actor),
    do: stock_change(&Server.add/4, code, location, quantity, actor)

  @doc "Salida de inventario."
  @spec remove_stock(String.t(), String.t(), term(), String.t()) ::
          {:ok, Resource.t()} | {:error, term()}
  def remove_stock(code, location, quantity, actor),
    do: stock_change(&Server.remove/4, code, location, quantity, actor)

  defp stock_change(operation, code, location, quantity, actor) do
    with {:ok, code} <- Validation.code(code, :code, :up),
         {:ok, location} <- Validation.code(location, :location),
         {:ok, quantity} <- Validation.positive_integer(quantity, :quantity) do
      operation.(code, location, quantity, actor)
    end
  end

  @doc "Transfiere inventario entre centros de apoyo; `zone` (opcional) es la zona del destino si es nuevo."
  @spec transfer(String.t(), String.t(), String.t(), term(), String.t() | nil, String.t()) ::
          {:ok, Resource.t()} | {:error, term()}
  def transfer(code, from, to, quantity, zone, actor) do
    with {:ok, code} <- Validation.code(code, :code, :up),
         {:ok, from} <- Validation.code(from, :origin),
         {:ok, to} <- Validation.code(to, :destination),
         {:ok, zone} <- Validation.optional(zone, &Validation.code(&1, :zone)),
         {:ok, quantity} <- Validation.positive_integer(quantity, :quantity) do
      Server.transfer(code, from, to, quantity, zone, actor)
    end
  end

  @doc "Descuento atómico para una necesidad (lo invoca `Emergencias.Needs.Server`)."
  @spec allocate(String.t(), pos_integer(), String.t(), String.t(), String.t()) ::
          {:ok, [Inventory.allocation()]} | {:error, term()}
  def allocate(category, quantity, zone, need_id, actor) do
    Emergencias.Server.safe(fn -> Server.allocate(category, quantity, zone, need_id, actor) end)
  end

  @doc "Devuelve lo asignado al inventario (al cancelar una necesidad)."
  @spec release([Inventory.allocation()], String.t(), String.t()) :: :ok | {:error, term()}
  def release(allocations, need_id, actor) do
    Emergencias.Server.safe(fn -> Server.release(allocations, need_id, actor) end)
  end

  @doc "Existencias filtradas por `:category`, `:zone`, `:location` y/o `:code` (valores en texto libre)."
  @spec list(keyword()) :: [Resource.t()]
  def list(filters \\ []), do: Server.query(&Inventory.list(&1, normalize(filters)))

  @doc "Total por categoría, opcionalmente de una zona."
  @spec totals(String.t() | nil) :: %{String.t() => non_neg_integer()}
  def totals(zone \\ nil), do: Server.query(&Inventory.totals_by_category(&1, zone))

  @doc "Normaliza una categoría libre: `\"Primeros Auxilios\"` -> `\"primeros_auxilios\"`."
  @spec category(term()) :: {:ok, String.t()} | {:error, term()}
  def category(value),
    do: with({:ok, text} <- Validation.text(value, :category), do: {:ok, Text.slug(text)})

  defp normalize(filters) do
    Enum.map(filters, fn
      {:category, v} when is_binary(v) -> {:category, Text.slug(v)}
      {:code, v} when is_binary(v) -> {:code, String.upcase(v)}
      {key, v} when is_binary(v) -> {key, String.downcase(v)}
      other -> other
    end)
  end
end
